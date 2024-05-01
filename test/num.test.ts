import { Fr } from "@aztec/aztec.js";
import { it } from "@jest/globals";

it.skip("test", async () => {
	// const num = new Fr(
	// 	21888242871839275222246405745257275088548364400416034343698204186575808495616n
	// );
	const num = new Fr(10);
	// const num2 = new Fr(5000000000000001);
	const num2 = new Fr(3);

	const div = num.div(num2);
	console.log("div: ", div);
	console.log("div: ", div.toBigInt());
});

it.skip("test", async () => {
	const num = new Fr(2958935137635786380114613843419925192240n);
	// const num = new Fr(73973378440894659502865346085498129804n);
	const num2 = new Fr(73973378440894659502865346085498129804n);

	const mul = num.mul(num2);
	console.log("mul: ", mul);
	console.log("mul: ", mul.toBigInt());
});

it.skip("test", async () => {
	const num = new Fr(
		21888242871839275222246405745257275088548364400416034343698204186575808495616n
	);
	const num2 = new Fr(3189391831712126n);

	const add = num.add(num2);
	console.log("add: ", add);
	console.log("add: ", add.toBigInt());
});

it.skip("test", async () => {
	const num = new Fr(
		21888242871839275222246405745257275088548364400416034343698204186575808495616n
	);
	const num2 = new Fr(3189391831712126n);

	const sub = num.sub(num2);
	console.log("sub: ", sub);
	console.log("sub: ", sub.toBigInt());
});

/**
 * Find the modular inverse of a given element, for BN254 Fr.
 */
function modInverse(b: bigint) {
	const [gcd, x, _] = extendedEuclidean(b, Fr.MODULUS);
	if (gcd != 1n) {
		throw Error("Inverse does not exist");
	}
	// Add modulus if -ve to ensure positive
	return new Fr(x > 0 ? x : x + Fr.MODULUS);
}

/**
 * The extended Euclidean algorithm can be used to find the multiplicative inverse of a field element
 * This is used to perform field division.
 */
function extendedEuclidean(
	a: bigint,
	modulus: bigint
): [bigint, bigint, bigint] {
	if (a == 0n) {
		return [modulus, 0n, 1n];
	} else {
		const [gcd, x, y] = extendedEuclidean(modulus % a, a);
		return [gcd, y - (modulus / a) * x, x];
	}
}
