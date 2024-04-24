mod value;
mod ciphertext;
mod bn254;

// test
fn main() {
  let num = 123438193746384423189281948629391;
  let value = value::Value::new(num);

  let rand = 3917818729331892189;

  let ciphertext = value.encrypt(rand);

  println(ciphertext.c0);
  println(ciphertext.c1);
  println(ciphertext.c2);
  println(ciphertext.c3);

  /*
  [he] Running 1 test function..
  CiphertextLimb { 
    c1: 0x27eba9b542de93e0457a73e25ecef2cb0c9b019d280418de67f4616ba4fd6df4, 
    c2: 0x1bfe5723820e7d7ea357138d33918b5b24b90d23637388b8d158bc217f4c44d2 
  }
  CiphertextLimb { 
    c1: 0x27eba9b542de93e0457a73e25ecef2cb0c9b019d280418de67f4616ba4fd6df4, 
    c2: 0x1235a6d819ece414db0a130162d1747b7bcf630f985a906eba0d122c1e9e4e43
  }
  CiphertextLimb { 
    c1: 0x27eba9b542de93e0457a73e25ecef2cb0c9b019d280418de67f4616ba4fd6df4, 
    c2: 0x0926c6af4b2232f448f56f6a6a57deedda558e5bfbb2b751a93af4c729747c0c 
  }
  CiphertextLimb { 
    c1: 0x27eba9b542de93e0457a73e25ecef2cb0c9b019d280418de67f4616ba4fd6df4, 
    c2: 0x0c86003e5bc1c05f784da7635c67a02abf2c151ec71f72501144a4a65d67ad93
  }
  [he] Testing test_main... ok
  */
 
}

#[test]
fn test_main() {
    main();
}