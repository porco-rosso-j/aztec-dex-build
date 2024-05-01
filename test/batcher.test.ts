import {
	Fr,
	PXE,
	createPXEClient,
	AztecAddress,
	AccountWalletWithPrivateKey,
	initAztecJs,
	GrumpkinScalar,
	generatePublicKey,
	computeMessageSecretHash,
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
import * as bjj from "babyjubjub-utils";
import { addPendingShieldNoteToPXE } from "./utils/addNote.js";

let pxe: PXE;
let batcher: BatcherVaultContract;

let admin_relayer: AccountWalletWithPrivateKey;
let userA: AccountWalletWithPrivateKey;
let userB: AccountWalletWithPrivateKey;

let eth: TokenContract;
let dai: TokenContract;
let amm: AMMMockContract;

let encrypted_amount: Fr[];

const TIMEOUT = 300_000;

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
}, TIMEOUT);

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
				HE_PRIVATE_KEY, // he_secret_key
				INTERVAL // interval
			)
			.send()
			.wait();
		console.log("relayer initialized");

		await batcher.methods.init_encrypted_note(RAND_INIT).send().wait();
		console.log("encrypted_note initialized");

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
		const rands = [Fr.random(), Fr.random()];
		const nonce = Fr.random();
		const currennt_round = await batcher.methods.get_round().simulate();
		// const deposit_amount = BigInt(4e18);
		const deposit_amount = BigInt(4e15);

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
				rands,
				nonce
			)
			.send()
			.wait();

		const encrypted_sum = await batcher.methods
			.get_encrypted_sum(currennt_round)
			.simulate();

		console.log("encrypted_sum: ", encrypted_sum);
	});

	it("userB should successfully make deposit to batcher contract", async () => {
		const rands = [Fr.random(), Fr.random()];
		const nonce = Fr.random();
		const currennt_round = await batcher.methods.get_round().simulate();
		// const deposit_amount = BigInt(1e18);
		const deposit_amount = BigInt(1e15);

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
				rands,
				nonce
			)
			.send()
			.wait();

		const encrypted_sum = await batcher.methods
			.get_encrypted_sum(currennt_round)
			.simulate();

		console.log("encrypted_sum: ", encrypted_sum);
		encrypted_amount = [encrypted_sum[0], encrypted_sum[1]];
	});

	it("relayer successfully decrypt and execute swap", async () => {
		const currennt_round = await batcher.methods.get_round().simulate();
		const encrypted_sum = await batcher.methods
			.get_encrypted_sum(currennt_round)
			.simulate();

		// ---  decryption  --- //

		const encryptedValueSumC1_0 = {
			x: encrypted_sum[0],
			y: encrypted_sum[1],
		};

		const encryptedValueSumC2_0 = {
			x: encrypted_sum[2],
			y: encrypted_sum[3],
		};

		const decryptedSum1 = await bjj.elgamalDecrypt(
			HE_PRIVATE_KEY,
			encryptedValueSumC1_0,
			encryptedValueSumC2_0,
			8
		);

		console.log("decryptedSum1: ", decryptedSum1);

		const encryptedValueSumC1_1 = {
			x: encrypted_sum[4],
			y: encrypted_sum[5],
		};

		const encryptedValueSumC2_1 = {
			x: encrypted_sum[6],
			y: encrypted_sum[7],
		};

		const decryptedSum2 = await bjj.elgamalDecrypt(
			HE_PRIVATE_KEY,
			encryptedValueSumC1_1,
			encryptedValueSumC2_1,
			8
		);

		console.log("decryptedSum2: ", decryptedSum2);

		// convert points to affine points
		const ciphertext_lower_1 = {
			point: encryptedValueSumC1_0,
		};

		const ciphertext_lower_2 = {
			point: encryptedValueSumC2_0,
		};

		const ciphertext_upper_1 = {
			point: encryptedValueSumC1_1,
		};

		const ciphertext_upper_2 = {
			point: encryptedValueSumC2_1,
		};

		const secret = Fr.random();
		const secretHash = computeMessageSecretHash(secret);

		const batcher_token_out_before = await dai.methods
			.balance_of_private(batcher.address)
			.simulate();

		console.log("batcher_token_out_before: ", batcher_token_out_before);

		const amm_token_in_before = await eth.methods
			.balance_of_public(amm.address)
			.simulate();

		console.log("amm_token_in_before: ", amm_token_in_before);

		const nonceForDAIApproval = new Fr(1n);
		await admin_relayer.createAuthWit({
			caller: amm.address,
			action: dai.methods.unshield(
				batcher.address,
				amm.address,
				5e16,
				nonceForDAIApproval
			),
		});

		const tx = await batcher.methods
			.execute_batch(
				decryptedSum1,
				decryptedSum2,
				ciphertext_lower_1,
				ciphertext_lower_2,
				ciphertext_upper_1,
				ciphertext_upper_2,
				HE_PRIVATE_KEY,
				0, // token_out_amount_cancelled
				0, // nonce0
				0, // nonce1
				secretHash
			)
			.send()
			.wait();

		// batcher_token_out_after
		const batcher_token_out_after = await dai.methods
			.balance_of_private(batcher.address)
			.simulate();

		console.log("batcher_token_out_after: ", batcher_token_out_after);
		expect(batcher_token_out_after).toBe(0n);

		// amm_token_out_after
		const amm_token_out_after = await dai.methods
			.balance_of_public(amm.address)
			.simulate();

		console.log("amm_token_out_after: ", amm_token_out_after);
		expect(amm_token_out_after).toBe(batcher_token_out_before);

		const expected_token_in = BigInt(5e16);

		// redeem eth shielded from amm
		await addPendingShieldNoteToPXE(
			batcher.address,
			eth.address,
			expected_token_in,
			secretHash,
			tx.txHash
		);

		await eth
			.withWallet(admin_relayer)
			.methods.redeem_shield(batcher.address, expected_token_in, secret)
			.send()
			.wait();

		// batcher_token_in_after
		const batcher_token_in_after = await eth.methods
			.balance_of_private(batcher.address)
			.simulate();

		console.log("batcher_token_in_after: ", batcher_token_in_after);
		expect(batcher_token_in_after).toBe(expected_token_in);

		// amm_token_in_after
		const amm_token_in_after = await eth.methods
			.balance_of_public(amm.address)
			.simulate();

		console.log("amm_token_in_after: ", amm_token_in_after);
		expect(amm_token_in_after).toBe(amm_token_in_before - expected_token_in);
	});

	// 1: decrypt & swap
	// 2: dispute relayer
});
