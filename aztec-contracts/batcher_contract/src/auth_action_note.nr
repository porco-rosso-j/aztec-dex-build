use dep::aztec::prelude::{AztecAddress, NoteInterface, NoteHeader, PrivateContext, emit_encrypted_log};
use dep::aztec::{
    note::{utils::compute_note_hash_for_consumption},
    oracle::{unsafe_rand::unsafe_rand, nullifier_key::get_nullifier_secret_key, get_public_key::get_public_key},
    hash::pedersen_hash, protocol_types::traits::Empty
};
 use dep::authwit::auth::{IS_VALID_SELECTOR, compute_outer_authwit_hash};

global AUTH_ACTION_NOTE_LEN: Field = 3;
global MAX_ARG_LEN: Field = 10;

#[aztec(note)]
struct AuthActionNote {
    approved: bool,
    owner: AztecAddress,
    randomness: Field
}

impl AuthActionNote {
    pub fn new(
        approved: bool,
        owner: AztecAddress
    ) -> Self {
        AuthActionNote { 
            approved,
            owner,
            randomness: unsafe_rand(),
            header: NoteHeader::empty()
        }
    }

    pub fn empty() -> Self {
        AuthActionNote::new(false, AztecAddress::from_field(0))
    }

    pub fn validate_action(
        self: Self,
        context: &mut PrivateContext,
        message_hash: Field,
    ) -> Field {
        if (self.approved) {
            context.push_new_nullifier(message_hash, 0);
            IS_VALID_SELECTOR
        } else {
            0
        }
    }
}

impl NoteInterface<AUTH_ACTION_NOTE_LEN> for AuthActionNote {
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
        // only broadcast if approved == true
        if !(self.approved) {
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
}
