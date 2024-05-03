import { jest, beforeAll, it, describe, expect } from "@jest/globals";
import {
	Fr,
	PXE,
	createPXEClient,
	AccountWalletWithPrivateKey,
	initAztecJs,
	GrumpkinScalar,
	generatePublicKey,
	computeMessageSecretHash,
} from "@aztec/aztec.js";
import { computePartialAddress } from "@aztec/circuits.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { TokenContract } from "@aztec/noir-contracts.js";
import { BatcherVaultContract } from "./artifacts/BatcherVault.js";
import { AMMMockContract } from "./artifacts/AMMMock.js";
import {
	deployAMMMock,
	deployTokensAndMint,
	publicDeployAccounts,
} from "./utils/deploy.js";
import {
	BONDING_AMOUNT,
	HE_PRIVATE_KEY,
	HE_PUBLIC_KEY,
	INTERVAL,
	NEW_HE_PRIVATE_KEY,
	RAND_INIT,
	SANDBOX_URL,
	SK_HASH,
	SLASH_AMOUNT,
} from "./utils/constants.js";
import { addPendingShieldNoteToPXE } from "./utils/addNote.js";
import * as bjj from "babyjubjub-utils";

let pxe: PXE;
let batcher: BatcherVaultContract;

let admin_relayer: AccountWalletWithPrivateKey;
let userA: AccountWalletWithPrivateKey;
let userB: AccountWalletWithPrivateKey;

let eth: TokenContract;
let dai: TokenContract;
let amm: AMMMockContract;

const TIMEOUT = 300_000;

// yarn test batcher.test.ts

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
			admin_relayer.getAddress(), // admin
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

		const nonce = Fr.random();
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
			.init_relayer(
				admin_relayer.getAddress(), // relayer
				dai.address, // bonding_token
				BONDING_AMOUNT, // bonding_amount
				SLASH_AMOUNT,
				[HE_PUBLIC_KEY.point.x, HE_PUBLIC_KEY.point.y], // he_pub_key
				SK_HASH, // sk_hash
				HE_PRIVATE_KEY, // he_secret_key
				INTERVAL, // interval
				nonce
			)
			.send()
			.wait();
		console.log("relayer initialized");

		const balance = await dai.methods
			.balance_of_public(batcher.address)
			.simulate();
		expect(balance).toBe(BONDING_AMOUNT);
		console.log("balance: ", balance);

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

	it("userA should successfully make deposit to batcher contract", async () => {
		const rands = [Fr.random(), Fr.random()];
		const nonce = Fr.random();
		const currennt_round = await batcher.methods.get_round().simulate();
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
	});

	it("relayer successfully decrypt and execute swap on behalf of users", async () => {
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

		const expected_token_in = BigInt(5e16);

		// add pending shield to pxe
		await addPendingShieldNoteToPXE(
			batcher.address,
			eth.address,
			expected_token_in,
			secretHash,
			tx.txHash
		);

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

		// redeem eth shielded from amm
		await batcher.methods
			.finalize_execute(expected_token_in, secret)
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

	it("users should successfully claim token_in privately", async () => {
		const round = 1;
		const total_token_out = await batcher.methods
			.get_token_out_total_amount(round)
			.simulate();
		const total_token_in = await batcher.methods
			.get_token_in_total_amount(round)
			.simulate();
		const token_out_amount_cancelled = await batcher.methods
			.get_token_out_amount_cancelled(round)
			.simulate();

		// ---- User A claim ---- //

		const userA_token_in_amount_before = await eth
			.withWallet(userA)
			.methods.balance_of_private(userA.getAddress())
			.simulate();
		console.log("userA_token_in_amount_before: ", userA_token_in_amount_before);

		await batcher
			.withWallet(userA)
			.methods.claim_token_in(
				round,
				total_token_in,
				total_token_out,
				token_out_amount_cancelled
			)
			.send()
			.wait();

		const userA_token_in_amount_after = await eth
			.withWallet(userA)
			.methods.balance_of_private(userA.getAddress())
			.simulate();
		console.log("userA_token_in_amount_after: ", userA_token_in_amount_after);

		expect(userA_token_in_amount_after).toBe(
			userA_token_in_amount_before + BigInt(4e16)
		);

		// ---- User B claim ---- //

		const userB_token_in_amount_before = await eth
			.withWallet(userB)
			.methods.balance_of_private(userB.getAddress())
			.simulate();
		console.log("userB_token_in_amount_before: ", userB_token_in_amount_before);

		await batcher
			.withWallet(userB)
			.methods.claim_token_in(
				round,
				total_token_in,
				total_token_out,
				token_out_amount_cancelled
			)
			.send()
			.wait();

		const userB_token_in_amount_after = await eth
			.withWallet(userB)
			.methods.balance_of_private(userB.getAddress())
			.simulate();
		console.log("userB_token_in_amount_after: ", userB_token_in_amount_after);

		expect(userB_token_in_amount_after).toBe(
			userB_token_in_amount_before + BigInt(1e16)
		);
	});

	it("non-relayer acc should successfully dispute the relayer and take over the role", async () => {
		const NEW_SK_HASH = await batcher.methods
			.get_sk_hash(NEW_HE_PRIVATE_KEY)
			.simulate();
		const NEW_HE_PUBKEY = await bjj.privateToPublicKey(NEW_HE_PRIVATE_KEY);
		console.log("NEW_HE_PUBKEY: ", NEW_HE_PUBKEY);

		const batch_relayer_before = await batcher.methods
			.get_batch_relayer()
			.simulate();
		console.log("batch_relayer_before: ", batch_relayer_before);

		await batcher
			.withWallet(userA)
			.methods.dispute_relayer(
				HE_PRIVATE_KEY,
				NEW_SK_HASH,
				NEW_HE_PUBKEY.x,
				NEW_HE_PUBKEY.y,
				NEW_HE_PRIVATE_KEY,
				userA.getAddress(),
				false // only_slash?
			)
			.send()
			.wait();

		const batch_relayer_after = await batcher.methods
			.get_batch_relayer()
			.simulate();
		console.log("batch_relayer_after: ", batch_relayer_after);
		expect(batch_relayer_after.sk_hash).toBe(NEW_SK_HASH);
		expect(batch_relayer_after.he_pub_key.point.x).toBe(NEW_HE_PUBKEY.x);
		expect(batch_relayer_after.he_pub_key.point.y).toBe(NEW_HE_PUBKEY.y);
	});
});
