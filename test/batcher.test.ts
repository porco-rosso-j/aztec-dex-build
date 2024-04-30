import {
	Fr,
	PXE,
	createPXEClient,
	AztecAddress,
	AccountWalletWithPrivateKey,
	initAztecJs,
	GrumpkinScalar,
	generatePublicKey,
} from "@aztec/aztec.js";
import { jest, beforeAll, it, describe, expect } from "@jest/globals";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { BatcherVaultContract } from "./artifacts/BatcherVault.js";
import { AMMMockContract } from "./artifacts/AMMMock.js";
import { TokenContract } from "@aztec/noir-contracts.js";
import {
	deployAMMMock,
	deployTokensAndMint,
	publicDeployAccounts,
} from "./utils/deploy.js";
import {
	ADDRESS_ZERO,
	BONDING_AMOUNT,
	HE_PRIVATE_KEY,
	HE_PUBLIC_KEY,
	INTERVAL,
	RAND_INIT,
	SANDBOX_URL,
	SK_HASH,
} from "./utils/constants.js";
import { computePartialAddress } from "@aztec/circuits.js";

let pxe: PXE;
let batcher: BatcherVaultContract;

let admin_relayer: AccountWalletWithPrivateKey;
let userA: AccountWalletWithPrivateKey;
let userB: AccountWalletWithPrivateKey;

let eth: TokenContract;
let dai: TokenContract;
let amm: AMMMockContract;

let encrypted_amount: Fr[];

const TIMEOUT = 360_000;

beforeAll(async () => {
	pxe = createPXEClient(SANDBOX_URL);

	await initAztecJs();
	const accounts = await getInitialTestAccountsWallets(pxe);
	admin_relayer = accounts[0];
	userA = accounts[1];
	userB = accounts[2];

	console.log("admin_relayer: ", admin_relayer.getAddress());

	await publicDeployAccounts(admin_relayer, [admin_relayer, userA, userB]);

	const [ethContract, daiContract] = await deployTokensAndMint(
		admin_relayer,
		admin_relayer.getAddress(),
		userA,
		userB
	);

	eth = ethContract;
	dai = daiContract;

	console.log("eth add: ", eth.address);
	console.log("dai add: ", dai.address);

	amm = await deployAMMMock(
		admin_relayer,
		admin_relayer.getAddress(),
		eth,
		dai.address
	);
}, 360_000);

describe("E2E Batcher setup", () => {
	jest.setTimeout(TIMEOUT);
	it("deployment and validate initial public states", async () => {
		const privateKey = GrumpkinScalar.random();
		const publicKey = generatePublicKey(privateKey);

		const batcherContractDeployment = BatcherVaultContract.deployWithPublicKey(
			publicKey,
			admin_relayer, // deployer
			admin_relayer.getAddress(), //admin
			amm.address, // target
			eth.address, // token_in
			dai.address // token_out
			// admin_relayer.getAddress(), // relayer
			// dai.address, // bonding_token
			// BONDING_AMOUNT, // bonding_amount
			// [HE_PUBLIC_KEY.point.x, HE_PUBLIC_KEY.point.y], // he_pub_key
			// SK_HASH, // sk_hash
			// INTERVAL, // interval
			// HE_PRIVATE_KEY, // he_secret_key
			// RAND_INIT
		);

		const batcherInstance = batcherContractDeployment.getInstance();
		await pxe.registerAccount(
			privateKey,
			computePartialAddress(batcherInstance)
		);

		batcher = await batcherContractDeployment.send().deployed();
		console.log("batcher.address: ", batcher.address);

		await batcher.methods
			.init_relayer(
				admin_relayer.getAddress(), // relayer
				dai.address, // bonding_token
				BONDING_AMOUNT, // bonding_amount
				[HE_PUBLIC_KEY.point.x, HE_PUBLIC_KEY.point.y], // he_pub_key
				SK_HASH, // sk_hash
				INTERVAL, // interval
				HE_PRIVATE_KEY, // he_secret_key
				RAND_INIT
			)
			.send()
			.wait();

		const admin = await batcher.methods.get_admin().simulate();
		expect(admin).toBe(admin_relayer.getAddress().toBigInt());
		// console.log("admin: ", admin);

		const round = await batcher.methods.get_round().simulate();
		expect(round).toBe(1n);
		// console.log("round: ", round);

		const target = await batcher.methods.get_target_address().simulate();
		expect(target).toBe(amm.address.toBigInt());
		// console.log("target: ", target);

		const token_in = await batcher.methods.get_token_in().simulate();
		expect(token_in).toBe(eth.address.toBigInt());
		// console.log("token_in: ", token_in);

		const token_out = await batcher.methods.get_token_out().simulate();
		expect(token_out).toBe(dai.address.toBigInt());
		// console.log("token_out: ", token_out);

		const batch_relayer = await batcher.methods.get_batch_relayer().simulate();
		// console.log("batch_relayer_obj: ", batch_relayer);
		expect(batch_relayer.relayer.toBigInt()).toBe(
			admin_relayer.getAddress().toBigInt()
		);
		expect(batch_relayer.bonding_token.toBigInt()).toBe(dai.address.toBigInt());
		expect(batch_relayer.bonding_amount).toBe(BONDING_AMOUNT);
		// expect(batch_relayer.he_pub_key).toBe(HE_PUBLIC_KEY);
		console.log("batch_relayer.he_pub_key: ", batch_relayer.he_pub_key);
		expect(batch_relayer.sk_hash).toBe(SK_HASH);
		expect(batch_relayer.last_timestamp).toBe(0n);
		expect(batch_relayer.interval).toBe(INTERVAL);

		const encrypted_sum = await batcher.methods.get_encrypted_sum(1).simulate();

		console.log("encrypted_sum: ", encrypted_sum);
	});

	it.skip("relayer successfully deposit bonding", async () => {
		const nonce = Fr.random(); // nonce for stake (transfer_public)
		await admin_relayer
			.setPublicAuthWit(
				{
					caller: batcher.address,
					action: dai.methods.transfer_public(
						admin_relayer.getAddress(),
						batcher.address,
						BONDING_AMOUNT,
						nonce
					),
				},
				true
			)
			.send()
			.wait();

		await batcher.methods
			.stake(admin_relayer.getAddress(), dai.address, BONDING_AMOUNT, nonce)
			.send()
			.wait();

		const balance = await dai.methods
			.balance_of_public(batcher.address)
			.simulate();
		expect(balance).toBe(BONDING_AMOUNT);
		console.log("balance: ", balance);
	});

	it("userA should successfully make deposit to batcher contract", async () => {
		const rand = 1878145627n;
		const nonce = Fr.random();
		const currennt_round = await batcher.methods.get_round().simulate();
		const deposit_amount = 100_000n;

		const action = dai
			.withWallet(userA)
			.methods.transfer(
				userA.getAddress(),
				batcher.address,
				deposit_amount,
				nonce
			);

		const witness = await userA.createAuthWit({
			caller: batcher.address,
			action,
		});
		await userA.addAuthWitness(witness);

		await batcher
			.withWallet(userA)
			.methods.deposit_to_batch(
				currennt_round,
				deposit_amount,
				HE_PUBLIC_KEY,
				rand,
				nonce
			)
			.send()
			.wait();

		console.log("deposit_to_batch?");

		const encrypted_sum = await batcher.methods
			.get_encrypted_sum(currennt_round)
			.simulate();

		console.log("encrypted_sum: ", encrypted_sum);
	});

	it("userB should successfully make deposit to batcher contract", async () => {
		const rand = 37814214n;
		const nonce = Fr.random();
		const currennt_round = await batcher.methods.get_round().simulate();
		const deposit_amount = 400_000n;

		const action = dai
			.withWallet(userB)
			.methods.transfer(
				userB.getAddress(),
				batcher.address,
				deposit_amount,
				nonce
			);

		const witness = await userB.createAuthWit({
			caller: batcher.address,
			action,
		});
		await userB.addAuthWitness(witness);

		await batcher
			.withWallet(userB)
			.methods.deposit_to_batch(
				currennt_round,
				deposit_amount,
				HE_PUBLIC_KEY,
				rand,
				nonce
			)
			.send()
			.wait();

		console.log("deposit_to_batch?");

		const encrypted_sum = await batcher.methods
			.get_encrypted_sum(currennt_round)
			.simulate();

		console.log("encrypted_sum: ", encrypted_sum);
		encrypted_amount = [encrypted_sum[0], encrypted_sum[1]];
	});

	it.skip("relayer successfully decrypt and swap the value", async () => {
		const nonce = Fr.random();
		const output = await batcher.methods
			.execute_batch(
				encrypted_amount,
				HE_PRIVATE_KEY,
				0,
				eth.address,
				dai.address,
				nonce,
				nonce
			)
			.simulate();

		console.log("output: ", output);
		// TODO: both/either addition and decryption goes wrong here.
		// expected: 500000
		// output: 40000000000 ( userA input * userB input )
		// possibly need BigInt lib
	});

	// 1: decrypt & swap
	// 2: dispute relayer
});
