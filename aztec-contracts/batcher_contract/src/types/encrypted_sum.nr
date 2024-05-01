use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};
use crate::types::elgamal_affine_points::ElgamalAffinePoints;
use dep::std::ec::tecurve::affine::Point;

global ENCRYPTED_SUM_SERIALIZED_LEN = 8;

struct EncryptedSum {
    limb0: ElgamalAffinePoints,
    limb1: ElgamalAffinePoints
}

// impl EncryptedSum {
//     fn get_encrypted_amount(self) -> [Field;8] {
//         let enc_sum = self.serialize();
//         [
//             enc_sum[0],
//             enc_sum[1],
//             enc_sum[2],
//             enc_sum[3],
//             enc_sum[4],
//             enc_sum[5],
//             enc_sum[6],
//             enc_sum[7],
//         ]
//     }
// }

impl Deserialize<ENCRYPTED_SUM_SERIALIZED_LEN> for EncryptedSum {
    fn deserialize(fields: [Field; ENCRYPTED_SUM_SERIALIZED_LEN]) -> Self {
        let mut limb_0: [Field;4] = [0; 4];
        let mut limb_1: [Field;4] = [0; 4];

        for i in 0..4 {
            limb_0[i] = fields[i];
            limb_1[i] = fields[i + 4];
        }

        Self {
            limb0: ElgamalAffinePoints::deserialize(limb_0),
            limb1: ElgamalAffinePoints::deserialize(limb_1)
        }
    }
}

impl Serialize<ENCRYPTED_SUM_SERIALIZED_LEN> for EncryptedSum {
    fn serialize(self) -> [Field; ENCRYPTED_SUM_SERIALIZED_LEN] {
         [
            self.limb0.C1.point.x, 
            self.limb0.C1.point.y, 
            self.limb0.C2.point.x, 
            self.limb0.C2.point.y,
            self.limb1.C1.point.x, 
            self.limb1.C1.point.y, 
            self.limb1.C2.point.x, 
            self.limb1.C2.point.y
        ]
    }
}
