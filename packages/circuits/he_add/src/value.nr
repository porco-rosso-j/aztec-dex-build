
use crate::ciphertext::{Ciphertext, CiphertextLimb};
use dep::noir_elgamal::elgamal::standard_fe;
use dep::std::uint128::{U128};


global gen: Field = 3618502788666131106986593281521497120414687020801267626233049500247285301248;
global g_pub_key: Field = 16584962576839748938045029104466123591912653899946104485344065692808256697355;


struct Value {
    value: U128
}

impl Value {

    fn new(_value: Field) -> Value {
        Value { value: U128::from_integer(_value) }
    }

    fn to_limbs(self) -> [ValueLimb; 4] {
        let value: Field = self.value.to_integer();
        dep::std::println(value);
        let v = value as u64;
        // let v = self.value.to_field() as u64;
        [
            ValueLimb::to_limb((v & 0xffff) as u32),
            ValueLimb::to_limb(((v >> 16) & 0xffff) as u32),
            ValueLimb::to_limb(((v >> 32) & 0xffff) as u32),
            ValueLimb::to_limb(((v >> 48) & 0xffff) as u32),
        ]
    }

    // fn from_limbs(
    //     x0: limb::Value,
    //     x1: limb::Value,
    //     x2: limb::Value,
    //     x3: limb::Value,
    // ) -> Self {
    //     let x0 = x0.0 as u128;
    //     let x1 = x1.0 as u128;
    //     let x2 = x2.0 as u128;
    //     let x3 = x3.0 as u128;
    //     Value(x0 + (x1 << 16) + (x2 << 32) + (x3 << 48))
    // }

    fn encrypt(
        self,
        rand: Field
    ) -> Ciphertext {

        let empty = CiphertextLimb::empty();
        let mut encrypted_limbs: [CiphertextLimb;4] = [empty;4];

        let limbs = self.to_limbs();

        for i in 0..4 {
            encrypted_limbs[i] = limbs[i].encrypt(rand);
        }

        let ciphertext = Ciphertext {
            c0: encrypted_limbs[0],
            c1: encrypted_limbs[1],
            c2: encrypted_limbs[2],
            c3: encrypted_limbs[3],
        };

        ciphertext
    }

}


struct ValueLimb {
    value: u32
}

impl ValueLimb {

    fn to_limb(_value: u32) -> ValueLimb {
        ValueLimb { value: _value }
    }

    fn empty() -> ValueLimb {
        ValueLimb { value: 0 as u32}
    }

    fn encrypt(
        self,
        rand: Field
    ) -> CiphertextLimb {

        let (c1, c2) = standard_fe::single_standard_encryption_fe(
            gen, 
            g_pub_key, 
            self.value as Field,
            rand
        );

        let ciphertext = CiphertextLimb {
            c1: c1,
            c2: c2,
        };

        ciphertext
    }
}
