use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};
use crate::types::elgamal_affine_points::ElgamalAffinePoints;
use crate::types::encrypted_sum::EncryptedSum;

global ROUND_SERIALIZED_LEN: Field = 12;
// global ROUND_SERIALIZED_LEN: Field = 4;

struct Round {
    token_in_amount: Field,
    token_out_amount_cancelled: Field,
    token_out_amount: Field,
    // encrypted_token_out_amount: [Field; 2], // [c1, c2]
    encrypted_token_out_amount: EncryptedSum,
    executed: bool,
    // minimum batch count
}

impl Round {
    fn get_encrypted_amount(self) -> [Field;8] {
        let enc_sum = self.encrypted_token_out_amount.serialize();
        [
            enc_sum[0],
            enc_sum[1],
            enc_sum[2],
            enc_sum[3],
            enc_sum[4],
            enc_sum[5],
            enc_sum[6],
            enc_sum[7],
        ]
    }
}


impl Deserialize<ROUND_SERIALIZED_LEN> for Round {
    fn deserialize(fields: [Field; ROUND_SERIALIZED_LEN]) -> Self {
       let mut enc_sum: [Field;8] = [0;8];

        for i in 0..8 {
            enc_sum[i] = fields[i + 3];
        }

        Round { 
            token_in_amount: fields[0],
            token_out_amount_cancelled: fields[1],
            token_out_amount: fields[2],
            encrypted_token_out_amount: EncryptedSum::deserialize(enc_sum),
            executed: fields[11] as bool
            // executed: fields[3] as bool
         }
    }
}

impl Serialize<ROUND_SERIALIZED_LEN> for Round {
    fn serialize(self) -> [Field; ROUND_SERIALIZED_LEN] {
       let enc_sum = self.encrypted_token_out_amount.serialize();

        [
            self.token_in_amount,
            self.token_out_amount_cancelled,
            self.token_out_amount,
            enc_sum[0],
            enc_sum[1],
            enc_sum[2],
            enc_sum[3],
            enc_sum[4],
            enc_sum[5],
            enc_sum[6],
            enc_sum[7],
            self.executed as Field,
        ]
    }
}

