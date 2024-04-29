import {
	AztecAddress,
	ExtendedNote,
	Fr,
	Note,
	TxHash,
	createPXEClient,
} from "@aztec/aztec.js";
import { TokenContract } from "@aztec/noir-contracts.js";
import { SANDBOX_URL } from "./constants.js";

export async function addPendingShieldNoteToPXE(
	recipient: AztecAddress,
	token: AztecAddress,
	amount: bigint,
	secretHash: Fr,
	txHash: TxHash
) {
	const note = new Note([new Fr(amount), secretHash]);
	const extendedNote = new ExtendedNote(
		note,
		recipient,
		token,
		TokenContract.storage.pending_shields.slot,
		TokenContract.notes.TransparentNote.id,
		txHash
	);

	const pxe = createPXEClient(SANDBOX_URL);
	await pxe.addNote(extendedNote);
}
