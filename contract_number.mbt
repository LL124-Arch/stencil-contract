///|
// Decimal tokens, rather than rounded Double values, decide JSON assertions.
// A bounded token/exponent prevents user-supplied numbers from allocating
// unbounded powers of ten. None is a visible validation/import failure.
fn contract_number_parts(value : Json) -> (BigInt, Int)? {
  let text = match value {
    Number(number, repr~) => repr.unwrap_or(number.to_string())
    _ => return None
  }
  if text.length() == 0 || text.length() > 4096 {
    return None
  }
  let chars = text.to_array()
  let mut i = 0
  let negative = chars[0] == '-'
  if negative {
    i += 1
  }
  if i >= chars.length() {
    return None
  }
  let digits = StringBuilder()
  if chars[i] == '0' {
    digits.write_char('0')
    i += 1
  } else {
    if chars[i] < '1' || chars[i] > '9' {
      return None
    }
    for ;; {
      if i >= chars.length() || chars[i] < '0' || chars[i] > '9' {
        break
      }
      digits.write_char(chars[i])
      i += 1
    }
  }
  let mut fraction = 0
  if i < chars.length() && chars[i] == '.' {
    i += 1
    let start = i
    for ;; {
      if i >= chars.length() || chars[i] < '0' || chars[i] > '9' {
        break
      }
      digits.write_char(chars[i])
      fraction += 1
      i += 1
    }
    if i == start {
      return None
    }
  }
  let mut exponent = 0
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    let mut minus = false
    if i < chars.length() && (chars[i] == '+' || chars[i] == '-') {
      minus = chars[i] == '-'
      i += 1
    }
    let start = i
    for ;; {
      if i >= chars.length() || chars[i] < '0' || chars[i] > '9' {
        break
      }
      exponent = exponent * 10 + chars[i].to_int() - '0'.to_int()
      if exponent > 4096 {
        return None
      }
      i += 1
    }
    if i == start {
      return None
    }
    if minus {
      exponent = -exponent
    }
  }
  if i != chars.length() {
    return None
  }
  let coefficient = @bigint.BigInt::from_string(digits.to_string())
  Some((if negative { -coefficient } else { coefficient }, fraction - exponent))
}

///|
fn contract_bigint_power_of_ten(power : Int) -> BigInt {
  let mut result = @bigint.BigInt::from_int(1)
  let ten = @bigint.BigInt::from_int(10)
  for _ in 0..<power {
    result = result * ten
  }
  result
}

///|
fn contract_number_compare(left : Json, right : Json) -> Int? {
  match (contract_number_parts(left), contract_number_parts(right)) {
    (Some((a, sa)), Some((b, sb))) => {
      let scale = if sa > sb { sa } else { sb }
      let a = a * contract_bigint_power_of_ten(scale - sa)
      let b = b * contract_bigint_power_of_ten(scale - sb)
      Some(if a < b { -1 } else if a > b { 1 } else { 0 })
    }
    _ => None
  }
}

///|
fn contract_number_is_integer(value : Json) -> Bool {
  match contract_number_parts(value) {
    Some((coefficient, scale)) =>
      scale <= 0 ||
      (coefficient % contract_bigint_power_of_ten(scale)).is_zero()
    None => false
  }
}

///|
fn contract_json_number_is_multiple(value : Json, divisor : Json) -> Bool {
  match (contract_number_parts(value), contract_number_parts(divisor)) {
    (Some((a, sa)), Some((b, sb))) if !b.is_zero() => {
      let scale = if sa > sb { sa } else { sb }
      let numerator = a * contract_bigint_power_of_ten(scale - sa)
      let denominator = b * contract_bigint_power_of_ten(scale - sb)
      (numerator % denominator).is_zero()
    }
    _ => false
  }
}

///|
fn contract_json_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Number(_, ..), Number(_, ..)) =>
      contract_number_compare(left, right) == Some(0)
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if !contract_json_equal(a[i], b[i]) {
          return false
        }
      }
      true
    }
    (Object(a), Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      for (key, value) in a {
        match b.get(key) {
          Some(other) if contract_json_equal(value, other) => ()
          _ => return false
        }
      }
      true
    }
    _ => Json::equal(left, right)
  }
}

///|
fn contract_json_numbers_supported(value : Json) -> Bool {
  match value {
    Number(_, ..) => contract_number_parts(value) is Some(_)
    Array(items) => {
      for item in items {
        if !contract_json_numbers_supported(item) {
          return false
        }
      }
      true
    }
    Object(members) => {
      for (_, item) in members {
        if !contract_json_numbers_supported(item) {
          return false
        }
      }
      true
    }
    _ => true
  }
}
