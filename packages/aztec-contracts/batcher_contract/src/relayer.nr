use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};

global RELAYER_SERIALIZED_LEN: Field = 7;

struct BatchRelayer {
    relayer: AztecAddress, 
    bonding_token: AztecAddress, 
    bonding_amount: Field, // say 50-100k dai
    he_pub_key: Field,
    sk_hash: Field,
    last_timestamp: Field,
    interval: Field,
}

impl BatchRelayer {
    fn new(
        relayer: AztecAddress, 
        bonding_token: AztecAddress,
        bonding_amount: Field,
        he_pub_key: Field,
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
        BatchRelayer { 
            relayer: AztecAddress::from_field(fields[0]),
            bonding_token: AztecAddress::from_field(fields[1]),
            bonding_amount: fields[2],
            he_pub_key: fields[3],
            sk_hash: fields[4],
            last_timestamp: fields[5],
            interval: fields[6],
         }
    }
}

impl Serialize<RELAYER_SERIALIZED_LEN> for BatchRelayer {
    fn serialize(self) -> [Field; RELAYER_SERIALIZED_LEN] {
        [
            self.relayer.to_field(), 
            self.bonding_token.to_field(),
            self.bonding_amount,
            self.he_pub_key,
            self.sk_hash,
            self.last_timestamp,
            self.interval,
        ]
    }
}
