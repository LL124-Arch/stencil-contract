///|
priv struct ContractJsonCursor {
  chars : Array[Char]
  mut index : Int
  mut depth : Int
}

///|
/// Parse JSON while retaining every numeric token for exact assertions.
/// Duplicate object keys, nesting beyond 128 levels, numeric tokens longer
/// than 4096 characters and exponent magnitudes above 4096 are rejected.
/// Use this entry point for schema/sample text; an already-rounded Double
/// cannot recover digits discarded by an earlier parser.
pub fn parse_contract_json(source : String) -> Json raise ContractError {
  ignore(@json.parse(source.view())) catch {
    _ => raise InvalidJsonText("malformed JSON or nesting beyond 128 levels")
  }
  let cursor : ContractJsonCursor = {
    chars: source.to_array(),
    index: 0,
    depth: 0,
  }
  cursor.value()
}

///|
/// Import the preserving JSON Schema profile without rounding numeric tokens.
/// This profile rejects engine-dependent pattern/format extensions. The Json
/// API from_json_schema retains its documented native-regex/format assertions.
pub fn ContractSchema::from_json_schema_text(
  source : String,
) -> ContractSchema raise ContractError {
  let schema = parse_contract_json(source)
  contract_require_preserving_profile(schema, "$")
  ContractSchema::from_json_schema(schema)
}

///|
fn contract_require_preserving_profile(
  schema : Json,
  path : String,
) -> Unit raise ContractError {
  match schema {
    Object(keywords) => {
      for name in ["pattern", "format"] {
        if keywords.contains(name) {
          raise UnsupportedJsonSchemaFeature(
            path,
            name + " is outside the preserving profile",
          )
        }
      }
      for group in ["properties", "$defs", "definitions"] {
        match keywords.get(group) {
          Some(Object(children)) =>
            for (name, child) in children {
              contract_require_preserving_profile(
                child,
                path + "/" + group + "/" + name,
              )
            }
          _ => ()
        }
      }
      for name in ["items", "propertyNames"] {
        match keywords.get(name) {
          Some(child) =>
            contract_require_preserving_profile(child, path + "/" + name)
          None => ()
        }
      }
    }
    _ => ()
  }
}

///|
fn ContractJsonCursor::space(self : ContractJsonCursor) -> Unit {
  for ;; {
    match self.chars.get(self.index) {
      Some(' ' | '\n' | '\r' | '\t') => self.index += 1
      _ => break
    }
  }
}

///|
fn ContractJsonCursor::string_value(
  self : ContractJsonCursor,
) -> String raise ContractError {
  let token = StringBuilder()
  token.write_char('"')
  self.index += 1
  let mut escaped = false
  for ;; {
    let char = self.chars[self.index]
    self.index += 1
    token.write_char(char)
    if escaped {
      escaped = false
    } else if char == '\\' {
      escaped = true
    } else if char == '"' {
      break
    }
  }
  let parsed = @json.parse(token.to_string().view()) catch {
    _ => raise InvalidJsonText("invalid JSON string")
  }
  match parsed {
    String(value) => value
    _ => raise InvalidJsonText("expected JSON string")
  }
}

///|
fn ContractJsonCursor::value_inner(
  self : ContractJsonCursor,
) -> Json raise ContractError {
  self.space()
  match self.chars[self.index] {
    '"' => Json::string(self.string_value())
    '[' => {
      self.index += 1
      self.space()
      let items : Array[Json] = []
      if self.chars[self.index] == ']' {
        self.index += 1
        return Json::array(items)
      }
      for ;; {
        items.push(self.value())
        self.space()
        let separator = self.chars[self.index]
        self.index += 1
        if separator == ']' {
          break
        }
      }
      Json::array(items)
    }
    '{' => {
      self.index += 1
      self.space()
      let members : Map[String, Json] = Map([])
      if self.chars[self.index] == '}' {
        self.index += 1
        return Json::object(members)
      }
      for ;; {
        self.space()
        let key = self.string_value()
        if members.contains(key) {
          raise InvalidJsonText("duplicate object key: " + key)
        }
        self.space()
        self.index += 1 // colon, already checked by the core parser
        members.set(key, self.value())
        self.space()
        let separator = self.chars[self.index]
        self.index += 1
        if separator == '}' {
          break
        }
      }
      Json::object(members)
    }
    _ => {
      let token = StringBuilder()
      for ;; {
        match self.chars.get(self.index) {
          None | Some(' ' | '\n' | '\r' | '\t' | ',' | ']' | '}') => break
          Some(char) => {
            token.write_char(char)
            self.index += 1
          }
        }
      }
      let text = token.to_string()
      let value = @json.parse(text.view()) catch {
        _ => raise InvalidJsonText("invalid JSON token")
      }
      match value {
        Number(number, ..) => {
          let exact = Json::number(number, repr=text)
          if contract_number_parts(exact) is None {
            raise InvalidJsonText(
              "numeric token/exponent exceeds the supported profile",
            )
          }
          exact
        }
        _ => value
      }
    }
  }
}

///|
fn ContractJsonCursor::value(
  self : ContractJsonCursor,
) -> Json raise ContractError {
  self.depth += 1
  if self.depth > 128 {
    raise InvalidJsonText("nesting beyond 128 levels")
  }
  let result = self.value_inner()
  self.depth -= 1
  result
}
