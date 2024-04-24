

struct Ciphertext {
    c0: CiphertextLimb,
    c1: CiphertextLimb,
    c2: CiphertextLimb,
    c3: CiphertextLimb,
}

impl Ciphertext {
    fn new(
        _c0: [Field;2], 
        _c1: [Field;2], 
        _c2: [Field;2], 
        _c3: [Field;2]
    ) -> Self {
        Ciphertext {
            c0: CiphertextLimb { c1: _c0[0], c2: _c0[1] },
            c1: CiphertextLimb { c1: _c1[0], c2: _c1[1] },
            c2: CiphertextLimb { c1: _c2[0], c2: _c2[1] },
            c3: CiphertextLimb { c1: _c3[0], c2: _c3[1] },
        }
    }

    // for aggreagtion
    fn add(self, rhs: Ciphertext) -> Self {
        Ciphertext {
            c0: self.c0.add(rhs.c0),
            c1: self.c1.add(rhs.c1),
            c2: self.c2.add(rhs.c2),
            c3: self.c3.add(rhs.c3),
        }
    }

    // decrypt()
}

struct CiphertextLimb {
    c1: Field,
    c2: Field,
}

impl CiphertextLimb {
    fn new(_c1: Field, _c2:Field) -> Self {
        CiphertextLimb {
            c1: _c1,
            c2: _c2
        }
    }

    fn empty() -> Self {
        CiphertextLimb {
            c1: 0,
            c2: 0
        }  
    }

    fn add(self, rhs: CiphertextLimb) -> Self {
       CiphertextLimb {
          c1: self.c1 + rhs.c1,
          c2: self.c2 + rhs.c2,
       }
    }

     // decrypt()
}


// impl Add for CiphertextLimb { 
//     fn add(self: Self, other: Secpk1Fq) -> Secpk1Fq {
//         let a = BigInt::from_le_bytes(self.array.as_slice(), secpk1_fq);
//         let b = BigInt::from_le_bytes(other.array.as_slice(), secpk1_fq);
//         Secpk1Fq {
//            array: a.bigint_add(b).to_le_bytes()
//         }
//     }
// }