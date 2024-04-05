use dep::aztec::prelude::{AztecAddress, NoteInterface, NoteHeader, PrivateContext, emit_encrypted_log};
use dep::aztec::{
    note::{utils::compute_note_hash_for_consumption},
    oracle::{nullifier_key::get_nullifier_secret_key, get_public_key::get_public_key},
    hash::pedersen_hash, protocol_types::traits::Empty
};

global DCA_NOTE_LEN: Field = 5;
global MAX_EPOCH: Field = 12;

#[aztec(note)]
struct DCANote {
    sell_amount: U128,
    total_deoposit_amount: U128,
    start_epoch: U128,
    end_epoch: U128,
    owner: AztecAddress,
}

impl DCANote {
    pub fn new(
        sell_amount: U128,
        total_deoposit_amount: U128,
        start_epoch: U128,
        end_epoch: U128,
        owner: AztecAddress
    ) -> Self {
        DCANote { 
            sell_amount, 
            total_deoposit_amount, 
            start_epoch, 
            end_epoch, 
            owner,
            header: NoteHeader::empty()
        }
    }
}

impl NoteInterface<DCA_NOTE_LEN> for DCANote {
    fn compute_nullifier(self, context: &mut PrivateContext) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_consumption(self);
        let secret = context.request_nullifier_secret_key(self.owner);
        pedersen_hash([
            note_hash_for_nullify,
            secret.high,
            secret.low,
        ],0)
    }

    fn compute_nullifier_without_context(self) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_consumption(self);
        let secret = get_nullifier_secret_key(self.owner);
        pedersen_hash([
            note_hash_for_nullify,
            secret.high,
            secret.low,
        ],0)
    }

    // Broadcasts the note as an encrypted log on L1.
    fn broadcast(self, context: &mut PrivateContext, slot: Field) {
        let encryption_pub_key = get_public_key(self.owner);
        emit_encrypted_log(
            context,
            (*context).this_address(),
            slot,
            Self::get_note_type_id(),
            encryption_pub_key,
            self.serialize_content(),
        );
    }
}
