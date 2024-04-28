use dep::std;
/// ElGamal encryption/decryption for Field elements

// Given generator gen, public key pub_key, message m and randomness r
// Output ciphertext (c1,c2)
// c1 = gen^r
// c2 = m * pub_key^r
// TODO acording to function comment assumes exponent under 32 bits. 
// It seems to work for random test values, but probably perfomance isn't optimal. 
fn single_standard_encryption_fe(
  gen: Field, 
  pub_key: Field, 
  m: Field, 
  r: Field
  ) -> (Field, Field) {

  // let c1 = gen.pow_32(r);
  // let temp = pub_key.pow_32(r);
  // let c2 = m * temp;
  // let c1 = r.pow_32(gen);
  // let temp1 = r.pow_32(pub_key);
  // let temp2 = m.pow_32(gen) ;
  // let c2 = temp1 + temp2;

  //　single_hom_encryption_fe
  // let c1 = gen.pow_32(r);
   let c1 = gen * r;
  let temp1 = pub_key.pow_32(r);
  let temp2 = gen.pow_32(m) ;
  let c2 = temp2 * temp1;
  (c1, c2)
}

#[test]
fn testsingle_standard_encryption_fe() {
  let gen = 3618502788666131106986593281521497120414687020801267626233049500247285301248;
  let g_pub_key = 0x8601d0dec944deca8918a6431526acb8530afea2ffa295142b348dfbce36c20b;
  let m = 42830;
  let r = 1152000579019524719769048073517805207578464470827627862468450398349088064047;
  let (c1, c2) = single_standard_encryption_fe(gen, g_pub_key, m, r);
  std::println(c1);
  std::println(c2);

}

// TODO assumes exponent under 32 bits?
fn single_decryption_fe(
  c1: Field,
  c2: Field,
  x: Field
) -> Field {

  // The shared secret
  let s = c1.pow_32(x);
  let s_inv = 1/s;
  
  // Check in parigp
  // Mod(1/31250, 21888242871839275222246405745257275088548364400416034343698204186575808495617)
  // note that this assumes field is bn254
  
  // Check here - works
  // let test = s * s_inv;
  // std::println("test");
  // std::println(test);

  // recover and return m
  c2 * s_inv
}


#[test]
fn test_single_encryption_fe_1() {
  // small values

  // priv key
  let x = 2;
  let gen = 5;
  // pub_key = gen^x
  // assumes exponent fits in 32 bits
  // 25 = 0x19
  let pub_key = gen.pow_32(x);

  let msg = 11111;
  let randomness = 6;
  let (c1, c2) = single_standard_encryption_fe(gen, pub_key, msg, randomness);
  let m_decrypted =  single_decryption_fe(c1, c2, x);
  
  assert(msg == m_decrypted);
}

#[test]
fn test_single_encryption_fe_2() {
  // with generated values parigp
  // random(21888242871839275222246405745257275088548364400416034343698204186575808495617)

  // priv key
  let x = 7115637666404682632379307215493662218327241124760828634863089038725962038957;
  
  // gen = 0x183227397098d014dc2822db40c0ac2e9419f4243cdcb848a1f0fac9fd2c88d0
  let gen = 10944121435919637611123202872628637544274182200208017171849102093287991052496;
  
  // pub_key = gen^x
  let pub_key = gen.pow_32(x);
  std::println(pub_key); // 0x06c4dfa71f2a7a8810dc34ce86938764a51b6bf5bce71da90c1c5fc9407e0ebc

  let msg = 11111;
  // hex 25ea07206ae935e88e774161a280fc15ddd2cbc78d99d2123f3bd562956d466a
  let randomness = 17149066796940759370530693659488791163567038136671713582338765584448638240362;
  let (c1, c2) = single_standard_encryption_fe(gen, pub_key, msg, randomness);
  let m_decrypted =  single_decryption_fe(c1, c2, x);

  assert(msg == m_decrypted);
}