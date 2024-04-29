use dep::noir_elgamal::elgamal::standard_fe;

// global gen: Field = 10944121435919637611123202872628637544274182200208017171849102093287991052496;
global gen: Field = 1094412143;

    fn encrypt(
        amount: Field,
        pub_key: Field,
        rand: Field
    ) -> (Field, Field) {

        let (c1, c2) = standard_fe::single_standard_encryption_fe(
            gen, 
            pub_key, 
            amount,
            rand
        );

        (c1, c2)
    }

    fn add(
        c1_1: Field, 
        c2_1: Field,
        c1_2: Field, 
        c2_2: Field) -> (Field, Field) 
    {
        if ((c1_1 == 0) & (c2_1 == 0)) {
            (c1_2, c2_2)
        } else {
            (c1_1*c1_2, c2_1*c2_2)
        }
    }

    fn decrypt(
        c1: Field,
        c2: Field,
        x: Field
    ) -> Field {
        standard_fe::single_decryption_fe(c1, c2, x)
    }

    fn validate_keypair(
        he_pub_key:Field, 
        he_secret_key:Field
    ) -> pub bool {
        let computed_pubkey = gen.pow_32(he_secret_key);
        // dep::std::println(computed_pubkey);
        let ret = computed_pubkey.eq(he_pub_key);
        ret
    }


    #[test]
    fn test_validate_keypair() {
        let pubkey = 3061722711224745108837506421211829939949377330929128360282042230364241268412;
        let sk = 7115637666404682632379307215493662218327241124760828634863089038725962038957;
        let ret = validate_keypair(pubkey, sk);
        dep::std::println(ret);
    }