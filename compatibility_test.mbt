///|
fn integer_schema() -> @stencil-contract.ContractSchema raise @stencil-contract.ContractError {
  @stencil-contract.ContractSchema::from_json_schema_text(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"integer\"}},\"additionalProperties\":false}",
  )
}

///|
test "integer preserves mathematical integrality and original decimal tokens" {
  let schema = integer_schema()
  for token in ["0", "-0", "1.0", "1e3", "0.1e1", "-12", "9007199254740993"] {
    let sample = @stencil-contract.parse_contract_json("{\"n\":" + token + "}")
    assert_true(
      @stencil-contract.check_contract("{{n}}", schema, sample).is_valid(),
    )
  }
  for token in ["1.5", "-0.01", "1e-3", "1.0000000000000000000001"] {
    let sample = @stencil-contract.parse_contract_json("{\"n\":" + token + "}")
    let report = @stencil-contract.check_contract("{{n}}", schema, sample)
    assert_false(report.is_valid())
    assert_eq(report.diagnostics[0].instance_path, Some("/n"))
    assert_eq(report.diagnostics[0].expected, "Integer")
  }
}

///|
test "numeric bounds enum const and multiples do not round through Double" {
  let bounded = @stencil-contract.ContractSchema::from_json_schema_text(
    "{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"integer\",\"maximum\":9007199254740992}}}",
  )
  assert_false(
    @stencil-contract.check_contract(
      "{{n}}",
      bounded,
      @stencil-contract.parse_contract_json("{\"n\":9007199254740993}"),
    ).is_valid(),
  )
  let exact = @stencil-contract.ContractSchema::from_json_schema_text(
    "{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"number\",\"exclusiveMinimum\":1,\"maximum\":1.0000000000000000000002}}}",
  )
  assert_true(
    @stencil-contract.check_contract(
      "{{n}}",
      exact,
      @stencil-contract.parse_contract_json("{\"n\":1.0000000000000000000001}"),
    ).is_valid(),
  )
  let multiple = @stencil-contract.ContractSchema::from_json_schema_text(
    "{\"type\":\"object\",\"properties\":{\"n\":{\"multipleOf\":9007199254740993}}}",
  )
  assert_true(
    @stencil-contract.check_contract(
      "{{n}}",
      multiple,
      @stencil-contract.parse_contract_json("{\"n\":18014398509481986}"),
    ).is_valid(),
  )
  assert_false(
    @stencil-contract.check_contract(
      "{{n}}",
      multiple,
      @stencil-contract.parse_contract_json("{\"n\":18014398509481984}"),
    ).is_valid(),
  )
  let enumeration = @stencil-contract.ContractSchema::from_json_schema_text(
    "{\"type\":\"object\",\"properties\":{\"n\":{\"enum\":[9007199254740992,9007199254740993],\"const\":9007199254740993}}}",
  )
  assert_false(
    @stencil-contract.check_contract(
      "{{n}}",
      enumeration,
      @stencil-contract.parse_contract_json("{\"n\":9007199254740992}"),
    ).is_valid(),
  )
  assert_true(
    @stencil-contract.check_contract(
      "{{n}}",
      enumeration,
      @stencil-contract.parse_contract_json("{\"n\":9007199254740993}"),
    ).is_valid(),
  )
}

///|
test "local refs retain integer and bounds inside arrays" {
  let schema = @stencil-contract.ContractSchema::from_json_schema_text(
    "{\"type\":\"object\",\"$defs\":{\"Positive\":{\"type\":\"integer\",\"minimum\":1}},\"properties\":{\"values\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/Positive\"},\"uniqueItems\":true}}}",
  )
  for source in ["{\"values\":[1,2]}", "{\"values\":[]}"] {
    assert_true(
      @stencil-contract.check_contract(
        "{{values}}",
        schema,
        @stencil-contract.parse_contract_json(source),
      ).is_valid(),
    )
  }
  for
    source in [
      "{\"values\":[1,1.0]}", "{\"values\":[1,1.5]}", "{\"values\":[0]}",
    ] {
    assert_false(
      @stencil-contract.check_contract(
        "{{values}}",
        schema,
        @stencil-contract.parse_contract_json(source),
      ).is_valid(),
    )
  }
}

///|
test "lossless parser handles escaped Unicode and rejects ambiguous input" {
  let value = @stencil-contract.parse_contract_json(
    "{\"标签\":[\"a\\\"b}1.5\",{\"n\":1.0000000000000000000001}],\"ok\":true,\"empty\":null}",
  )
  assert_true(value.stringify().contains("1.0000000000000000000001"))
  for
    text in [
      "{\"x\":1,\"x\":2}", "{\"x\":1,\"\\u0078\":2}", "1e999999999999", "[1,]", "01",
    ] {
    let rejected = try {
      ignore(@stencil-contract.parse_contract_json(text))
      false
    } catch {
      @stencil-contract.ContractError::InvalidJsonText(_) => true
      _ => false
    }
    assert_true(rejected)
  }
  let mut nested = "0"
  for _ in 0..<129 {
    nested = "[" + nested + "]"
  }
  let mut oversized = "1"
  for _ in 0..<4096 {
    oversized += "0"
  }
  for text in [nested, oversized, "1e4097", "1e-4097"] {
    let rejected = try {
      ignore(@stencil-contract.parse_contract_json(text))
      false
    } catch {
      @stencil-contract.ContractError::InvalidJsonText(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "import fails closed at dialect scope type and path boundaries" {
  for
    schema in [
      "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"object\"}",
      "{\"type\":\"object\",\"properties\":{\"node\":{\"properties\":{\"x\":{\"type\":\"string\"}}}}}",
      "{\"type\":\"object\",\"properties\":{\"a.b\":{\"type\":\"integer\"}}}", "{\"type\":\"object\",\"properties\":{\"x\":{\"$ref\":\"other.json\"}}}",
      "{\"type\":\"object\",\"properties\":{\"x\":{\"$ref\":\"#/$defs/x\",\"minimum\":1}},\"$defs\":{\"x\":{\"type\":\"integer\"}}}",
    ] {
    let rejected = try {
      ignore(@stencil-contract.ContractSchema::from_json_schema_text(schema))
      false
    } catch {
      @stencil-contract.ContractError::UnsupportedJsonSchemaFeature(_, _) =>
        true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "preserving import distinguishes schema assertions from data keywords" {
  for
    source in [
      "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"string\",\"format\":\"date\"}}}",
      "{\"type\":\"object\",\"propertyNames\":{\"pattern\":\"^[a-z]+$\"}}",
    ] {
    let rejected = try {
      ignore(@stencil-contract.ContractSchema::from_json_schema_text(source))
      false
    } catch {
      @stencil-contract.ContractError::UnsupportedJsonSchemaFeature(_, feature) =>
        feature.contains("preserving profile")
      _ => false
    }
    assert_true(rejected)
  }
  let schema = @stencil-contract.ContractSchema::from_json_schema_text(
    "{\"type\":\"object\",\"properties\":{\"data\":{\"const\":{\"pattern\":\"literal data\"}}}}",
  )
  assert_true(
    @stencil-contract.check_contract("{{data}}", schema, {
      "data": { "pattern": "literal data" },
    }).is_valid(),
  )
}
