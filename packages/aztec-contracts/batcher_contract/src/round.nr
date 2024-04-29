use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};


global ROUND_SERIALIZED_LEN: Field = 6;

struct Round {
    token_in_amount: Field,
    token_out_amount_cancelled: Field,
    token_out_amount: Field,
    encrypted_token_out_amount: [Field; 2], // [c1, c2]
    executed: bool,
    // minimum batch count
}

impl Round {
    fn get_encrypted_amount(self) -> (Field, Field) {
        (
            self.encrypted_token_out_amount[0],
            self.encrypted_token_out_amount[1]
        )
    }
}


impl Deserialize<ROUND_SERIALIZED_LEN> for Round {
    fn deserialize(fields: [Field; ROUND_SERIALIZED_LEN]) -> Self {
        let mut encrypted_token_out_amount: [Field;2] = [0;2];
        encrypted_token_out_amount[0] = fields[4];
        encrypted_token_out_amount[1] = fields[5];

        Round { 
            token_in_amount: fields[0],
            token_out_amount_cancelled: fields[1],
            token_out_amount: fields[2],
            encrypted_token_out_amount,
            executed: fields[5] as bool
         }
    }
}

impl Serialize<ROUND_SERIALIZED_LEN> for Round {
    fn serialize(self) -> [Field; ROUND_SERIALIZED_LEN] {
        [
            self.token_in_amount,
            self.token_out_amount_cancelled,
            self.token_out_amount,
            self.encrypted_token_out_amount[0],
            self.encrypted_token_out_amount[1],
            self.executed as Field,
        ]
    }
}

