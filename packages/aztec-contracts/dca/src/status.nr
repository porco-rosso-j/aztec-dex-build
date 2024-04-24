use dep::aztec::protocol_types::{address::AztecAddress, traits::{Serialize, Deserialize}};

struct Status {
    current_epoch: Field, // 1 <= x >= MAX_STATUS
    last_timestamp: Field, 
    dca_interval: Field, // e.g. 2592000 for a month
    claimable: bool // disallows claim until epoch_to_token_in updated after DCA execution
}

global STATUS_SERIALIZED_LEN: Field = 4;

impl Deserialize<STATUS_SERIALIZED_LEN> for Status {
    fn deserialize(fields: [Field; STATUS_SERIALIZED_LEN]) -> Self {
        Leader { 
            current_epoch,
            last_timestamp,
            dca_interval,
            claimable: claimable as bool
         }
    }
}

impl Serialize<STATUS_SERIALIZED_LEN> for Status {
    fn serialize(self) -> [Field; STATUS_SERIALIZED_LEN] {
        [
            self.current_epoch, 
            self.last_timestamp,
            self.dca_interval,
            self.claimable as Field,
        ]
    }
}

/*

i think there should be time to disallow new deposits in the period of time between
execute batch and update token_in amounts...

assume epoch update occurs in execBatchSwap()

new deposits are put into the next(current) epoch, so its ok

but new claim only should happen after epoch_to_token_out and epoch_to_token_in are both synched
=> if no epoch_to_token_out, 

how about turning "claimbale" false in execute batch and turnin it true back in "update"
that sounds like simplest way


HE Addition:
who: ○
when: ×
input amount: × ( exposed to relayer )
output amount: ○

Shared note:
who: ○
when: ○
input amount: × ( exposed to relayer )
output amount: ○

*/