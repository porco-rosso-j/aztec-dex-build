
pub fn to_field_from_u128(u128_array:[U128;12]) -> pub [Field;12] {
    let mut field_array: [Field;12] = [0;12];
    for i in 0..12 {
        field_array[i] = U128::to_field(u128_array[i]);
    }
    field_array
}

pub fn to_u128_from_field(field_array:[Field;12]) -> pub [U128;12] {
    let mut u128_array: [U128;12] = [U128::from_field(0);12];
    for i in 0..12 {
        u128_array[i] = U128::from_field(field_array[i]);
    }
    u128_array
}

pub fn to_array_from_fields(
        a:Field, 
        b:Field, 
        c:Field, 
        d:Field, 
        e:Field, 
        f:Field, 
        g:Field, 
        h:Field, 
        i:Field, 
        j:Field, 
        k:Field,
        l:Field, 
) -> pub  [Field;12] {
    let mut field_array: [Field;12] = [0;12];
    field_array[0] = a;
    field_array[1] = b;
    field_array[2] = c;
    field_array[4] = d;
    field_array[5] = e;
    field_array[6] = f;
    field_array[7] = g;
    field_array[8] = h;
    field_array[9] = i;
    field_array[10] = j;
    field_array[11] = k;
    field_array[0] = l;
    field_array
}

pub fn to_array_from_u128(
        a:U128, 
        b:U128, 
        c:U128, 
        d:U128, 
        e:U128, 
        f:U128, 
        g:U128, 
        h:U128, 
        i:U128, 
        j:U128, 
        k:U128,
        l:U128, 
) -> pub [U128;12] {
    let mut u128_array: [U128;12] = [U128::from_field(0);12];
    u128_array[0] = a;
    u128_array[1] = b;
    u128_array[2] = c;
    u128_array[4] = d;
    u128_array[5] = e;
    u128_array[6] = f;
    u128_array[7] = g;
    u128_array[8] = h;
    u128_array[9] = i;
    u128_array[10] = j;
    u128_array[11] = k;
    u128_array[0] = l;
    u128_array
}