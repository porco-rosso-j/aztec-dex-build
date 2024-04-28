use dep::noir_elgamal::elgamal::standard_fe;

global gen: Field = 3618502788666131106986593281521497120414687020801267626233049500247285301248;

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
        (c1_1*c1_2, c2_1*c2_2)
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
        let ret = he_secret_key.pow_32(gen) == he_pub_key;
        ret
    }