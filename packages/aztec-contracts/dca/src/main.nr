mod dca_note;
mod interfaces;
mod array;

// What this contract does
// - users can privately register dca strategy
// - users can privately deposit token_out, say DAI, for a given strategy to dca token_in, say ETH
// - users can privately claim dca-ed ETH
// - a dca strategy per address

// *** what's public and private ? *** 
// 1: user address: private
// 2: input amount: public but can be more private by splitting
// 3: output amount: private
// greater than the original dca-bridge blueprint with only output amount being private
// https://docs.google.com/document/d/1OWLA41AIiwszgL5eQn4vyTKvFtKHJlBZBdveUpgtOeA/view

contract DCAVault {
    // use dep::aztec::prelude::{FunctionSelector, AztecAddress, Map, PublicImmutable, PublicMutable, PublicImmutable, PrivateMutable};
    use dep::aztec::prelude::{
        AztecAddress, EthAddress, FunctionSelector, NoteHeader, NoteGetterOptions, NoteViewerOptions,
        PrivateContext, Map, PublicMutable, PublicImmutable, PrivateMutable, SharedImmutable
    };
    use dep::aztec::{note::note_getter_options::Comparator, context::{PublicContext, Context}};
    use crate::interfaces::{Token, Uniswap};
    use crate::dca_note::{DCANote, DCA_NOTE_LEN, MAX_EPOCH};
    use crate::array;

    struct Storage {
        admin: PublicImmutable<AztecAddress>,
        uniswap: SharedImmutable<AztecAddress>,
        token_out: SharedImmutable<AztecAddress>,
        token_in: SharedImmutable<AztecAddress>,
        current_epoch: PublicMutable<U128>,
        epoch_to_total_token_out: Map<Field, PublicMutable<U128>>, // epoch -> dai amount sold every epoch 
        epoch_to_total_token_in: Map<Field, PublicMutable<U128>>, // epoch -> eth amount bought by dca each epoch
        dca_notes: Map<AztecAddress, PrivateMutable<DCANote>>,
        epoch_to_dca_executed: Map<Field, PublicMutable<bool>>, 
    }

    impl Storage {
      fn init(context: Context) -> Self {
        Storage {
            admin: PublicImmutable::new(context, 1),
            uniswap: SharedImmutable::new(context, 2),
            token_out: SharedImmutable::new(context, 3),
            token_in: SharedImmutable::new(context, 4),
            current_epoch: PublicMutable::new(context, 5),
            epoch_to_total_token_out: Map::new(context, 6, |context, slot| {
                    PublicMutable::new(context, slot)
                },
            ),
            epoch_to_total_token_in: Map::new(context, 7, |context, slot| {
                    PublicMutable::new(context, slot)
                },
            ),
            dca_notes: Map::new(context, 8,|context, slot| {
                    PrivateMutable::new(context, slot)
               },
            ),
            epoch_to_dca_executed:  Map::new(context, 9,|context, slot| {
                 PublicMutable::new(context, slot)
            },
            ),
        }
      }
    }


    #[aztec(private)]
    fn constructor(admin: AztecAddress, uniswap:AztecAddress, token_in:AztecAddress, token_out:AztecAddress) {
        let selector = FunctionSelector::from_signature("_initialize((Field),(Field),(Field),(Field))");
        context.call_public_function(context.this_address(), selector, [admin.to_field(), uniswap.to_field(), token_in.to_field(), token_out.to_field()]);
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
        assert(new_epoch <= U128::from_field(12), "epoch has reached max");
        storage.current_epoch.write(new_epoch);
    }

    // here anyone can update the acquired eth reward of the latest epoch after eth purchase
    // but this should only occur once each epoch, so...
    // 1: if `execute_batch_dca` for current epoch has already been executed => revert
    // 2: if epoch_to_token_in[current_epoch] != 0 => revert
    #[aztec(public)]
    fn update_token_in_balance() {
        let epoch = storage.current_epoch.read().to_field();
        assert(storage.epoch_to_dca_executed.at(epoch).read(), "dca hasn't been executed for this epoch");
        assert(storage.epoch_to_total_token_in.at(epoch).read() == U128::from_field(0), "already updated");

        let mut total_token_in_amount:Field = 0;
        for i in 0..12 {
            total_token_in_amount = total_token_in_amount + storage.epoch_to_total_token_in.at(epoch).read().to_field();
        }

        let token_in = storage.token_in.read_public();
        // get eth balance
        let balance = Token::at(token_in).balance_of_public(&mut context, context.this_address());
        // new balance acquried at the latest epoch = current balance - culmulative balances
        let new_balance = balance - total_token_in_amount;

        // store the new balance 
        storage.epoch_to_total_token_in.at(epoch).write(U128::from_field(new_balance));
    }

    // This method handles token deposit from users
    // and records the amount and duration in DCA Note.
    // if `init` is true: initialize dca note 
    // if `init` is false: add dca_amount to the existing dca position.
    #[aztec(private)]
    fn add_dca_amount(
        dca_amount: U128, 
        total_deposit_amount:U128, // dca_amount * (end_epoch - start_epoch)
        start_epoch: U128, 
        end_epoch: U128,
        nonce_for_unshield_approval:Field,
        init: bool // true if dca_note for an acc has never been created
    ) {

        let sender = context.msg_sender();
        let mut dca_note = DCANote::empty();

        // init
        if (init) {
            assert((end_epoch - start_epoch) > U128::from_field(0), "invalid epochs");
            
            context.call_public_function(
               context.this_address(),
               FunctionSelector::from_signature("_validate_epoch((Field),(Field))"),
               [U128::to_field(start_epoch), U128::to_field(end_epoch)]
            );

            let total_dca_amount = dca_amount * (end_epoch - start_epoch);
            assert(total_deposit_amount == total_dca_amount, "total_deposit_amount isn't equal to total_dca_amount");

            dca_note = DCANote::new(dca_amount, total_deposit_amount, start_epoch, end_epoch, sender);
            storage.dca_notes.at(sender).initialize(
               &mut dca_note,
               true
            );

        // add
        } else {

           let _dca_note = storage.dca_notes.at(sender).get_note(false);
           let new_dca_amount: U128 = _dca_note.dca_amount + dca_amount;
           let new_total_deposit_amount: U128 = new_dca_amount * (_dca_note.end_epoch - _dca_note.start_epoch);
           assert(new_total_deposit_amount == (_dca_note.total_deoposit_amount + total_deposit_amount), "invalid total_deposit_amount");

           // here i may add logics for changes in epoch, tho, complexity...

           dca_note = DCANote::new(
               new_dca_amount, 
               new_total_deposit_amount,
               _dca_note.start_epoch,
               _dca_note.end_epoch,
               sender
           );

           storage.dca_notes.at(sender).replace(&mut dca_note, true);
        }

        let asset = storage.token_out.read_private();
        Token::at(asset).unshield(
            &mut context,
            sender,
            context.this_address(),
            total_deposit_amount.to_field(),
            nonce_for_unshield_approval
        );

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_add_token_out_amount((Field),(Field),(Field))"),
            [dca_amount.to_field(), dca_note.start_epoch.to_field(), dca_note.end_epoch.to_field()]
        );
        
    }

    #[aztec(private)]
    fn remove_dca_amount(amount:U128, total_withdraw_amount:U128, secret_hash:Field) {
        
        let dca_note = storage.dca_notes.at(context.msg_sender()).get_note(false);
        let new_dca_amount: U128 = dca_note.dca_amount - amount;
        let new_total_deposit_amount = new_dca_amount * (dca_note.end_epoch - dca_note.start_epoch);
        assert(new_total_deposit_amount == (dca_note.total_deoposit_amount - total_withdraw_amount), "invalid total_withdraw_amount");

        let mut new_dca_note = DCANote::new(
            new_dca_amount, 
            new_total_deposit_amount,
            dca_note.start_epoch,
            dca_note.end_epoch,
            context.msg_sender()
        );

        storage.dca_notes.at(context.msg_sender()).replace(&mut new_dca_note, true);

        let asset = storage.token_out.read_private();
        Token::at(asset).shield(
            &mut context, 
            context.this_address(), 
            U128::to_field(total_withdraw_amount),
            secret_hash, 
            0
        );

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_sub_token_out_amount((Field),(Field),(Field))"),
            [amount.to_field(), dca_note.start_epoch.to_field(), dca_note.end_epoch.to_field()]
        ); 
    }

    #[aztec(private)]
    fn change_duration(new_duration:Field) {
        // longer duration -> deposit increases accordingly
        // shorter duration -> deposit decreases accordingly
    }

    // from relayer or amind controlled by L1 contract with timestamp checkers
    // minimum_output_amount should be calculated based on uniswap twap
    #[aztec(public)]
    fn execute_batch_dca(
        input_asset_bridge: AztecAddress,
        output_asset_bridge: AztecAddress,
        nonce_for_transfer_approval: Field,
        uniswap_fee_tier: Field,
        minimum_output_amount: Field,
        secret_hash_for_L1_to_l2_message: Field,
        caller_on_L1: EthAddress,
        nonce_for_swap_approval: Field
    ) {
        // caller should be an authorized relayer 

        let epoch = storage.current_epoch.read().to_field();
        assert(!storage.epoch_to_dca_executed.at(epoch).read(), "already executed");

        let input_amount = storage.epoch_to_total_token_out.at(epoch).read();
        
        let uniswap = storage.uniswap.read_public();
        Uniswap::at(uniswap).swap_public(
            &mut context,
            context.this_address(),
            input_asset_bridge,
            input_amount.to_field(),
            output_asset_bridge,
            nonce_for_transfer_approval,
            uniswap_fee_tier,
            minimum_output_amount,
            context.this_address(),
            secret_hash_for_L1_to_l2_message,
            caller_on_L1,
            nonce_for_swap_approval
        );

        storage.epoch_to_dca_executed.at(epoch).write(true);

        // how to record the eth amount brdiged back from L1...?
        // assuming the eth bridged back will be sent directly to this address
        // then relayer updates `epoch_to_total_token_in` once every epoch before
        // claim only considers one-epoch before the current epoch.
        // then all the bridge eth amount can be reflected correctly.
        // if relayer forgot to updates it?? 
        // -> make the func essentially callable by anyone!
    }

    // here probably there is need to implement create public auth wit
    // so that uniswap contract can receive(transfer) token from this cotnract.
    #[aztec(public)] 
    fn spend_public_authwit(inner_hash: Field) -> Field {
        // let message_hash = compute_outer_authwit_hash(
        //     context.msg_sender(),
        //     context.chain_id(),
        //     context.version(),
        //     inner_hash
        // );
        // let value = storage.approved_action.at(message_hash).read();
        // if (value) {
        //     context.push_new_nullifier(message_hash, 0);
        //     IS_VALID_SELECTOR
        // } else {
        //     0
        // }
        0
    }

    // from user
    #[aztec(private)]
    fn claim_token_in(
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
               eth_amount = eth_amount + (epoch_to_total_token_in[index] * dca_note.dca_amount / epoch_to_total_token_out[index]);
            }
        }

        // TODO: dca note should be replaced with a new dsa note with reduced amounts 
        // suppose partial claim is not possible, epoch nums can also be zeroed.

        // individual users can execute private transfer in this address..?
        let _callStackItem = context.call_private_function(
            storage.token_out.read_private(),
            FunctionSelector::from_signature("transfer((Field),(Field),Field,Field)"),
            [context.this_address().to_field(), context.msg_sender().to_field(), U128::to_field(eth_amount), 0]
        );
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _initialize(admin: AztecAddress, uniswap:AztecAddress, token_in:AztecAddress, token_out:AztecAddress) {
        assert(admin.to_field() != 0, "invalid admin address");
        storage.admin.initialize(admin);
        storage.uniswap.initialize(uniswap);
        storage.token_in.initialize(token_in);
        storage.token_out.initialize(token_out);
    }

    #[aztec(public)] 
    #[aztec(internal)]
    fn _validate_claim_params(
        _current_epoch: U128, 
        _end_epoch: U128,
        _start_epoch: U128,
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
    fn _add_token_out_amount(amount: U128, start_epoch: U128, end_epoch: U128) {
        let len = MAX_EPOCH as u64;
        for i in 0..len {
            let index: Field = i as Field + start_epoch.to_field();

            if (U128::from_field(index) <= end_epoch) {
               let total_amount = storage.epoch_to_total_token_out.at(index).read() + amount;
               storage.epoch_to_total_token_out.at(index).write(total_amount);
            }
        }
    }

    /// decrease the dca amount of token-out at each epoch
    #[aztec(public)]
    #[aztec(internal)]
    fn _sub_token_out_amount(amount: U128, start_epoch: U128, end_epoch: U128) {
        let len = MAX_EPOCH as u64;
        for i in 0..len {
            let index: Field = i as Field + start_epoch.to_field();

            if (U128::from_field(index) <= end_epoch) {
               let total_amount = storage.epoch_to_total_token_out.at(index).read() - amount;
               storage.epoch_to_total_token_out.at(index).write(total_amount);
            }
        }
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _validate_epoch(start_epoch: U128, end_epoch: U128) {
        assert(start_epoch != end_epoch, "start_epoch is equal to end_epoch");
        assert(start_epoch >= storage.current_epoch.read(), "invalid start epoch");
        assert((end_epoch <= U128::from_field(MAX_EPOCH)), "invalid end epoch");
    }

    unconstrained fn get_admin() -> pub Field {
        storage.admin.read().to_field()
    }

    unconstrained fn get_uniswap_bridge_address() -> pub Field {
        storage.uniswap.read_public().to_field()
    }

    unconstrained fn get_token_in() -> pub Field {
        storage.token_in.read_public().to_field()
    }

    unconstrained fn get_token_out() -> pub Field {
        storage.token_out.read_public().to_field()
    }

    unconstrained fn get_epoch() -> pub U128 {
        storage.current_epoch.read()
    }
}


/*

TODO 1: figure out a way for users to manipulate note owned by contract.
so that users can claim funds sit on contracts privately.
`crowdfunding` contract somehow lets user withdraw token privately by `transfer` but 
im not quite sure how this is feasible. the value note created at donating is not used weirdly.

TODO 2: implement splitter contract and making DCA act as a batcher

the reason why hiding sender addr is not enough but amount should be as blur as possible is to
decrease the chance for observers to tell from which address the fund comes from.
e.g. if address 0xA shields 100k dai right before a new 100k dai is deposited to this vault, 
there is a chance that this fund comes from the 0xA address. if user be cautious, he first puts
30k and subsequently, 50k, 10k, and 10k to reduce the chance. 

`add_balance` func should be called by splitter, which is initiated by relayer, on users behalf.

----

TODO 3: epoch management
currently, when / which funcs relayers and users can do are not restricted but this is disruptive otherwise.

---- 

TODO 4: add relayer. by default admin == relayer but they can be separate

---- 

TODO 5: claim function for relayers to deposit the token_in back to this contract, 
        recording the total amount in epoch_to_total_token_in

Current Limitation
1: to achive split-deposit, users need to call `add_dca_amount()` multiple times
   private action * relayer might not be technically feasible
   https://github.com/AztecProtocol/aztec-packages/blob/master/docs/docs/learn/concepts/accounts/authwit.md
   relayer needs to know decryption key to know how many amounts 
2: unsure if private-transfer from contract to account(caller) is possible
3: a lack of timestamp in L2
4: no custom slippage for each user ( this contract has minimum slippage visible to users )
5: no custom dca period ( this value can also be pre-defined on contract )

*/