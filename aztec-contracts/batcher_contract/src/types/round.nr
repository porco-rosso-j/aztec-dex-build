use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};
use crate::types::elgamal_affine_points::ElgamalAffinePoints;

global ROUND_SERIALIZED_LEN: Field = 8;

struct Round {
    token_in_amount: Field,
    token_out_amount_cancelled: Field,
    token_out_amount: Field,
    // encrypted_token_out_amount: [Field; 2], // [c1, c2]
    encrypted_token_out_amount: ElgamalAffinePoints,
    executed: bool,
    // minimum batch count
}

impl Round {
    fn get_encrypted_amount(self) -> [Field;4] {
        let elgamal_affine_points = self.encrypted_token_out_amount.serialize();
        [
            elgamal_affine_points[0],
            elgamal_affine_points[1],
            elgamal_affine_points[2],
            elgamal_affine_points[3]
        ]
    }
}


impl Deserialize<ROUND_SERIALIZED_LEN> for Round {
    fn deserialize(fields: [Field; ROUND_SERIALIZED_LEN]) -> Self {
       let mut elgamal_affine_points: [Field;4] = [0;4];
        elgamal_affine_points[0] = fields[3];
        elgamal_affine_points[1] = fields[4];
        elgamal_affine_points[2] = fields[5];
        elgamal_affine_points[3] = fields[6];

        Round { 
            token_in_amount: fields[0],
            token_out_amount_cancelled: fields[1],
            token_out_amount: fields[2],
            encrypted_token_out_amount: ElgamalAffinePoints::deserialize(elgamal_affine_points),
            executed: fields[5] as bool
         }
    }
}

impl Serialize<ROUND_SERIALIZED_LEN> for Round {
    fn serialize(self) -> [Field; ROUND_SERIALIZED_LEN] {
        let elgamal_affine_points = self.encrypted_token_out_amount.serialize();

        [
            self.token_in_amount,
            self.token_out_amount_cancelled,
            self.token_out_amount,
            elgamal_affine_points[0],
            elgamal_affine_points[1],
            elgamal_affine_points[2],
            elgamal_affine_points[3],
            self.executed as Field,
        ]
    }
}

