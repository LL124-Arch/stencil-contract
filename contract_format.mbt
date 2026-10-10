///|
fn contract_json_schema_format_is_supported(format : String) -> Bool {
  match format {
    "date" | "time" | "date-time" | "uuid" => true
    _ => false
  }
}

///|
fn contract_json_schema_format_matches(format : String, value : String) -> Bool {
  match format {
    "date" => contract_json_schema_date_matches(value.to_array())
    "time" => contract_json_schema_time_matches(value.to_array(), 0)
    "date-time" => contract_json_schema_date_time_matches(value.to_array())
    "uuid" => contract_json_schema_uuid_matches(value.to_array())
    _ => false
  }
}

///|
fn contract_json_schema_date_time_matches(chars : Array[Char]) -> Bool {
  if chars.length() < 11 || !contract_json_schema_date_matches_prefix(chars) {
    return false
  }
  if chars[10] != 'T' && chars[10] != 't' {
    return false
  }
  contract_json_schema_time_matches(chars, 11)
}

///|
fn contract_json_schema_date_matches(chars : Array[Char]) -> Bool {
  chars.length() == 10 && contract_json_schema_date_matches_prefix(chars)
}

///|
fn contract_json_schema_date_matches_prefix(chars : Array[Char]) -> Bool {
  if chars.length() < 10 || chars[4] != '-' || chars[7] != '-' {
    return false
  }
  match
    (
      contract_json_schema_parse_digits(chars, 0, 4),
      contract_json_schema_parse_digits(chars, 5, 7),
      contract_json_schema_parse_digits(chars, 8, 10),
    ) {
    (Some(year), Some(month), Some(day)) => {
      if month < 1 || month > 12 {
        return false
      }
      let days_in_month = match month {
        2 if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) => 29
        2 => 28
        4 | 6 | 9 | 11 => 30
        _ => 31
      }
      day >= 1 && day <= days_in_month
    }
    _ => false
  }
}

///|
fn contract_json_schema_time_matches(chars : Array[Char], start : Int) -> Bool {
  if chars.length() < start + 9 ||
    chars[start + 2] != ':' ||
    chars[start + 5] != ':' {
    return false
  }
  match
    (
      contract_json_schema_parse_digits(chars, start, start + 2),
      contract_json_schema_parse_digits(chars, start + 3, start + 5),
      contract_json_schema_parse_digits(chars, start + 6, start + 8),
    ) {
    (Some(hour), Some(minute), Some(second)) => {
      if hour > 23 || minute > 59 || second > 60 {
        return false
      }
      let mut index = start + 8
      if chars[index] == '.' {
        index += 1
        let fraction_start = index
        while index < chars.length() &&
              contract_json_schema_is_digit(chars[index]) {
          index += 1
        }
        if index == fraction_start {
          return false
        }
      }
      if index >= chars.length() {
        return false
      }
      match chars[index] {
        'Z' | 'z' => index == chars.length() - 1
        '+' | '-' => {
          if index + 6 != chars.length() || chars[index + 3] != ':' {
            return false
          }
          match
            (
              contract_json_schema_parse_digits(chars, index + 1, index + 3),
              contract_json_schema_parse_digits(chars, index + 4, index + 6),
            ) {
            (Some(offset_hour), Some(offset_minute)) =>
              offset_hour <= 23 && offset_minute <= 59
            _ => false
          }
        }
        _ => false
      }
    }
    _ => false
  }
}

///|
fn contract_json_schema_uuid_matches(chars : Array[Char]) -> Bool {
  if chars.length() != 36 {
    return false
  }
  for i in 0..<chars.length() {
    if i == 8 || i == 13 || i == 18 || i == 23 {
      if chars[i] != '-' {
        return false
      }
    } else if !contract_json_schema_is_hex_digit(chars[i]) {
      return false
    }
  }
  true
}

///|
fn contract_json_schema_parse_digits(
  chars : Array[Char],
  start : Int,
  end : Int,
) -> Int? {
  if start < 0 || end > chars.length() || start >= end {
    return None
  }
  let mut value = 0
  for i in start..<end {
    let digit = chars[i].to_int() - '0'.to_int()
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
fn contract_json_schema_is_digit(char : Char) -> Bool {
  let digit = char.to_int() - '0'.to_int()
  digit >= 0 && digit <= 9
}

///|
fn contract_json_schema_is_hex_digit(char : Char) -> Bool {
  contract_json_schema_is_digit(char) ||
  (char >= 'a' && char <= 'f') ||
  (char >= 'A' && char <= 'F')
}
