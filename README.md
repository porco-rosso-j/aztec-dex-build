# Batcher Contract on Aztec

The `BatcherVault` contract allow users to obfuscate their swap amounts when they trade on AMMs. It leverages additive homomorphic encryption scheme to encrypt and aggregate users' input amount without revealing individual amount. The encrypted total amount is decrypted by a relayer who executes batched swap.

This vault doesn't only help conceal the users's input amount but also hide sender address and output amount throughout the deposit and claim processes. This is because token transfer in both deposit and claim is performed privately without revealing `msg_sender`. Only visible information is "when" each deposit is made, as each deposit execution invokes public methods internally.

Note the current implementation only make input amounts invisible from the entire world but the party who decrypts the encrypted deposit. Details and solutions to this problem are discribed below.

## Technologies & Credits

- [`noir-elgamal`](https://github.com/jat9292/noir-elgamal) by Jat & Josh: A noir libraryfor Exponential ElGamal Encryption on the Baby Jubjub curve. This is the core component of this project used to handle homomorphic encryption, addition and decryption to users' deposit.

- [`babyjubjub-utils`](https://github.com/jat9292/babyjubjub-utils) by Jat: Node package implementing utility functions for interacting with the Baby Jubjub curve and the `noir-elgama`l` Noir package. This package is used in our ts test to perform the baby-giant-step algorithm for the full decryption of deposit amount.

- [`aztec-patterns`](https://github.com/defi-wonderland/aztec-patterns) by DeFi Wonderland: Types such are `ElgamalAffinePoints` and `AffinePoint` found in [`add-homomorphic`](https://github.com/defi-wonderland/aztec-patterns/tree/dev/patterns/add-homomorphic) project that integrates `noir-elgamal` are also used in the batcher vault contract.

## Limitations & Solutions

### 1. Amount Visibility to relayer

The Relayer, also called a decryptor, who owns decryption key, effctively can know all the individual deposit amount if they look at encrypted data at each deposit tx. Furemore, they have constant incentives to sell the decryption key to a highest bidder who is willing to pay money to monitor users' input amount.

To mitigate this risk, this batcher vault implements a stake & slash-based dispute mechanism that could discourage relayers from selling their decryption key as well as encouraging them to keep it secure.

A relayer needs to stake a certain amount of token to the contract at deployemnt. And this stake is slashed and sent to the party who prove that they know the decryption key. For instance, if an entity who disguises as a bidder successfully obtains the key, he can take the relayer's stake, optionally taking over the relayer role.

Another approach that is more preferable but challenging is to implement a threshold decryption scheme like Penumbra does. It generates, split, and distribute the decryption key to multiple parties through DKG procedure, allowing for decryption without nobody knowing the entire key.

Theoretically, it seems quite feasible to implement such a scheme for this batcher vault by having [a Penumbra-like threshold decryption logic](https://github.com/penumbra-zone/penumbra/tree/main/crates/crypto/eddy) in Noir with baby-jub-jub-based [FROAST](https://github.com/ZcashFoundation/frost) as the key generation algorithm.

This could be our future improvement task and the primary reason why we decided to build this feature with elgamal homomorphic addition instead of a note sharing scheme where individual input amount must be revealed to a relayer.

### 2. Upper limit to input amount

This batcher vault supports up to `u64` value for the plaintext (deposit amount) while the `noir-elgamal` lib only supports [up to `u40`](https://github.com/jat9292/noir-elgamal/blob/main/src/lib.nr#L81). This is made possible by splitting `u64` input value via bit shift and encrypting two separate `u32`. This limit can be increased to `u128` or more but this obviously entails more storage and execution cost and longer decryption time.

### 3. Delay

To offer meaningful degree of privacy, the relayer is expected to batches several swap requests instead of one or a few. Hence, users may need to wait for a few blocks until their swap is completed. This PoC only let relayer execute the batch only once a minute as `interval` in `BatchRelayer` struct is set to `86400`.
