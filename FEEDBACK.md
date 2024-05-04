## Feedback

### 1. Built-in `spend_public/private_authwit` for every non-account contract (noir)

As the non-account contracts also sometimes need to approve another contract to take a specifc action on behalf, it'd be reasonable to add these funcs as built-in, so that developers don't need to implement it manually every time, though, if there is not much overhead. This is especially relevant for approvals in private context as it needs a note to store the hash of an approved action privately.

In my case, as described in [this question](https://discord.com/channels/1144692727120937080/1235201898542272582) of Aztec Dev Discord, I had to add `spend_private_authwit` method to `BatcherVault` contract and implement `AuthActionNote` so that it can approve AMM to `unshield()` a token from the batcher contract.

As you can see the following simple code, it's something that'd always have to be copy&pasted by developers. Like `fn compute_note_hash_and_nullifier()` was clearly redundant and removed, it'd ideal if these methods and notes were also abstracted for devs.

#### spend_private_authwit() method

```rust
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
```

#### AuthActionNote

```rust
    global AUTH_ACTION_NOTE_LEN: Field = 2;

    #[aztec(note)]
    struct AuthActionNote {
        approved: bool,
        owner: AztecAddress,
    }
```

### 2. Runtime error due to subtle typos in function signature (noir)

Noir compiler doesn't care the correctness of string signature for computing selector. Hence, just sutble typos lead to runtime error which is very annoying. It'd be great if Noir compiler does take it into account or there is some other ways to auto-check their correctness before running test.

e.g. this causes a runtime error!　(A lack of one right-most bracket)

```rust
let selector = FunctionSelector::from_signature("func((Field),(Field),(Field)")
```

### 3. `pow_32()` fails with large exponent at runtime (noir)

`pow_32()` function for Field fails at runtime, throwing an error `Cannot satisfy constraint 'self.__to_le_bits(bit_size)` even though it computes the correct value in the test.

### 4. Need to `deployWithPublicKey` manually (aztec.js)

Since the batcher vault contract needs to receive token from external contracts including accounts via `transfer()`, I had to register the contract by changing the deployment line from ordinal one to the one `deployWithPublicKey()`.

It'd be great if this was done by default, as I guess many devs stumble on this. Or it'd nice if its at least covered in the doc ( unless i miss it ) including the explanation about what is operator, what these keys are for, etc...

from:

```js
await BatcherVaultContract.deploy(
	admin_relayer, // deployer
	param...
)
	.send()
	.wait();
```

to:

```js
const privateKey = GrumpkinScalar.random();
const publicKey = generatePublicKey(privateKey);

const batcherContractDeployment = BatcherVaultContract.deployWithPublicKey(
	publicKey,
	params...
);

const batcherInstance = batcherContractDeployment.getInstance();
await pxe.registerAccount(privateKey, computePartialAddress(batcherInstance));
```

### 5. `publicDeployAccounts` by default (aztec.js)

As I see other developers face this, and I also had to manually add this func [here](./test/utils/deploy.ts) it'd be nice if this registration is done by default.
