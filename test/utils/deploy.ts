import {
	Fr,
	PXE,
	AztecAddress,
	AccountWalletWithPrivateKey,
	Wallet,
	BatchCall,
	computeMessageSecretHash,
} from "@aztec/aztec.js";
import {
	deployInstance,
	registerContractClass,
} from "@aztec/aztec.js/deployment";
import { SchnorrAccountContractArtifact } from "@aztec/accounts/schnorr";
import { TokenContract } from "@aztec/noir-contracts.js";
// import { BatcherVaultContract } from "../artifacts/BatcherVault.js";
import { AMMMockContract } from "../artifacts/AMMMock.js";
import { addPendingShieldNoteToPXE } from "./addNote.js";

export const deployTokensAndMint = async (
	wallet: Wallet,
	admin_relayer: AztecAddress,
	userA: AccountWalletWithPrivateKey,
	userB: AccountWalletWithPrivateKey
): Promise<TokenContract[]> => {
	const ethContract = await TokenContract.deploy(
		wallet,
		admin_relayer,
		"Ethereum",
		"ETH",
		18n
	)
		.send()
		.deployed();

	const daiContract = await TokenContract.deploy(
		wallet,
		admin_relayer,
		"Dai Stablecoin",
		"DAI",
		18n
	)
		.send()
		.deployed();

	// mint eth to admin
	await ethContract.methods
		.mint_public(admin_relayer, 10_000_000)
		.send()
		.wait();

	// mint dai to relayer for bonding
	await daiContract.methods
		.mint_public(admin_relayer, 100_000_000)
		.send()
		.wait();

	// mint dai to userA for deposit
	// await daiContract.methods.mint_public(userA, 100_000_000).send().wait();
	const mint_amount = 100_000_000n;

	const secretA = Fr.random();
	const secretHashA = computeMessageSecretHash(secretA);
	const txA = await daiContract.methods
		.mint_private(mint_amount, secretHashA)
		.send()
		.wait();

	await addPendingShieldNoteToPXE(
		userA.getAddress(),
		daiContract.address,
		mint_amount,
		secretHashA,
		txA.txHash
	);

	await daiContract
		.withWallet(userA)
		.methods.redeem_shield(userA.getAddress(), mint_amount, secretA)
		.send()
		.wait();

	// mint dai to userB for deposit
	// await daiContract.methods.mint_public(userB, 100_000_000).send().wait();
	const secretB = Fr.random();
	const secretHashB = computeMessageSecretHash(secretB);
	const txB = await daiContract.methods
		.mint_private(mint_amount, secretHashB)
		.send()
		.wait();

	await addPendingShieldNoteToPXE(
		userB.getAddress(),
		daiContract.address,
		mint_amount,
		secretHashB,
		txB.txHash
	);

	await daiContract
		.withWallet(userB)
		.methods.redeem_shield(userB.getAddress(), mint_amount, secretB)
		.send()
		.wait();

	return [ethContract, daiContract];
};

export const deployAMMMock = async (
	wallet: AccountWalletWithPrivateKey,
	admin_relayer: AztecAddress,
	token_in: TokenContract,
	token_out: AztecAddress
) => {
	const ammMockContract = await AMMMockContract.deploy(
		wallet,
		admin_relayer,
		token_in.address,
		token_out
	)
		.send()
		.deployed();

	console.log("ammMockContract: ", ammMockContract.address);

	// approve ammMockContract for performing transfer_public
	const nonce = Fr.random();
	await wallet
		.setPublicAuthWit(
			{
				caller: ammMockContract.address,
				action: token_in.methods.transfer_public(
					admin_relayer,
					ammMockContract.address,
					100_000,
					nonce
				),
			},
			true
		)
		.send()
		.wait();

	// deployer add liquidity
	await ammMockContract.methods
		.add_liquidity(token_in.address, 100_000, nonce)
		.send()
		.wait();

	return ammMockContract;
};

export async function publicDeployAccounts(
	sender: Wallet,
	accountsToDeploy: Wallet[]
) {
	const accountAddressesToDeploy = accountsToDeploy.map((a) => a.getAddress());
	const instances = await Promise.all(
		accountAddressesToDeploy.map((account) =>
			sender.getContractInstance(account)
		)
	);
	const batch = new BatchCall(sender, [
		(
			await registerContractClass(sender, SchnorrAccountContractArtifact)
		).request(),
		...instances.map((instance) => deployInstance(sender, instance!).request()),
	]);
	await batch.send().wait();
}
