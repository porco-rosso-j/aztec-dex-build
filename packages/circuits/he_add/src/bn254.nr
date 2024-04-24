use dep::std::bigint::{Bn254Fr, bn254_fr};
use dep::std::println;
use dep::std::field;

    fn field_to_bn254fr(x:Field) -> Bn254Fr {
        let bytes = x.to_le_bytes(32);
        let big_int = Bn254Fr::from_le_bytes(bytes);
        println(big_int);
        big_int
    }


    fn bn254fr_to_field(x:Bn254Fr) -> Field {
        let ret = x.to_le_bytes();
        let bytes_u8_32_ret = u8_to_u8_32(ret);
        let field_ret = bytes32_to_field(bytes_u8_32_ret);
        field_ret
    }

    fn u8_to_u8_32(arr: [u8]) -> [u8; 32] {
       let mut as_field: [u8; 32] = [0 as u8; 32];
       for i in 0..32 {
          as_field[i] = arr[i];
       }
       as_field
    }

    fn bytes32_to_field(bytes32: [u8; 32]) -> Field {
      let mut v = 1;
      let mut ret = 0 as Field;

      for i in 0..32 {
         ret = ret + (bytes32[i] as Field) * v;
         v = v * 256;
         // println(ret);
      }

      ret
    }
