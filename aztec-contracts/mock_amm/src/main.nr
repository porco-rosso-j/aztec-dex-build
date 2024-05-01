mod interfaces;

// aztec-cli codegen ./target/ -o ../../test/artifacts --ts

contract AMMMock {
    use dep::aztec::prelude::{
        AztecAddress, EthAddress, FunctionSelector, NoteHeader, NoteGetterOptions, NoteViewerOptions,
        Map, PublicMutable, PublicImmutable, PrivateMutable, SharedImmutable
    };
    use dep::aztec::{note::note_getter_options::Comparator, 
        context::{Context, PrivateContext, PublicContext, gas::GasOpts}
    };
    use crate::interfaces::Token;

    #[aztec(storage)]
    struct Storage {
        admin: PublicImmutable<AztecAddress>, 
        token0: SharedImmutable<AztecAddress>,
        token1: SharedImmutable<AztecAddress>
    }

    impl Storage {
      fn init(context: Context) -> Self {
        Storage {
            admin: PublicImmutable::new(context, 1), 
            token0: SharedImmutable::new(context, 2), // eth
            token1: SharedImmutable::new(context, 3), // dai
        }
      }
    }

    #[aztec(private)]
    #[aztec(initializer)]
    fn constructor(admin: AztecAddress, token0: AztecAddress, token1: AztecAddress) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_initialize((Field),(Field),(Field))"),
            [admin.to_field(), token0.to_field(), token1.to_field()]
        );
    }

    #[aztec(public)]
    #[aztec(internal)]
    #[aztec(noinitcheck)]
    fn _initialize(
        admin: AztecAddress, 
        token0: AztecAddress, 
        token1: AztecAddress
    ) {
        storage.admin.initialize(admin);
        storage.token0.initialize(token0);
        storage.token1.initialize(token1);
    }

    //  #[aztec(private)]
    //  fn add_liquidity(token0: AztecAddress, amount: Field) {
    //     assert(token0 == storage.token0.read_private(), "invalid token0");
    //     Token::at(token0).unshield(&mut context, context.msg_sender(), context.this_address(), amount, 0);
    //  }
     #[aztec(public)]
     fn add_liquidity(token0: AztecAddress, amount: Field, nonce: Field) {
        assert(token0 == storage.token0.read_public(), "invalid token0");
        Token::at(token0).transfer_public(&mut context, context.msg_sender(), context.this_address(), amount, nonce);
     }

     // mock public swap call
     // only works for swapping token1(dai) for token0(eth)
     // exchange rate is decided by caller
     #[aztec(public)]
     fn swap_public(
        amount0: Field, // eth out
        amount1: Field, // dai in 
        nonce0: Field,
        nonce1: Field
    )  {
        let token0 = storage.token0.read_public();
        let token1 = storage.token1.read_public();

        // transfer eth out 
        Token::at(token0).transfer_public(
            &mut context, 
            context.this_address(), 
            context.msg_sender(), 
            amount0, 
            nonce0
        );

        // transfer dai in
        Token::at(token1).transfer_public(
            &mut context, 
            context.msg_sender(), 
            context.this_address(), 
            amount1, 
            nonce1
        );

    }

     // mock private swap call
     // only works for swapping token1(dai) for token0(eth)
     // exchange rate is decided by caller
     #[aztec(private)]
     fn swap_private(
        amount0: Field, // eth out
        amount1: Field, // dai in 
        nonce0: Field,
        nonce1: Field,
        secret_hash: Field
    )  {
        let token0 = storage.token0.read_private();
        let token1 = storage.token1.read_private();

        // optimistically transfer(shield) eth out to batcher pub -> pri
        Token::at(token0).shield(
            &mut context, 
            context.this_address(), 
            amount0, 
            secret_hash,
            nonce0
        );

        // transfer(unshield) dai from batcher pri -> pub
        Token::at(token1).unshield(
            &mut context, 
            context.msg_sender(), 
            context.this_address(), 
            amount1, 
            nonce1
        );
    }

    unconstrained fn get_admin() -> pub Field {
        storage.admin.read().to_field()
    }

    unconstrained fn get_token0() -> pub Field {
        storage.token0.read_public().to_field()
    }

    unconstrained fn get_token1() -> pub Field {
        storage.token1.read_public().to_field()
    }

}