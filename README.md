# Batcher Contract on Aztec

The `BatcherVault` contract allows users to obfuscate their swap amounts when they trade on AMMs. It leverages an additive homomorphic encryption scheme to encrypt and aggregate users' input amounts without revealing individual amounts. The encrypted total amount is decrypted by a relayer who executes a batched swap. Later, users can claim their share of the output amount calculated based on their pro-rata share of the input amount for each batch round.

This vault doesn't only help conceal the users' input amount but also hide the sender address and output amount throughout the deposit and claim processes. Token transfer in both deposits and claims is performed privately without revealing `msg_sender`. The only visible information is "when" each deposit is made, as each deposit execution invokes public methods internally.

Note that the current implementation only makes input amounts invisible from the entire world but the party who decrypts the encrypted deposit. Details and solutions to this problem are described below.

## Technologies & Credits

- [`noir-elgamal`](https://github.com/jat9292/noir-elgamal) by Jat & Josh: A noir library for Exponential ElGamal Encryption on the Baby Jubjub curve. This is the core component of this project, which is used to handle homomorphic encryption, addition, and decryption of users' deposits.

- [`babyjubjub-utils`](https://github.com/jat9292/babyjubjub-utils) by Jat: Node package implementing utility functions for interacting with the Baby Jubjub curve and the `noir-elgama`l` Noir package. This package is used in our ts test to perform the baby-giant-step algorithm for the full decryption of the deposit amount.

- [`aztec-patterns`](https://github.com/defi-wonderland/aztec-patterns) by DeFi Wonderland: Types such are `ElgamalAffinePoints` and `AffinePoint` found in [`add-homomorphic`](https://github.com/defi-wonderland/aztec-patterns/tree/dev/patterns/add-homomorphic) project that integrates `noir-elgamal` are also used in the batcher vault contract.

## Limitations & Solutions

### 1. Amount Visibility to Relayer

The Relayer, also called a decryptor, who owns the decryption key effectively can know all the individual deposit amounts if they look at encrypted data at each deposit tx. Furthermore, they have constant incentives to sell the decryption key to the highest bidder who is willing to pay money to monitor users' input amounts.

To mitigate this risk, this batcher vault implements a stake-and-slash-based dispute mechanism that could discourage relayers from selling their decryption key as well as encourage them to keep it secure.

A relayer needs to stake a bonding token to the contract at deployment. This stake is slashed and sent to the party who proves that he knows the decryption key. For instance, if an entity disguised as a bidder successfully obtains the key, he can take the relayer's stake and optionally take over the relayer's role.

Another approach that is more preferable but challenging is to implement a threshold decryption scheme like Penumbra's. It generates, splits, and distributes the decryption key to multiple parties through the DKG procedure, allowing for decryption without nobody knowing the entire key.

Theoretically, it seems quite feasible to implement such a scheme for this batcher vault by having [a Penumbra-like threshold decryption logic](https://github.com/penumbra-zone/penumbra/tree/main/crates/crypto/eddy) in Noir with baby-jub-jub-based [Frost](https://github.com/ZcashFoundation/frost) as the key generation algorithm.

This could be our future improvement task and the primary reason why we decided to build this feature with the Elgamal homomorphic addition instead of a note-sharing scheme in which individual input amounts can also be hidden from the external world but the relayer.

### 2. The Upper Limit of Input Amount

This batcher vault supports up to `u64` value for the plaintext (deposit amount) while the `noir-elgamal` lib only supports [up to `u40`](https://github.com/jat9292/noir-elgamal/blob/main/src/lib.nr#L81). This is made possible by splitting `u64` input value via bit shift and encrypting two separate `u32`. This limit can be increased to `u128` or more but this obviously entails more storage and execution cost and longer decryption time.

### 3. Delay

To offer a meaningful degree of privacy, the relayer is expected to batch several swap requests instead of one or a few. Hence, users may need to wait for a few blocks until their swap is completed. This PoC only lets the relayer execute the batch only once a minute as `interval` in `BatchRelayer` struct is set to `86400`.

## Feedback

plz see [here](./FEEDBACK.md)
