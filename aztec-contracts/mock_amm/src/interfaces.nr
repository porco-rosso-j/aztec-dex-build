// docs:start:interfaces
use dep::aztec::prelude::{FunctionSelector, AztecAddress, EthAddress, PrivateContext};
use dep::aztec::context::{PublicContext, gas::GasOpts};

struct Token {
  address: AztecAddress,
}

impl Token {
    pub fn at(address: AztecAddress) -> Self {
        Self { address }
    }

    pub fn transfer_public(
        self: Self,
        context: &mut PublicContext,
        from: AztecAddress,
        to: AztecAddress,
        amount: Field,
        nonce: Field
    ) {
        context.call_public_function(
            self.address,
            FunctionSelector::from_signature("transfer_public((Field),(Field),Field,Field)"),
            [from.to_field(), to.to_field(), amount, nonce],
            GasOpts::default()
        ).assert_empty();
    }

    pub fn shield(
        self: Self,
        context: &mut PrivateContext,
        from: AztecAddress,
        amount: Field,
        secret_hash: Field,
        nonce: Field
    ) {
        context.call_public_function(
            self.address,
            FunctionSelector::from_signature("shield((Field),Field,Field,Field)"),
            [from.to_field(), amount, secret_hash, nonce]
        );
    }
    
    pub fn unshield(
        self: Self,
        context: &mut PrivateContext,
        from: AztecAddress,
        to: AztecAddress,
        amount: Field,
        nonce: Field
    ) {
        let _ = context.call_private_function(
            self.address,
            FunctionSelector::from_signature("unshield((Field),(Field),Field,Field)"),
            [from.to_field(), to.to_field(), amount, nonce]
        );
    }

    pub fn transfer(
        self: Self,
        context: &mut PrivateContext,
        from: AztecAddress,
        to: AztecAddress,
        amount: Field,
        nonce: Field
    ) {
        let _ret = context.call_private_function(
            self.address,
            FunctionSelector::from_signature("transfer((Field),(Field),Field,Field)"),
            [from.to_field(), to.to_field(), amount, nonce]
        );
    }

    // pub fn balance_of_public(
    //     self: Self,
    //     context: &mut PublicContext,
    //     owner: AztecAddress
    // ) -> Field {
    //     let _ret = context.call_public_function(
    //         self.address,
    //         FunctionSelector::from_signature("balance_of_public((Field))"),
    //         [owner.to_field()],
    //          GasOpts::default()
    //     );
    //     _ret[0]
    // }
}
