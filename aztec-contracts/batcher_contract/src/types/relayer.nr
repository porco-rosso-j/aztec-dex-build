use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};
use crate::types::affine_point::AffinePoint;

global RELAYER_SERIALIZED_LEN: Field = 8; // 7

struct BatchRelayer {
    relayer: AztecAddress, 
    bonding_token: AztecAddress, 
    bonding_amount: Field, // say 50-100k dai
    he_pub_key: AffinePoint,
    sk_hash: Field,
    last_timestamp: Field,
    interval: Field,
}

impl BatchRelayer {
    fn new(
        relayer: AztecAddress, 
        bonding_token: AztecAddress,
        bonding_amount: Field,
        he_pub_key: AffinePoint,
        sk_hash: Field, 
        last_timestamp: Field,
        interval: Field,
    ) -> Self {
        BatchRelayer {
            relayer,
            bonding_token,
            bonding_amount,
            he_pub_key,
            sk_hash,
            last_timestamp,
            interval
        }
    }
}

impl Deserialize<RELAYER_SERIALIZED_LEN> for BatchRelayer {
    fn deserialize(fields: [Field; RELAYER_SERIALIZED_LEN]) -> Self {
        let mut affine_points: [Field; 2] = [0;2];
        affine_points[0] = fields[3];
        affine_points[1] = fields[4];

        BatchRelayer { 
            relayer: AztecAddress::from_field(fields[0]),
            bonding_token: AztecAddress::from_field(fields[1]),
            bonding_amount: fields[2],
            he_pub_key:  AffinePoint::deserialize(affine_points),
            sk_hash: fields[5],
            last_timestamp: fields[6],
            interval: fields[7],
         }
    }
}

impl Serialize<RELAYER_SERIALIZED_LEN> for BatchRelayer {
    fn serialize(self) -> [Field; RELAYER_SERIALIZED_LEN] {
        let pubkey_affine_points = self.he_pub_key.serialize();

        [
            self.relayer.to_field(), 
            self.bonding_token.to_field(),
            self.bonding_amount,
            pubkey_affine_points[0],
            pubkey_affine_points[1],
            self.sk_hash,
            self.last_timestamp,
            self.interval,
        ]
    }
}
