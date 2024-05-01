declare module "babyjubjub-utils" {
	const anyExported: any;
	export default anyExported;
	export function generatePrivateAndPublicKey(): Promise<{
		privateKey: any;
		publicKey: any;
	}>;
	export function packPoint(publicKey: any): Promise<any>;
	export function elgamalEncryptPacked(
		publicKey: any,
		plaintext: number
	): Promise<{ C1: any; C2: any }>;
	export function addPoints(point1: any, point2: any): Promise<any>;
	export function elgamalDecrypt(
		privateKey: any,
		C1: any,
		C2: any,
		padding: number
	): Promise<number>;
}
