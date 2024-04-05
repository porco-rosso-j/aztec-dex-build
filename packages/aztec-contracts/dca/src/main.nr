mod dca_note;
mod interfaces;
mod array;

// What this contract does
// - let users register dca storategy
// - let users deposit DAI for a given strategy to dca ETH
// - let users claim dca-ed ETH
// - a dca strategy per address

// global MAX_EPOCH: Field = 12; // indicates this vault only provides DCA for a year at the maximum.

contract DCAVault {
    // use dep::aztec::prelude::{FunctionSelector, AztecAddress, Map, PublicImmutable, PublicMutable, PublicImmutable, PrivateMutable};
    use dep::aztec::prelude::{
        AztecAddress, FunctionSelector, NoteHeader, NoteGetterOptions, NoteViewerOptions,
        PrivateContext, Map, PublicMutable, PublicImmutable, PrivateMutable
    };
    use dep::aztec::{note::note_getter_options::Comparator, context::{PublicContext, Context}};
    use crate::interfaces::{Token};
    use crate::dca_note::{DCANote, DCA_NOTE_LEN, MAX_EPOCH};
    use crate::array;

    struct Storage {
        admin: PublicImmutable<AztecAddress>,
        token_out: PublicImmutable<AztecAddress>,
        token_in: PublicImmutable<AztecAddress>,
        current_epoch: PublicMutable<U128>,
        epoch_to_total_token_out: Map<Field, PublicMutable<U128>>, // epoch -> dai amount sold every epoch 
        epoch_to_total_token_in: Map<Field, PublicMutable<U128>>, // epoch -> eth amount bought by dca each epoch
        dca_notes: Map<AztecAddress, PrivateMutable<DCANote>>,
    }

    impl Storage {
      fn init(context: Context) -> Self {
        Storage {
            admin: PublicImmutable::new(context, 1),
            token_out: PublicImmutable::new(context, 2),
            token_in: PublicImmutable::new(context, 3),
            current_epoch: PublicMutable::new(context, 4),
            epoch_to_total_token_out: Map::new(context, 5, |context, slot| {
                    PublicMutable::new(context, slot)
                },
            ),
            epoch_to_total_token_in: Map::new(context, 6, |context, slot| {
                    PublicMutable::new(context, slot)
                },
            ),
            dca_notes: Map::new(context, 7,|context, slot| {
                    PrivateMutable::new(context, slot)
               },
            ),
        }
      }
    }


    #[aztec(private)]
    fn constructor(admin: AztecAddress) {
        let selector = FunctionSelector::from_signature("_initialize((Field))");
        context.call_public_function(context.this_address(), selector, [admin.to_field()]);
    }

    /// admin should increment epoch at the end of each month
    /// timestamp check should be added by the following two different approaches
    /// 1) call timestamp on Aztec. This is not implemented at protocol level yet.
    /// 2) makes this function only callable by a contract controlled by an L1 contract with timestamp checker.
    #[aztec(public)]
    fn increment_epoch() {
        // _is_admin();
        assert(context.msg_sender().to_field() == storage.admin.read().to_field(), "invalid sender");
        let new_epoch = storage.current_epoch.read() + U128::from_field(1);
        storage.current_epoch.write(new_epoch)
    }

    #[aztec(private)]
    fn register_dca(
        sell_amount: U128, 
        initial_deposit_amount: U128, 
        start_epoch: U128, 
        end_epoch: U128,
        nonce_for_unshield_approval:Field
    ) {

        context.call_public_function(
            context.this_address(),
            // FunctionSelector::from_signature("validate_epoch(U128,U128)"),
            FunctionSelector::from_signature("validate_epoch(Field,Field)"),
            [U128::to_field(start_epoch), U128::to_field(end_epoch)]
        );

        let total_sell_amount = sell_amount * (end_epoch - start_epoch);
        assert(initial_deposit_amount == total_sell_amount, "initial_deposit_amount isn't equal to total_sell_amount");

        // create a new dca note
        // if there is already an active note, it triggers claim and re-set. 
        let mut dca_note = DCANote::new(sell_amount, initial_deposit_amount, start_epoch, end_epoch, context.msg_sender());
        storage.dca_notes.at(context.msg_sender()).initialize(
            &mut dca_note,
            true
        );

        // send deposit_amount from account to this contract by validating authwitness
        // let selector = FunctionSelector::from_signature("transfer((Field),(Field),Field,Field)");
        // let _callStackItem = context.call_private_function(
        //     token_out,
        //     selector,
        //     [this.to_field(), this.to_field(), initial_deposit_amount, 0]
        // );
        
        let asset = storage.token_out.read();
        Token::at(asset).unshield(
            &mut context,
            context.msg_sender(),
            context.this_address(),
            U128::to_field(initial_deposit_amount),
            nonce_for_unshield_approval
        );

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_add_token_out_amount(Field,Field,Field)"),
             [U128::to_field(sell_amount), U128::to_field(start_epoch), U128::to_field(end_epoch)]
        );
    }

    // add sell-token balance on a specifc dca note
    #[aztec(private)]
    fn add_balance(amount: Field) {

        // get existing note. no note for the user -> revert
        // modify the note, incrementing balance

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("increase_total_liquidity(Field)"),
            [amount]
        );
    }

    #[aztec(private)]
    fn remove_balance(amount:Field) {
        
        // get existing note. no note for the user -> revert
        // revert if new total_deoposited_amount is less than duration * sell_amount
        // modify the note, decrementing balance    

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("decrease_total_liquidity(Field)"),
            [amount]
        );   
    }

    #[aztec(private)]
    fn change_duration(new_duration:Field) {
        // get existing note. no note for the user -> revert
        // 
    }

    // from relayer or amind controlled by L1 contract with timestamp checkers
    // private or public...?
    // if token_out is unshielded -> public
    // if token_out is transferred -> private possible
    #[aztec(public)]
    fn execute_batch_dca() {
        // caller should be an authorized relayer 

        // initiate bridge through unsiwap and token bridge contracts
        // compute the amount to send to uniswap bridge
        // how? -> total bridge amount per epoch...?
        // 
        // unshield needed 

        // epoch_to_total_token_in[this_epoch] += new_token_in_amount;

        // uniswap.swap_private();
    }

    // from relayer
    // if eth is bridged back publicly, 
    // relayer can shield the amount
    #[aztec(private)]
    fn on_dca_executed() {
        // initiate bridge through unsiwap and token bridge contracts
    }

    // from user
    #[aztec(private)]
    fn claim_token(
        current_epoch: U128, 
        epoch_diff: U128,
        epoch_to_total_token_in: [U128;MAX_EPOCH],
        epoch_to_total_token_out: [U128;MAX_EPOCH]
        ) {

        // get msg_sender's note
        let mut dca_note = storage.dca_notes.at(context.msg_sender()).get_note(true);

        // this private function can't access to public states
        // hence, it ensures that it deals with correct public states by passing them as args and verifies it in public func
        // claim_params() is here for the verification via _validate_claim_params()
        let mut claim_params:[Field;27] = [0;27];
        claim_params[0] = current_epoch.to_field();
        claim_params[1] = dca_note.start_epoch.to_field();
        claim_params[2] = dca_note.end_epoch.to_field();

        for i in 0..12 {
            claim_params[i + 3] = epoch_to_total_token_in[i].to_field();
            claim_params[i + 15] = epoch_to_total_token_out[i].to_field();
        }

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_validate_claim_params(Field[])"), // or (Field)[]
            claim_params
        ); 

        // calculate total eth purchased through dollar cost averages within the specified period for a user
        let mut eth_amount: U128 = U128::from_field(0);
        let len = MAX_EPOCH as u64;

        for i in 0..len {
            let index = i as Field + U128::to_field(dca_note.start_epoch);
            if (U128::from_field(index) <= dca_note.end_epoch) {  
               eth_amount = eth_amount + (epoch_to_total_token_in[index] * dca_note.sell_amount / epoch_to_total_token_out[i]);
            }
        }

        // create pending shield instead of transfer...? 
        // individual users can execute private transfer from this address..?
        let _callStackItem = context.call_private_function(
            storage.token_out.read(),
            FunctionSelector::from_signature("transfer((Field),(Field),Field,Field)"),
            [context.this_address().to_field(), context.msg_sender().to_field(), U128::to_field(eth_amount), 0]
        );
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _initialize(admin: AztecAddress) {
        assert(admin.to_field() != 0, "invalid admin address");
        storage.admin.initialize(admin);
    }

    #[aztec(public)] 
    #[aztec(internal)]
    fn _validate_claim_params(
        _current_epoch: U128, // Field?
        _end_epoch: U128,
        _start_epoch: U128,
        // _token_in_a:Field, 
        // _token_in_b:Field, 
        // _token_in_c:Field, 
        // _token_in_d:Field, 
        // _token_in_e:Field, 
        // _token_in_f:Field, 
        // _token_in_g:Field, 
        // _token_in_h:Field, 
        // _token_in_i:Field, 
        // _token_in_j:Field, 
        // _token_in_k:Field,
        // _token_in_l:Field, 
        // _token_out_a:Field, 
        // _token_out_b:Field, 
        // _token_out_c:Field, 
        // _token_out_d:Field, 
        // _token_out_e:Field, 
        // _token_out_f:Field, 
        // _token_out_g:Field, 
        // _token_out_h:Field, 
        // _token_out_i:Field, 
        // _token_out_j:Field, 
        // _token_out_k:Field,
        // _token_out_l:Field, 
        _token_in_a:U128, 
        _token_in_b:U128, 
        _token_in_c:U128, 
        _token_in_d:U128, 
        _token_in_e:U128, 
        _token_in_f:U128, 
        _token_in_g:U128, 
        _token_in_h:U128, 
        _token_in_i:U128, 
        _token_in_j:U128, 
        _token_in_k:U128,
        _token_in_l:U128, 
        _token_out_a:U128, 
        _token_out_b:U128, 
        _token_out_c:U128, 
        _token_out_d:U128, 
        _token_out_e:U128, 
        _token_out_f:U128, 
        _token_out_g:U128, 
        _token_out_h:U128, 
        _token_out_i:U128, 
        _token_out_j:U128, 
        _token_out_k:U128,
        _token_out_l:U128, 
        ) {

        assert(storage.current_epoch.read() == _current_epoch, "invalid_current_epoch");

        let epoch_to_total_token_in = array::to_array_from_u128(_token_in_a, _token_in_b, _token_in_c, _token_in_d, _token_in_e, _token_in_f, _token_in_g, _token_in_h, _token_in_i, _token_in_j, _token_in_k, _token_in_l);
        let epoch_to_total_token_out = array::to_array_from_u128(_token_out_a, _token_out_b, _token_out_c, _token_out_d, _token_out_e, _token_out_f, _token_out_g, _token_out_h, _token_out_i, _token_out_j, _token_out_k, _token_out_l);
 
        // let epoch_to_total_token_in = array::to_u128_from_field(_epoch_to_total_token_in);
        // let epoch_to_total_token_out = array::to_u128_from_field(_epoch_to_total_token_out);

        let mut end_epoch: U128 = U128::from_field(0);
        if (_current_epoch > _end_epoch) {
            end_epoch = _end_epoch;
        } else {
            end_epoch = _current_epoch;
        }

        let len = MAX_EPOCH as u64;
        for i in 0..len {
            let index: Field = i as Field + U128::to_field(_start_epoch);

            if (U128::from_field(index) <= _end_epoch) {
               assert(
                storage.epoch_to_total_token_in.at(index).read() == epoch_to_total_token_in[index], 
                "inavalid_epoch_to_total_token_in"
                );
               assert(
                storage.epoch_to_total_token_out.at(index).read() == epoch_to_total_token_out[index], 
                "inavalid_epoch_to_total_token_out"
                );
            }
        }
    }

    /// increase the dca amount of token-out at each epoch
    #[aztec(public)]
    #[aztec(internal)]
    fn _add_token_out_amount(amount: Field, start_epoch: Field, end_epoch: Field) {
        let len = MAX_EPOCH as u64;
        for i in 0..len {
            // let index: U128 = U128::from_integer(i) + start_epoch;
            let index: Field = i as Field + start_epoch;

            if (U128::from_field(index) <= U128::from_field(end_epoch)) {
               let total_amount = storage.epoch_to_total_token_out.at(index).read() + U128::from_field(amount);
               storage.epoch_to_total_token_out.at(index).write(total_amount);
            }
        }
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _validate_epoch(start_epoch: Field, end_epoch: Field) {
        assert(start_epoch as u32 != end_epoch as u32, "start_epoch is equal to end_epoch");
        assert(U128::from_field(start_epoch) >= storage.current_epoch.read(), "invalid start epoch");
        assert((U128::from_field(end_epoch) <= U128::from_field(MAX_EPOCH)), "invalid end epoch");
    }

    // #[aztec(public)]
    // #[aztec(internal)]
    // fn _is_admin() {
    //     assert(context.msg_sender().to_field() == storage.admin.read().to_field(), "invalid sender");
    // }

    unconstrained fn get_admin() -> pub Field {
        storage.admin.read().to_field()
    }

    unconstrained fn get_epoch() -> pub U128 {
        storage.current_epoch.read()
    }


    // private: register_dca_strategy
    // private: add_token_to_strategy
    // private: claim_asset
    // public: increase_total_liquidity

    // unconstrained fn compute_note_hash_and_nullifier(
    //     contract_address: AztecAddress,
    //     nonce: Field,
    //     storage_slot: Field,
    //     note_type_id: Field,
    //     preimage: [Field; DCA_NOTE_LEN]
    // ) -> pub [Field; 4] {
    //     let note_header = NoteHeader::new(contract_address, nonce, storage_slot);
    //     note_utils::compute_note_hash_and_nullifier(DCANote::deserialize_content, note_header, preimage)
        
    // }
}


/*

the reason why hiding sender addr is not enough but amount should be as blur as possible is to
decrease the chance for observers to tell from which address the fund comes from.
e.g. if address 0xA shields 100k dai right before a new 100k dai is deposited to this vault, 
there is a chance that this fund comes from the 0xA address. if user be cautious, he first puts
30k and subsequently, 50k, 10k, and 10k to reduce the chance. 
this is why `add_liquidity()` func is useful.

----

so, where can this go about nagating the potential loss due to the lack of total_deoposit_amount against sell_amount * epochs

1: in executeBatchSwap()
-> re-calculates total_token_out_amount but how without being able to know each user's DCANote
-> if month == epoch and users need to declare it publicly.. hmm this could leak sell_amount
-> 

2: end_epoch so... len can be caluclated like below
-> epoch = current_epoch > end_epoch ? end_epoch : current_epoch;
-> epoch_diff = epoch - start_epoch

this comes with re-initializing note at each claiming and occasionally each reset of dca strategy.


---

current challenge in implmenting claim function

1: unable to fetch epoch_to_token_in and _out, as private funcs can't access to public state
-> pass them as args and verify in pub funcs
2: hard to pass these arrays to pub func, as `call_public_function` only receives the array of Field 
   it doesn't technically seem impossible but then, the length of params will reach 27 lol
   i assume there should be max length of args in the system so it perhaps fails in runtime...
3:  
*/