mod deposit_note;
mod auth_action_note;
mod types;

// aztec-cli codegen ./target/ -o ../../test/artifacts --ts

contract BatcherVault {
    use dep::aztec::prelude::{
        AztecAddress, EthAddress, FunctionSelector, NoteHeader, NoteGetterOptions, NoteViewerOptions,
        Map, PublicMutable, PublicImmutable, PrivateMutable, SharedImmutable
    };
    use dep::aztec::{note::note_getter_options::Comparator, 
        context::{Context, PrivateContext, PublicContext, gas::GasOpts}
    };

    use dep::authwit::auth::{
        IS_VALID_SELECTOR, assert_current_call_valid_authwit_public, compute_call_authwit_hash,
        compute_outer_authwit_hash
    };

    use dep::noir_elgamal;
    use dep::std::ec::tecurve::affine::Point;

    // note
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
        batch_relayer: PublicMutable<BatchRelayer>,
        rounds: Map<Field, PublicMutable<Round>>,
        deposit_notes: Map<AztecAddress, PrivateMutable<DepositNote>>, 
        auth_actions: Map<Field, PrivateMutable<AuthActionNote>>,   
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

    // have separate init func for initializing relayer states
    // due to  (JSON-RPC PROPAGATED) Array size exceeds target length for deployment
    // should only be called by relayer if admin & relayer are separate 
    #[aztec(private)]
    fn init_relayer(
        relayer: AztecAddress,
        bonding_token: AztecAddress, 
        bonding_amount: Field,
        he_pub_key: [Field;2],
        sk_hash: Field,
        he_secret_key: Field,
        interval: Field
    ) {
        let computed_sk_hash = dep::std::hash::pedersen_hash([he_secret_key]);
        assert(sk_hash == computed_sk_hash, "invalid sk_hash");
     
        // TODO: Check he_secret_key corresponds to he_pub_key in bbj
        // https://github.com/jat9292/babyjubjub-utils/blob/f93b474f35a302543b9f703b00c4e0628b5b88a7/index.js#L87

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_init_relayer((Field),(Field),Field,Field,Field,Field,Field)"), 
            [
                relayer.to_field(),
                bonding_token.to_field(),
                bonding_amount,
                he_pub_key[0],
                he_pub_key[1],
                sk_hash,
                interval
            ]
        );

    }

    #[aztec(public)]
    fn _init_relayer(
        relayer: AztecAddress,
        bonding_token: AztecAddress, 
        bonding_amount: Field,
        he_pub_key_x: Field,
        he_pub_key_y: Field,
        sk_hash: Field,
        interval: Field
    ) {
        // should validate if caller is admin or can be called only once 
        let point = Point::new(he_pub_key_x, he_pub_key_y);
        let he_pub_key_affine = AffinePoint::new(point);
        assert(noir_elgamal::is_valid_subgroup(he_pub_key_affine.point), "Invalid public key");

        // relayer provides batch_relayer states
        let batch_relayer = BatchRelayer::new(
            relayer,
            bonding_token,
            bonding_amount,
            he_pub_key_affine,
            sk_hash,
            0, // timestamp
            interval
        );
        storage.batch_relayer.write(batch_relayer);
        // TODO: maybe perform stake too here
    }

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
     * Admin's Operations
     ************************************************************************/

     // TODO:
     // set_relayer(): set a new relayer
     // set_relayer_params: set new relayer params, e.g. bonding_token, bonding_amount, etc...


    /************************************************************************
     * Users' Operations : Deposit, Withdraw, and Claim
     ************************************************************************/

    // TODO: some checks if relayer has already made a deposit before users depositing
    // todo: init round after incrementing round 
    #[aztec(private)]
    fn deposit_to_batch(
        current_round: Field,
        amount_out: Field, 
        relayer_he_pubkey: AffinePoint,
        // rand: Field,
        rands: [Field;2],
        nonce: Field
    ) {
        // TODO: validate current_round
        let sender = context.msg_sender();
        // let mut deposit_note = DepositNote::empty();

        let mut deposit_note = DepositNote::new(current_round, amount_out, sender);
        storage.deposit_notes.at(sender).initialize(
            &mut deposit_note,
            true
        );

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

        let (c1_0, c2_0) = noir_elgamal::exp_elgamal_encrypt(
               relayer_he_pubkey.point, 
               lower,
               rands[0]
        );

       let (c1_1, c2_1) = noir_elgamal::exp_elgamal_encrypt(
               relayer_he_pubkey.point, 
               upper,
               rands[1]
        );
        
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

    // from user
    #[aztec(private)]
    fn claim_token_in(round: Field, total_token_in:Field, total_token_out: Field) {

        // get msg_sender's note
        let mut deposit_note = storage.deposit_notes.at(context.msg_sender()).get_note(false);

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_validate_claim_params(Field[])"), 
            [deposit_note.round, total_token_in, total_token_out]
        ); 

        // calculate total token_in purchased at a specificed round
        let token_in_amount = (total_token_in * deposit_note.amount_out / total_token_out);

        // individual users can execute private transfer from this address to them with no permission..?
        let _callStackItem = context.call_private_function(
            storage.token_out.read_private(),
            FunctionSelector::from_signature("transfer((Field),(Field),Field,Field)"),
            [context.this_address().to_field(), context.msg_sender().to_field(), token_in_amount, 0]
        );

        // TODO: note should be destroyed
    }

    /************************************************************************
     * Relayer's Public Operations
     ************************************************************************/

    // from relayer or amind controlled by L1 contract with timestamp checkers
    // minimum_output_amount should be calculated based on target twap
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

        let total_amount = ((plaintext_upper as u64 << 32) as u64 | plaintext_lower as u64) as Field;
        let amount_out_minus_cancelled = total_amount - token_out_amount_cancelled;

        // amount_out
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("validate_execute_batch((Field),Field,Field)"), 
            [
                context.msg_sender().to_field(),
                total_amount, 
                amount_out_minus_cancelled
            ]
        );

        // _approve_target_to_unshield
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

        // / 10x exchange rate for test
        let expected_token_in = amount_out_minus_cancelled * 10;

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

    // here probably there is need to implement create public auth wit
    // so that target contract can receive(transfer) token from this cotnract.
    #[aztec(private)]
    fn spend_private_authwit(inner_hash: Field) -> Field {
        let message_hash = compute_outer_authwit_hash(
            context.msg_sender(),
            context.chain_id(),
            context.version(),
            inner_hash
        );
        
        let auth_action = storage.auth_actions.at(message_hash).get_note(false);
        
        if (auth_action.approved) {
            context.push_new_nullifier(message_hash, 0);
            IS_VALID_SELECTOR
        } else {
            0
        }
    }

    // TODO: this func can have conditions to be executed 
    // 1: total deposit count: how many deposits are made so far
    // 2: time: how long did it take since last batch execute
    #[aztec(public)]
    #[aztec(internal)]
    fn validate_execute_batch(
        sender: AztecAddress, 
        amount_out:Field,
        amount_out_sub_cancelled:Field
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
        // assert(
        //     (round.encrypted_token_out_amount[0] == c1)
        //     & (round.encrypted_token_out_amount[1] == c2), 
        //     "invalid encrypted amount"
        // );

        round.token_out_amount = amount_out_sub_cancelled;
        round.executed = true;
        storage.rounds.at(current_round).write(round);
    }

    // here anyone can update the acquired eth reward of the latest round after eth purchase
    // but this should only occur once each round, so...
    #[aztec(public)]
    fn finalize_execute(
        secret_hash_for_redeeming_minted_notes: Field, // secret hash used to redeem minted notes at a later time. This enables anyone to call this function and mint tokens to a user on their behalf
        amount: Field,
        secret_for_L1_to_L2_message_consumption: Field 
    ) {
       // TODO: assert caller == relayer
       // TODO: how to query amount...? instead of relayer reporting it
       //       a way is to query balance in both execute_batch and this func
       //       while suspend claim between these two actions
       // or claim just can be done by the first claimer
       // by storing the secret somewhere...?
       // wait then nah this is bad as this contract should be receipient

        let current_round = storage.current_round.read();
        let mut round = storage.rounds.at(current_round).read();
        assert(round.executed, "batch tx hasn't been executed");
        assert(round.token_in_amount == 0, "already claimed");

        // store the new balance 
        round.token_in_amount = amount;
        storage.rounds.at(current_round).write(round);
        

        // claim_private ( mint_private() )
        // redeem_shield()

        let new_round = storage.current_round.read() + 1;
        storage.current_round.write(new_round); 
    }

    /************************************************************************
     * Functions for Relayer Dispute
     ************************************************************************/

    #[aztec(private)]
    fn dipute_relayer(
        he_secret_key: Field, 
        new_sk_hash: Field, 
        new_he_pub_key:Field,
        new_he_secret_key: Field,
        new_relayer: AztecAddress,
        secret_hash: Field,
        nonce:Field
        ) {
        let sk_hash = dep::std::hash::pedersen_hash([he_secret_key]);

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("check_sk_hash(Field)"), // or (Field)[]
            [sk_hash]
        ); 

        // validate that new_sk_hash == hash(new_he_secret_key);
        let new_computed_sk_hash = dep::std::hash::pedersen_hash([new_he_secret_key]);
        assert(new_sk_hash == new_computed_sk_hash, "invalid_new_sk_hash");
        
        // TODO: Check new_he_secret_key corresponds to new_he_pub_key in bbj
        // https://github.com/jat9292/babyjubjub-utils/blob/f93b474f35a302543b9f703b00c4e0628b5b88a7/index.js#L87

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("replace_relayer_and_slash_stake(Field,Field,(Field),Field,Field)"),
            [new_sk_hash, new_he_pub_key, new_relayer.to_field(), secret_hash, nonce]
        ); 
    }

    #[aztec(public)]
    fn check_sk_hash(sk_hash: Field) {
        assert(sk_hash == storage.batch_relayer.read().sk_hash, "invalid sk_hash");
    }

    // replace_relayer_and_slash_stake
    // 1: replace current relayer with a new relayer
    // 2: slash bond token
    // 3: make a new stake deposit from a new layer
    #[aztec(public)]
    #[aztec(internal)]
    fn replace_relayer_and_slash_stake(sk_hash: Field, new_he_pub_key: AffinePoint, new_relayer:AztecAddress, secret_hash:Field, nonce:Field) {
        // replacement from slashed relayer to a new relayer ( disputer )
        let mut relayer = storage.batch_relayer.read();
        relayer.relayer = new_relayer;
        relayer.sk_hash = sk_hash;
        relayer.he_pub_key = new_he_pub_key;
        storage.batch_relayer.write(relayer);

        // slash by shielding staked asset to new relayer
        Token::at(relayer.bonding_token).shield(
            &mut context, 
            context.this_address(), 
            relayer.bonding_amount,
            secret_hash, 
            0
        );

        // new stake deposit from new relayer
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("stake((Field),(Field),Field,Field)"), 
            [new_relayer.to_field(), relayer.bonding_token.to_field(), relayer.bonding_amount, nonce],
            GasOpts::default()
        ).assert_empty();  
    }

    #[aztec(public)] 
    fn stake(relayer: AztecAddress, token:AztecAddress, amount:Field, nonce:Field) {
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

    /************************************************************************
     * Public Internal Function
     ************************************************************************/

    #[aztec(public)] 
    #[aztec(internal)]
    fn _validate_claim_params(
        _round: Field, 
        _total_token_in: Field,
        _total_token_out: Field
    ) {
        let round = storage.rounds.at(_round).read();
        assert(round.token_in_amount == _total_token_in, "invalid _total_token_in");
        assert(round.token_out_amount == _total_token_out, "invalid _total_token_in");
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _add_token_out_amount(
        C1_0_serialized: [Field;2], 
        C2_0_serialized: [Field;2],
        C1_1_serialized: [Field;2], 
        C2_1_serialized: [Field;2]
    ) {
        let current_round = storage.current_round.read();
        let mut round = storage.rounds.at(current_round).read();

        let encrypted_value_to_add_0 = ElgamalAffinePoints::new(
            AffinePoint::deserialize(C1_0_serialized),
            AffinePoint::deserialize(C2_0_serialized)
        );

        let encrypted_value_to_add_1 = ElgamalAffinePoints::new(
            AffinePoint::deserialize(C1_1_serialized),
            AffinePoint::deserialize(C2_1_serialized)
        );

        let current_encrypted_sum = round.encrypted_token_out_amount;
        let new_encrypted_sum_0 = current_encrypted_sum.limb0.add(encrypted_value_to_add_0);
        let new_encrypted_sum_1 = current_encrypted_sum.limb1.add(encrypted_value_to_add_1);

        round.encrypted_token_out_amount.limb0 = new_encrypted_sum_0;
        round.encrypted_token_out_amount.limb1 = new_encrypted_sum_1;

        storage.rounds.at(current_round).write(round);
    }


    // #[aztec(public)]
    // #[aztec(internal)]
    // fn _add_token_out_amount(
    //     C1_serialized: [Field;2], 
    //     C2_serialized: [Field;2]
    // ) {
    //     let current_round = storage.current_round.read();
    //     let mut round = storage.rounds.at(current_round).read();

    //     let encrypted_value_to_add = ElgamalAffinePoints::new(
    //         AffinePoint::deserialize(C1_serialized),
    //         AffinePoint::deserialize(C2_serialized)
    //     );

    //     let current_encrypted_sum = round.encrypted_token_out_amount;
    //     let new_encrypted_sum = current_encrypted_sum.add(encrypted_value_to_add);

    //     round.encrypted_token_out_amount = new_encrypted_sum;
    //     storage.rounds.at(current_round).write(round);
    // }

    /// "decrease" (increase) `token_out_amount_cancelled` in rounds
    #[aztec(public)]
    #[aztec(internal)]
    fn _sub_token_out_amount(amount: Field, _round: Field) {
        let mut round = storage.rounds.at(_round).read();
        round.token_out_amount_cancelled = amount;
        storage.rounds.at(_round).write(round);
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _validate_round(round:Field) {
        let current_round = storage.current_round.read();
        assert(current_round == round, "invalid_round");
    }

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

    // let encrypted_sum = [
    //   21472650984436762244031229619925647112984218173381824458470819684039379547949,
    //   1837783691375768657483026041108174498631463823080692472709918501662216277768,
    //   11690546517140707588397632225831069958620412414394622994423967885413670819429,
    //   21302984366707003236483210776302960827497755078834244388811810345577369656375,
    //   13058325584767053170800789778067689450276426775479771755984487613995695696571,
    //   4975052509571564062789505510404194221861562293797938993591427913567106498933,
    //   2873706985540263354861265913926170740549681333793565646869733174154165291296,
    //   9501958688898625059030708999438742894669694486443633382776986148168316164379
    // ];
