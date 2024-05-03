use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};
use crate::types::affine_point::AffinePoint;

global RELAYER_SERIALIZED_LEN: Field = 9; 

// relayer config struct
struct BatchRelayer {
    relayer: AztecAddress, 
    bonding_token: AztecAddress, 
    bonding_amount: Field, // say 50-100k dai
    slash_amount: Field,
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
        slash_amount: Field,
        he_pub_key: AffinePoint,
        sk_hash: Field, 
        last_timestamp: Field,
        interval: Field,
    ) -> Self {
        BatchRelayer {
            relayer,
            bonding_token,
            bonding_amount,
            slash_amount,
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
        affine_points[0] = fields[4];
        affine_points[1] = fields[5];

        BatchRelayer { 
            relayer: AztecAddress::from_field(fields[0]),
            bonding_token: AztecAddress::from_field(fields[1]),
            bonding_amount: fields[2],
            slash_amount: fields[3],
            he_pub_key:  AffinePoint::deserialize(affine_points),
            sk_hash: fields[6],
            last_timestamp: fields[7],
            interval: fields[8],
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
            self.slash_amount,
            pubkey_affine_points[0],
            pubkey_affine_points[1],
            self.sk_hash,
            self.last_timestamp,
            self.interval,
        ]
    }
}
