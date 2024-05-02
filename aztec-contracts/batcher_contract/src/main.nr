mod deposit_note;
mod auth_action_note;
mod types;

// aztec-cli codegen ./target/ -o ../../test/artifacts --ts

/// This contract allows users to obfuscate their swap amounts when they trade on AMMs. 
/// It leverages an additive homomorphic encryption scheme to encrypt and 
/// aggregate users' input amounts without revealing individual amounts. 
/// The encrypted total amount is decrypted by a relayer who executes a batched swap.

contract BatcherVault {
    use dep::aztec::{
        prelude::{
        AztecAddress, FunctionSelector, Map, PublicMutable, PublicImmutable, PrivateMutable, SharedImmutable
        },
        context::Context,
    };
    use dep::authwit::auth::{IS_VALID_SELECTOR, compute_call_authwit_hash, compute_outer_authwit_hash};

    // libs
    use dep::noir_elgamal;
    use dep::std::ec::tecurve::affine::Point;

    // notes
    use crate::deposit_note::{DepositNote, DEPOSIT_NOTE_LEN};
    use crate::auth_action_note::{AuthActionNote, AUTH_ACTION_NOTE_LEN};

    // types
    use crate::types::{
        interfaces::{Token, Uniswap},
        relayer::{BatchRelayer, RELAYER_SERIALIZED_LEN},
        round::{Round, ROUND_SERIALIZED_LEN},
        affine_point::{AffinePoint, AFFINE_POINT_SERIALIZED_LEN},
        elgamal_affine_points::{ElgamalAffinePoints, ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN}
    };

    #[aztec(storage)]
    struct Storage {
        admin: PublicImmutable<AztecAddress>, // admin
        target: SharedImmutable<AztecAddress>, // amm or uniswap connect
        token_out: SharedImmutable<AztecAddress>, // token sold e.g. dai
        token_in: SharedImmutable<AztecAddress>, // token purchased e.g. eth
        current_round: PublicMutable<Field>,
        batch_relayer: PublicMutable<BatchRelayer>, // relayer's config
        rounds: Map<Field, PublicMutable<Round>>, // the mapping of storing token amount data for each round
        deposit_notes: Map<AztecAddress, PrivateMutable<DepositNote>>, // note of users' input amount
        auth_actions: Map<Field, PrivateMutable<AuthActionNote>>, // store private approved action
    }

    impl Storage {
      fn init(context: Context) -> Self {
        Storage {
            admin: PublicImmutable::new(context, 1),
            target: SharedImmutable::new(context, 2),
            token_out: SharedImmutable::new(context, 3),
            token_in: SharedImmutable::new(context, 4),
            current_round: PublicMutable::new(context, 5),
            batch_relayer: PublicMutable::new(context, 6),
            rounds: Map::new(context, 7, |context, slot| {
                    PublicMutable::new(context, slot)
                },
            ),
            deposit_notes: Map::new(context, 8,|context, slot| {
                    PrivateMutable::new(context, slot)
               },
            ),
            auth_actions: Map::new(context, 9,|context, slot| {
                    PrivateMutable::new(context, slot)
               },
            ),
        }
      }
    }

    /************************************************************************
     * Initialization Functions
     ************************************************************************/

    #[aztec(private)]
    #[aztec(initializer)]
    fn constructor(
        admin: AztecAddress, 
        target:AztecAddress, 
        token_in:AztecAddress, 
        token_out:AztecAddress, 
    ) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_initialize((Field),(Field),(Field),(Field))"), 
            [
                admin.to_field(),
                target.to_field(),
                token_in.to_field(),
                token_out.to_field()
            ]
        );
    }

    #[aztec(public)]
    #[aztec(internal)]
    #[aztec(noinitcheck)]
    fn _initialize(
        admin: AztecAddress, 
        target:AztecAddress, 
        token_in:AztecAddress, 
        token_out:AztecAddress
    ) {
        // should put asserts to validate params
        storage.admin.initialize(admin);
        storage.target.initialize(target);
        storage.token_in.initialize(token_in);
        storage.token_out.initialize(token_out);
        storage.current_round.write(1);
    }

    // Note: have separate init func for initializing relayer states
    // due to  (JSON-RPC PROPAGATED) Array size exceeds target length for deployment
    #[aztec(private)]
    fn init_relayer(
        relayer: AztecAddress,
        bonding_token: AztecAddress, 
        bonding_amount: Field,
        slash_amount: Field,
        he_pub_key: [Field;2],
        sk_hash: Field,
        he_secret_key: Field,
        interval: Field,
        nonce: Field
    ) {
        let computed_sk_hash = dep::std::hash::pedersen_hash([he_secret_key]);
        assert(sk_hash == computed_sk_hash, "invalid sk_hash");
     
        // TODO: Check he_secret_key corresponds to he_pub_key in bbj
        // assert(he_pub_key == noir_elgamal::priv_to_pub_key(he_secret_key))

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_init_relayer((Field),(Field),Field,Field,Field,Field,Field,Field)"), 
            [
                relayer.to_field(),
                bonding_token.to_field(),
                bonding_amount,
                slash_amount,
                he_pub_key[0],
                he_pub_key[1],
                sk_hash,
                interval
            ]
        );

        // stake bonding token
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_stake_bonding((Field),(Field),Field,Field)"), 
            [
                relayer.to_field(),
                bonding_token.to_field(),
                bonding_amount,
                nonce
            ]
        );
    }

    // store relayer's config in BatchRelayer struct
    #[aztec(public)]
    fn _init_relayer(
        relayer: AztecAddress,
        bonding_token: AztecAddress, 
        bonding_amount: Field,
        slash_amount: Field,
        he_pub_key_x: Field,
        he_pub_key_y: Field,
        sk_hash: Field,
        interval: Field
    ) {
        // should validate if caller is admin or can be called only once 
        let point = Point::new(he_pub_key_x, he_pub_key_y);
        let he_pub_key_affine = AffinePoint::new(point);
        assert(noir_elgamal::is_valid_subgroup(he_pub_key_affine.point), "Invalid public key");

        // init BatchRelayer
        let batch_relayer = BatchRelayer::new(
            relayer,
            bonding_token,
            bonding_amount,
            slash_amount,
            he_pub_key_affine,
            sk_hash,
            0, // timestamp
            interval
        );

        storage.batch_relayer.write(batch_relayer);
    }

    // Another init method to avoid the same error `Array size exceeds target length`
    // Initialize encrypted note with zero values
    #[aztec(public)]
    fn init_encrypted_note(rand: Field) {
        let batch_relayer = storage.batch_relayer.read();

        // intiialize Round with zero values for encrypted_token_out_amount
        let (c1, c2) = noir_elgamal::exp_elgamal_encrypt(batch_relayer.he_pub_key.point, 0 as u32, rand);
        let initial_encrypted_amount = ElgamalAffinePoints::new(
            AffinePoint::new(c1),
            AffinePoint::new(c2)
        );

        let mut round = storage.rounds.at(1).read();
        round.encrypted_token_out_amount.limb0 = initial_encrypted_amount;
        round.encrypted_token_out_amount.limb1 = initial_encrypted_amount;
        storage.rounds.at(1).write(round);
    }

    /************************************************************************
     * Users' Operations : Deposit, Cancel, and Claim
     ************************************************************************/

    // This method lets users to make swap request by depositing their funds,
    // calling another public function to store the encrypted amount 
    #[aztec(private)]
    fn deposit_to_batch(
        current_round: Field,
        amount_out: Field, 
        relayer_he_pubkey: AffinePoint,
        rands: [Field;2],
        nonce: Field
    ) {
        // TODO: validate current_round
        let sender = context.msg_sender();

        // initialize deposit_note
        let mut deposit_note = DepositNote::new(current_round, amount_out, sender);
        storage.deposit_notes.at(sender).initialize(
            &mut deposit_note,
            true
        );

        // transfer user's fund to this contract
        let asset = storage.token_out.read_private();
        Token::at(asset).transfer(
            &mut context,
            sender,
            context.this_address(),
            amount_out,
            nonce
        );

        // split amount_out into 2 limbs 
        let lower = (amount_out as u64 & 0xFFFFFFFF) as u32; // lower
        let upper = (amount_out as u64 >> 32) as u32; // upper

        // encrypt lower
        let (c1_0, c2_0) = noir_elgamal::exp_elgamal_encrypt(
               relayer_he_pubkey.point, 
               lower,
               rands[0]
        );

        // encrypt upper
       let (c1_1, c2_1) = noir_elgamal::exp_elgamal_encrypt(
               relayer_he_pubkey.point, 
               upper,
               rands[1]
        );

         // call _add_token_out_amount() to store the encrypted amount
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_add_token_out_amount([Field;2],[Field;2],[Field;2],[Field;2])"),
            [
              c1_0.x,
              c1_0.y,
              c2_0.x,
              c2_0.y,
              c1_1.x,
              c1_1.y,
              c2_1.x,
              c2_1.y
            ]
        );
    }
    
    // called by deposit_to_batch()
    // store encrypted deposit amount in the current round of rounds mapping
    #[aztec(public)]
    #[aztec(internal)]
    fn _add_token_out_amount(
        c1_0: [Field;2], 
        c2_0: [Field;2],
        c1_1: [Field;2], 
        c2_1: [Field;2]
    ) {
        let current_round = storage.current_round.read();
        let mut round = storage.rounds.at(current_round).read();

        let encrypted_value_to_add_0 = ElgamalAffinePoints::new(
            AffinePoint::deserialize(c1_0),
            AffinePoint::deserialize(c2_0)
        );

        let encrypted_value_to_add_1 = ElgamalAffinePoints::new(
            AffinePoint::deserialize(c1_1),
            AffinePoint::deserialize(c2_1)
        );

        let current_encrypted_sum = round.encrypted_token_out_amount;
        let new_encrypted_sum_0 = current_encrypted_sum.limb0.add(encrypted_value_to_add_0);
        let new_encrypted_sum_1 = current_encrypted_sum.limb1.add(encrypted_value_to_add_1);

        round.encrypted_token_out_amount.limb0 = new_encrypted_sum_0;
        round.encrypted_token_out_amount.limb1 = new_encrypted_sum_1;

        storage.rounds.at(current_round).write(round);
    }

    // This method lets users cancel their swap request and send the deposit back to the user
    // TODO: this func or another func should let users withdraw in the case of relayer failure
    // partial removal be a bit tricker but complete cancelling might be quite easy to implement
    #[aztec(private)]
    fn cancel_batch_and_claim(
        current_round: Field, 
        secret_hash:Field
    ) {
        
        let deposit_note = storage.deposit_notes.at(context.msg_sender()).get_note(false);

        // transfer cancelled amount to the sender
        let asset = storage.token_out.read_private();
        Token::at(asset).transfer(
            &mut context, 
            context.this_address(), 
            context.msg_sender(),
            deposit_note.amount_out,
            0
        );

        // report cancelled amount
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_sub_token_out_amount((Field),Field)"),
            [deposit_note.amount_out, current_round]
        ); 

        // make note empty
        let mut empty_deposit_note = DepositNote::empty();
        storage.deposit_notes.at(context.msg_sender()).replace(&mut empty_deposit_note, true);
    }

    /// "decrease" (increase) `token_out_amount_cancelled` in rounds
    #[aztec(public)]
    #[aztec(internal)]
    fn _sub_token_out_amount(amount: Field, _round: Field) {
        let mut round = storage.rounds.at(_round).read();
        round.token_out_amount_cancelled = amount;
        storage.rounds.at(_round).write(round);
    }

    // This method lets users claim their share of the output amount 
    // calculated based on their pro-rata share of the input amount in a batch. 
    // claim_amount is calculated like "total_token_in * amount_out / total_token_out"
    #[aztec(private)]
    fn claim_token_in(
        round: Field, 
        total_token_in: Field, 
        total_token_out: Field, 
        token_out_amount_cancelled: Field
    ) {
        let sender = context.msg_sender();
        // fetch user's deposit_ note
        let mut deposit_note = storage.deposit_notes.at(sender).get_note(false);

        // validate params
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_validate_claim_params(Field,Field,Field,Field)"), 
            [deposit_note.round, total_token_in, total_token_out, token_out_amount_cancelled]
        ); 

        // calculate total token_in purchased at a specificed round
        let token_out_amount = total_token_out - token_out_amount_cancelled;
        let claim_token_in_amount = (total_token_in * deposit_note.amount_out / token_out_amount);

        // individual users make this contract transfer token_in out to them
        let asset = storage.token_in.read_private();
        Token::at(asset).transfer(
            &mut context,
            context.this_address(),
            sender,
            claim_token_in_amount,
            0
        );

        // "destroy" used deposit note
        deposit_note.round = 0;
        deposit_note.amount_out = 0;
        storage.deposit_notes.at(context.msg_sender()).replace(&mut deposit_note, true);
    }

    #[aztec(public)] 
    #[aztec(internal)]
    fn _validate_claim_params(
        _round: Field, 
        _total_token_in: Field,
        _total_token_out: Field,
        _token_out_amount_cancelled: Field
    ) {
        let round = storage.rounds.at(_round).read();
        assert(round.token_in_amount == _total_token_in, "invalid _total_token_in");
        assert(round.token_out_amount == _total_token_out, "invalid _total_token_out");
        assert(round.token_out_amount_cancelled == _token_out_amount_cancelled, "invalid _token_out_amount_cancelled");
    }

    /************************************************************************
     * Relayer's Operations | Execute Batch, Finalize Batch, and Dispute
     ************************************************************************/

    // This method lets relayer execute a batch for a certain round.
    // 1: decrypts splitted encrypted deposit amounts and combine them
    // 2: approves the AMM contract for unshielding funds from this contract
    // 3: calls swap function on AMM contract
    #[aztec(private)]
    fn execute_batch(
        plaintext_lower: Field,
        plaintext_upper: Field,
        ciphertext_lower_1: AffinePoint,
        ciphertext_lower_2: AffinePoint,
        ciphertext_upper_1: AffinePoint,
        ciphertext_upper_2: AffinePoint,
        secret_key: Field,
        token_out_amount_cancelled: Field,
        nonce0: Field,
        nonce1: Field,
        secret_hash: Field
    ) -> pub Field {
        // caller should be an authorized relayer 
        // assert(context.msg_sender() == storage.batch_relayer.relayer, "caller must be relayer");

        let decrytped_lower = noir_elgamal::exp_elgamal_decrypt(
            secret_key, 
            (ciphertext_lower_1.point, ciphertext_lower_2.point)
        );

        let decrytped_upper = noir_elgamal::exp_elgamal_decrypt(
            secret_key, 
            (ciphertext_upper_1.point, ciphertext_upper_2.point)
        );

        let bjj_affine = noir_elgamal::get_affine_curve();
        let base_pt = noir_elgamal::get_base_point();

        let point_lower = bjj_affine.mul(plaintext_lower, base_pt);
        let point_upper = bjj_affine.mul(plaintext_upper, base_pt);

         assert(point_lower.eq(decrytped_lower), "invalid plaintext_lower");
         assert(point_upper.eq(decrytped_upper), "invalid plaintext_upper");

        // combine lower & upper
        let total_amount = ((plaintext_upper as u64 << 32) as u64 | plaintext_lower as u64) as Field;
        // subtract cancelled amount
        let amount_out_minus_cancelled = total_amount - token_out_amount_cancelled;
        // 10x exchange rate for test
        let expected_token_in = amount_out_minus_cancelled * 10;

        // validate params in public func
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("validate_execute_batch((Field),Field,Field,Field)"), 
            [
                context.msg_sender().to_field(),
                total_amount, 
                amount_out_minus_cancelled,
                expected_token_in
            ]
        );

        // approve amm to unshield token from this contract
        let selector = FunctionSelector::from_signature("unshield((Field),(Field),Field,Field)");
        let target = storage.target.read_private();
        let message_hash = compute_call_authwit_hash(
            target,
            storage.token_out.read_private(),
            context.chain_id(),
            context.version(),
            selector,
            [context.this_address().to_field(), target.to_field(), amount_out_minus_cancelled, 0]
        );

        // store message_hash in note
        let mut auth_action_note = AuthActionNote::new(true, context.msg_sender());
        storage.auth_actions.at(message_hash).initialize(
            &mut auth_action_note,
            true
        );

        // call `swap_private` on the mock AMM contract
        context.call_private_function(
            storage.target.read_private(),
            FunctionSelector::from_signature("swap_private(Field,Field,Field,Field,Field)"), 
            [
                expected_token_in, 
                amount_out_minus_cancelled,
                nonce0, 
                nonce1,
                secret_hash // for claiming shielded purchased token
            ]
        );  

        amount_out_minus_cancelled
    }
    
    // for target contract to be able to receive(unshield) token from this cotnract.
    #[aztec(private)]
    fn spend_private_authwit(inner_hash: Field) -> Field {
        let message_hash = compute_outer_authwit_hash(
            context.msg_sender(),
            context.chain_id(),
            context.version(),
            inner_hash
        );
        
        // get boolean value for an action stored in note
        let auth_action = storage.auth_actions.at(message_hash).get_note(false);
        
        if (auth_action.approved) {
            context.push_new_nullifier(message_hash, 0);
            IS_VALID_SELECTOR
        } else {
            0
        }
    }

    // called by `execute_batch()`
    // validate params and store necessary in public context 
    #[aztec(public)]
    #[aztec(internal)]
    fn validate_execute_batch(
        sender: AztecAddress, 
        amount_out:Field,
        amount_out_sub_cancelled:Field,
        expected_token_in: Field
    ) {
        let relayer = storage.batch_relayer.read();
        let exp_current_time = relayer.last_timestamp + relayer.interval;
        assert(context.timestamp() as u64 >= exp_current_time as u64, "time hasn't elapsed enough to update round");
        assert(sender == relayer.relayer, "caller must be relayer");

        let current_round = storage.current_round.read();
        let mut round = storage.rounds.at(current_round).read();
        assert(!round.executed, "already executed");

        let _amount_out_sub_cancelled = amount_out - round.token_out_amount_cancelled;
        assert(amount_out_sub_cancelled == _amount_out_sub_cancelled, "invalid_cancelled_amount_out");

        // TODO: validate swap amount or decrypted data against encyrpted ammounts

        // store data for the round
        round.expected_min_token_in = expected_token_in;
        round.token_out_amount = amount_out_sub_cancelled;
        round.executed = true;
        storage.rounds.at(current_round).write(round);
    }

    // This method is called right after `execute_batch()` to finialize the batch execution.
    // it lets the relayer redeem pending shield and update the acquired eth amount
    // of the latest round after eth purchase at the `batch_execute()`
    #[aztec(private)]
    fn finalize_execute(
        token_in_amount: Field,
        secret: Field
    ) {
        // claim pending shield created by target contract
        let token_in = storage.token_in.read_private();
        Token::at(token_in).redeem_shield(&mut context, context.this_address(), token_in_amount, secret);

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_finalize_execute(Field)"), 
            [token_in_amount]
        );  
    }

    // called internally from `finalize_execute()`
    // validate params and store necessary in public context 
    #[aztec(public)]
    #[aztec(internal)]
    fn _finalize_execute(token_in_amount: Field) {
        let current_round = storage.current_round.read();
        let mut round = storage.rounds.at(current_round).read();
        assert(round.executed, "batch tx hasn't been executed");
        assert(!round.claimed, "pending shield for this round has already been claimed");
        assert(U128::from_field(token_in_amount) >= U128::from_field(round.expected_min_token_in), "insufficient token_in_amount");

         // store token_in_amount
        round.token_in_amount = token_in_amount;
        round.claimed = true;
        storage.rounds.at(current_round).write(round);

        // increment round count
        storage.current_round.write(current_round + 1);
    }

    /************************************************************************
     * Functions for Relayer Dispute
     ************************************************************************/

    // This method lets caller slash the existing relayer and optionally take over the relayer role.
    // caller should provide the correct `he_secret_key`
    #[aztec(private)]
    fn dispute_relayer(
        he_secret_key: Field, 
        new_sk_hash: Field, 
        new_he_pub_key_x: Field,
        new_he_pub_key_y: Field,
        new_he_secret_key: Field,
        new_relayer: AztecAddress,
        only_slash: bool
        ) {

        let sk_hash = dep::std::hash::pedersen_hash([he_secret_key]);
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("check_sk_hash(Field)"),
            [sk_hash]
        ); 

        if (only_slash) {
            context.call_public_function(
               context.this_address(),
               FunctionSelector::from_signature("slash((Field))"),
               [context.msg_sender().to_field()]
            );   
        } else {
           
           // validate that new_sk_hash == hash(new_he_secret_key);
           let new_computed_sk_hash = dep::std::hash::pedersen_hash([new_he_secret_key]);
           assert(new_sk_hash == new_computed_sk_hash, "invalid_new_sk_hash");
        
           // TODO: Check new_he_secret_key corresponds to new_he_pub_key in bbj
           // assert(he_pub_key == noir_elgamal::priv_to_pub_key(he_secret_key))

           context.call_public_function(
               context.this_address(),
               FunctionSelector::from_signature("replace_relayer(Field,Field,Field,(Field))"),
               [
                   new_sk_hash, 
                   new_he_pub_key_x,
                   new_he_pub_key_y,
                   new_relayer.to_field()
               ]
           ); 
        }


    }

    #[aztec(public)]
    #[aztec(internal)]
    fn slash(recipient: AztecAddress) {
        // replacement from slashed relayer to a new relayer ( disputer )
        let relayer = storage.batch_relayer.read();

        // slash by shielding staked asset to new relayer
        Token::at(relayer.bonding_token).transfer_public(
            &mut context, 
            context.this_address(), 
            recipient,
            relayer.slash_amount,
            0
        );
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn replace_relayer(
        sk_hash: Field, 
        new_he_pub_key_x: Field, 
        new_he_pub_key_y: Field,
        new_relayer: AztecAddress,
    ) {
        // replacement from slashed relayer to a new relayer ( disputer )
        let mut relayer = storage.batch_relayer.read();
        relayer.relayer = new_relayer;
        relayer.sk_hash = sk_hash;
        // store new pub key 
        relayer.he_pub_key = AffinePoint::new(Point::new(new_he_pub_key_x, new_he_pub_key_y));
        storage.batch_relayer.write(relayer); 
    }

    // called by relayer_init func
    // transfer relayer's fund to this contract
    #[aztec(public)] 
    #[aztec(internal)] 
    fn _stake_bonding(relayer: AztecAddress, token:AztecAddress, amount:Field, nonce:Field) {
        let batch_relayer = storage.batch_relayer.read();
        assert(U128::from_field(amount) >= U128::from_field(batch_relayer.bonding_amount), "insufficient bonding amount");
        // TODO: also verify caller == relayer in normal situation..?

        // transfer public
        Token::at(token).transfer_public(
            &mut context, 
            relayer,
            context.this_address(), 
            amount,
            nonce
        );
    }

    // TODO: withdraw_bonding
    #[aztec(public)] 
    fn withdraw_bonding(relayer: AztecAddress, token:AztecAddress, amount:Field) {
        Token::at(token).transfer_public(
            &mut context, 
            context.this_address(), 
            relayer,
            amount,
            0
        );
    }

    #[aztec(public)]
    fn check_sk_hash(sk_hash: Field) {
        assert(sk_hash == storage.batch_relayer.read().sk_hash, "invalid sk_hash");
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _validate_round(round:Field) {
        let current_round = storage.current_round.read();
        assert(current_round == round, "invalid_round");
    }

    /************************************************************************
     * Unconstrained Functions
     ************************************************************************/

    unconstrained fn get_admin() -> pub Field {
        storage.admin.read().to_field()
    }

    unconstrained fn get_target_address() -> pub Field {
        storage.target.read_public().to_field()
    }

    unconstrained fn get_token_in() -> pub Field {
        storage.token_in.read_public().to_field()
    }

    unconstrained fn get_token_out() -> pub Field {
        storage.token_out.read_public().to_field()
    }

    unconstrained fn get_token_in_total_amount(round: Field) -> pub Field {
        storage.rounds.at(round).read().token_in_amount
    }

    unconstrained fn get_token_out_total_amount(round: Field) -> pub Field {
       storage.rounds.at(round).read().token_out_amount
    }

    unconstrained fn get_token_out_amount_cancelled(round: Field) -> pub Field {
        storage.rounds.at(round).read().token_out_amount_cancelled
    }

    unconstrained fn get_round() -> pub Field {
        storage.current_round.read()
    }

    unconstrained fn get_batch_relayer() -> pub BatchRelayer {
        storage.batch_relayer.read()
    }

    unconstrained fn get_encrypted_sum(current_round:Field) -> pub [Field;8] {
        let mut ret:[Field;8] = [0;8];
        storage.rounds.at(current_round).read().get_encrypted_amount()
    }

    unconstrained fn get_sk_hash(he_secret_key: Field) -> pub Field {
        dep::std::hash::pedersen_hash([he_secret_key])
    }

    /************************************************************************
     * For testing 
     ************************************************************************/

    #[test]
    fn test_get_sk_hash() {
        let sk = 2360067582289791756090345803415031600606727745697750731963540090262281758098;
        let ret = get_sk_hash(sk);
        dep::std::println(ret);
    }

    // unconstrained fn split(amount: Field) -> pub [u32;2] {
    unconstrained fn split(amount: Field) -> pub u64 {
        let amount_u64 = amount as u64;
        let mut amounts: [u32;2] = [0 as u32;2];
        amounts[0] = (amount_u64 & 0xFFFFFFFF) as u32; // lower
        dep::std::println(amounts[0]);
        amounts[1] = (amount_u64 >> 32) as u32; // upper
        dep::std::println(amounts[1]);
        
        let ret = (amounts[1] as u64 << 32) as u64 | amounts[0] as u64;
        dep::std::println(ret);
        ret
    }    

    #[test]
    fn test_split() {
        let amount = 5000000000000000000;
        let ret = split(amount);
         dep::std::println(ret);
    }

    unconstrained fn combine(lower: u64, upper: u64) -> pub u64 {
        let ret = (upper << 32) as u64 | lower as u64;
        ret
    }

    #[test]
    fn test_combine() {
        // let ret = combine(5451808768, 1164153217);
         let ret = combine(5232427008, 1164152);

         dep::std::println(ret);
    }


    unconstrained fn tsdasa(fields:[Field;8]) {
        let mut limb_0: [Field;4] = [0; 4];
        let mut limb_1: [Field;4] = [0; 4];

        for i in 0..4 {
            
            limb_0[i] = fields[i];
            limb_1[i] = fields[i + 4];
        }
        dep::std::println(limb_0);
         dep::std::println(limb_1);
    } 

    #[test]
    fn test_tsdasa() {
        let amount: [Field;8] = [1, 2, 3, 4, 5, 6, 7, 8];
        tsdasa(amount);
    }

    unconstrained fn to_point() {
        let lower = 5232427008;
        let bjj_affine = noir_elgamal::get_affine_curve();
        let base_pt = noir_elgamal::get_base_point();
        let ret = bjj_affine.mul(lower, base_pt);
        dep::std::println(ret);
    }

    #[test]
    fn test_to_point() {
        to_point();
    }
}