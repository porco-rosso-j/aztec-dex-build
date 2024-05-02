use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};
use crate::types::elgamal_affine_points::ElgamalAffinePoints;
use crate::types::encrypted_sum::EncryptedSum;

global ROUND_SERIALIZED_LEN: Field = 14;

struct Round {
    token_in_amount: Field,
    expected_min_token_in: Field,
    token_out_amount_cancelled: Field,
    token_out_amount: Field,
    encrypted_token_out_amount: EncryptedSum,
    executed: bool,
    claimed: bool,
    // min_batch_count or min_batch_amount
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
            enc_sum[i] = fields[i + 4];
        }

        Round { 
            token_in_amount: fields[0],
            expected_min_token_in: fields[1],
            token_out_amount_cancelled: fields[2],
            token_out_amount: fields[3],
            encrypted_token_out_amount: EncryptedSum::deserialize(enc_sum),
            executed: fields[12] as bool,
            claimed: fields[13] as bool
         }
    }
}

impl Serialize<ROUND_SERIALIZED_LEN> for Round {
    fn serialize(self) -> [Field; ROUND_SERIALIZED_LEN] {
       let enc_sum = self.encrypted_token_out_amount.serialize();

        [
            self.token_in_amount,
            self.expected_min_token_in,
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
            self.claimed as Field,
        ]
    }
}

