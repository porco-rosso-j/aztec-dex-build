import { Fr } from "@aztec/aztec.js";
import { it } from "@jest/globals";
import * as bjj from "babyjubjub-utils";
import { HE_PRIVATE_KEY, NEW_HE_PRIVATE_KEY } from "./utils/constants.js";

it.skip("test", async () => {
	const generatedKeys = await bjj.generatePrivateAndPublicKey();
	console.log("generatedKeys: ", generatedKeys);
	const privateKey = generatedKeys.privateKey;
	console.log("privateKey: ", privateKey);
	const publicKey = await bjj.packPoint(generatedKeys.publicKey);
	console.log("publicKey: ", publicKey);
	const original_plaint_text1 = 1000;
	const original_plaint_text2 = 42;
	const { C1: encryptedValue1C1, C2: encryptedValue1C2 } =
		await bjj.elgamalEncryptPacked(publicKey, original_plaint_text1);

	console.log("encryptedValue1C1: ", encryptedValue1C1);
	console.log("encryptedValue1C2: ", encryptedValue1C2);

	const { C1: encryptedValue2C1, C2: encryptedValue2C2 } =
		await bjj.elgamalEncryptPacked(publicKey, original_plaint_text2);

	console.log("encryptedValue2C1: ", encryptedValue2C1);
	console.log("encryptedValue2C2: ", encryptedValue2C2);

	const encryptedValueSumC1 = await bjj.addPoints(
		encryptedValue1C1,
		encryptedValue2C1
	); // we sum the ciphertexts
	console.log("encryptedValueSumC1: ", encryptedValueSumC1);

	const encryptedValueSumC2 = await bjj.addPoints(
		encryptedValue1C2,
		encryptedValue2C2
	); // we sum the ciphertexts

	console.log("encryptedValueSumC2: ", encryptedValueSumC2);

	const decryptedSum = await bjj.elgamalDecrypt(
		privateKey,
		encryptedValueSumC1,
		encryptedValueSumC2,
		8
	);

	console.log("decryptedSum: ", decryptedSum);
	// assert.equal(decryptedSum, original_plaint_text1 + original_plaint_text2); // we recover the sum of orginal plaintexts
}, 360000);

it.skip("test 2", async () => {
	const privateKey = BigInt(
		"2360067582289791756090345803415031600606727745697750731963540090262281758098"
	);

	// const encrypted_sum = [
	// 	12545004557005016049698532947601840318278527242697445274565814580946444342144n,
	// 	8520592548842938419371968419511920710277428913949953188529118072663285342448n,
	// 	14604867579825346845334235231255415290705125469553663824435106869473578543791n,
	// 	3903879204896560080825150557219882409936290276230848056615688353809138436898n,
	// 	18436497353218453881787079406501856362210550929692453231992530150198272153801n,
	// 	5226692059557117023923858651266542839209135757736008491749003805125234124646n,
	// 	5018180979981680084824738331943122842532059574193791451409770255913095964377n,
	// 	2519015932811723705164980251254700299513948377033145824235764673892173550364n,
	// ];
	const encrypted_sum = [
		21472650984436762244031229619925647112984218173381824458470819684039379547949n,
		1837783691375768657483026041108174498631463823080692472709918501662216277768n,
		11690546517140707588397632225831069958620412414394622994423967885413670819429n,
		21302984366707003236483210776302960827497755078834244388811810345577369656375n,
		13058325584767053170800789778067689450276426775479771755984487613995695696571n,
		4975052509571564062789505510404194221861562293797938993591427913567106498933n,
		2873706985540263354861265913926170740549681333793565646869733174154165291296n,
		9501958688898625059030708999438742894669694486443633382776986148168316164379n,
	];

	const encryptedValueSumC1_0 = {
		x: encrypted_sum[0],
		y: encrypted_sum[1],
	};

	const encryptedValueSumC2_0 = {
		x: encrypted_sum[2],
		y: encrypted_sum[3],
	};

	const decryptedSum1 = await bjj.elgamalDecrypt(
		privateKey,
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
		privateKey,
		encryptedValueSumC1_1,
		encryptedValueSumC2_1,
		8
	);

	console.log("decryptedSum2: ", decryptedSum2);
}, 360000);

it("get pubkey from sk", async () => {
	const NEW_HE_PUBKEY = await bjj.privateToPublicKey(NEW_HE_PRIVATE_KEY);
	console.log("NEW_HE_PUBKEY: ", NEW_HE_PUBKEY);
});
