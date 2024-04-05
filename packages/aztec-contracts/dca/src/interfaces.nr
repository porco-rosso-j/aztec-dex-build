// docs:start:interfaces
use dep::aztec::prelude::{FunctionSelector, AztecAddress, EthAddress, PrivateContext};
use dep::aztec::context::PublicContext;

struct Token {
  address: AztecAddress,
}

impl Token {
    pub fn at(address: AztecAddress) -> Self {
        Self { address }
    }

    pub fn shield(
        self: Self,
        context: &mut PrivateContext,
        from: AztecAddress,
        amount: Field,
        secret_hash: Field,
        nonce: Field
    ) {
        let _ = context.call_public_function(
            self.address,
            FunctionSelector::from_signature("shield((Field),Field,Field,Field)"),
            [from.to_field(), amount, secret_hash, nonce]
        );
    }


    pub fn transfer_public(
        self: Self,
        context: &mut PublicContext,
        from: AztecAddress,
        to: AztecAddress,
        amount: Field,
        nonce: Field
    ) {
        let _ = context.call_public_function(
            self.address,
            FunctionSelector::from_signature("transfer_public((Field),(Field),Field,Field)"),
            [from.to_field(), to.to_field(), amount, nonce]
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

    pub fn balance_of_public(
        self: Self,
        context: &mut PublicContext,
        owner: AztecAddress
    ) -> Field {
        let _ret = context.call_public_function(
            self.address,
            FunctionSelector::from_signature("balance_of_public((Field))"),
            [owner.to_field()]
        );
        _ret[0]
    }
}

struct Uniswap {
  address: AztecAddress,
}

impl Uniswap {
    pub fn at(address: AztecAddress) -> Self {
        Self { address }
    }

    pub fn swap_public(
        self: Self,
         context: &mut PublicContext,
        sender: AztecAddress,
        input_asset_bridge: AztecAddress,
        input_amount: Field,
        output_asset_bridge: AztecAddress,
        nonce_for_transfer_approval: Field,
        uniswap_fee_tier: Field,
        minimum_output_amount: Field,
        recipient: AztecAddress,
        secret_hash_for_L1_to_l2_message: Field,
        caller_on_L1: EthAddress,
        nonce_for_swap_approval: Field
    ) {
        let _ = context.call_public_function(
            self.address,
            FunctionSelector::from_signature("swap_public((Field),(Field),Field,(Field),Field,Field,Field,(Field),Field,(Field),Field)"),
            [
                sender.to_field(), 
                input_asset_bridge.to_field(), 
                input_amount, 
                output_asset_bridge.to_field(), 
                nonce_for_transfer_approval,
                uniswap_fee_tier,
                minimum_output_amount,
                recipient.to_field(),
                secret_hash_for_L1_to_l2_message,
                caller_on_L1.to_field(),
                nonce_for_swap_approval
            ]
        );
    }
}
// docs:end:interfaces
