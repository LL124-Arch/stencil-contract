///|
test "Stencil dependency renders a template" {
  let output = @stencil.render("Hello {{name}}", { "name": "MoonBit" })
  assert_eq(output, "Hello MoonBit")
}

///|
fn has_issue(
  report : @stencil-contract.ContractReport,
  expected_code : @stencil-contract.ContractDiagnosticCode,
  expected_path : String,
) -> Bool {
  for diagnostic in report.diagnostics {
    if diagnostic.path == expected_path &&
      diagnostic_code_matches(diagnostic.code, expected_code) {
      return true
    }
  }
  false
}

///|
fn has_issue_from(
  report : @stencil-contract.ContractReport,
  expected_code : @stencil-contract.ContractDiagnosticCode,
  expected_source : String,
  expected_path : String,
) -> Bool {
  for diagnostic in report.diagnostics {
    if diagnostic.source == expected_source &&
      diagnostic.path == expected_path &&
      diagnostic_code_matches(diagnostic.code, expected_code) {
      return true
    }
  }
  false
}

///|
fn diagnostic_code_matches(
  left : @stencil-contract.ContractDiagnosticCode,
  right : @stencil-contract.ContractDiagnosticCode,
) -> Bool {
  match (left, right) {
    (
      @stencil-contract.ContractDiagnosticCode::TemplateSyntax,
      @stencil-contract.ContractDiagnosticCode::TemplateSyntax,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::MissingPartial,
      @stencil-contract.ContractDiagnosticCode::MissingPartial,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::PartialCycle,
      @stencil-contract.ContractDiagnosticCode::PartialCycle,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
      @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::UnexpectedField,
      @stencil-contract.ContractDiagnosticCode::UnexpectedField,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::UnusedSchemaField,
      @stencil-contract.ContractDiagnosticCode::UnusedSchemaField,
    )
    | (
      @stencil-contract.ContractDiagnosticCode::NoSamples,
      @stencil-contract.ContractDiagnosticCode::NoSamples,
    ) => true
    _ => false
  }
}

///|
fn count_issue_from(
  report : @stencil-contract.ContractReport,
  expected_code : @stencil-contract.ContractDiagnosticCode,
  expected_source : String,
  expected_path : String,
) -> Int {
  let mut count = 0
  for diagnostic in report.diagnostics {
    if diagnostic.source == expected_source &&
      diagnostic.path == expected_path &&
      diagnostic_code_matches(diagnostic.code, expected_code) {
      count += 1
    }
  }
  count
}

///|
fn reports_have_same_diagnostics(
  left : @stencil-contract.ContractReport,
  right : @stencil-contract.ContractReport,
) -> Bool {
  if left.diagnostics.length() != right.diagnostics.length() {
    return false
  }
  for i in 0..<left.diagnostics.length() {
    let left_diagnostic = left.diagnostics[i]
    let right_diagnostic = right.diagnostics[i]
    if !diagnostic_code_matches(left_diagnostic.code, right_diagnostic.code) ||
      left_diagnostic.source != right_diagnostic.source ||
      left_diagnostic.path != right_diagnostic.path ||
      left_diagnostic.instance_path != right_diagnostic.instance_path ||
      left_diagnostic.expected != right_diagnostic.expected ||
      left_diagnostic.actual != right_diagnostic.actual ||
      left_diagnostic.message != right_diagnostic.message ||
      !diagnostic_severity_matches(
        left_diagnostic.severity,
        right_diagnostic.severity,
      ) {
      return false
    }
  }
  true
}

///|
fn diagnostic_severity_matches(
  left : @stencil-contract.ContractSeverity,
  right : @stencil-contract.ContractSeverity,
) -> Bool {
  match (left, right) {
    (
      @stencil-contract.ContractSeverity::Error,
      @stencil-contract.ContractSeverity::Error,
    )
    | (
      @stencil-contract.ContractSeverity::Warning,
      @stencil-contract.ContractSeverity::Warning,
    ) => true
    _ => false
  }
}

///|
test "schema rejects invalid and duplicate paths" {
  let invalid = try {
    ignore(
      @stencil-contract.ContractSchema::new([
        {
          path: "users[][]",
          kind: @stencil-contract.ContractKind::Array,
          required: true,
        },
      ]),
    )
    "no error"
  } catch {
    @stencil-contract.ContractError::InvalidFieldPath(path) => path
    _ => "wrong error"
  } noraise {
    _ => "no error"
  }
  assert_eq(invalid, "users[][]")

  let invalid_separator = try {
    ignore(
      @stencil-contract.ContractSchema::new([
        {
          path: "profile..name",
          kind: @stencil-contract.ContractKind::String,
          required: true,
        },
      ]),
    )
    "no error"
  } catch {
    @stencil-contract.ContractError::InvalidFieldPath(path) => path
    _ => "wrong error"
  } noraise {
    _ => "no error"
  }
  assert_eq(invalid_separator, "profile..name")

  let duplicate = try {
    ignore(
      @stencil-contract.ContractSchema::new([
        {
          path: "name",
          kind: @stencil-contract.ContractKind::String,
          required: true,
        },
        {
          path: "name",
          kind: @stencil-contract.ContractKind::String,
          required: false,
        },
      ]),
    )
    "no error"
  } catch {
    @stencil-contract.ContractError::DuplicateFieldPath(path) => path
    _ => "wrong error"
  } noraise {
    _ => "no error"
  }
  assert_eq(duplicate, "name")

  let parent_kind = try {
    ignore(
      @stencil-contract.ContractSchema::new([
        {
          path: "users",
          kind: @stencil-contract.ContractKind::String,
          required: true,
        },
        {
          path: "users[].name",
          kind: @stencil-contract.ContractKind::String,
          required: true,
        },
      ]),
    )
    "no error"
  } catch {
    @stencil-contract.ContractError::InvalidParentKind(path, expected, actual) => {
      ignore(expected)
      ignore(actual)
      path
    }
    _ => "wrong error"
  } noraise {
    _ => "no error"
  }
  assert_eq(parent_kind, "users")
}

///|
test "valid object schema and nested array wildcard validate" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "title",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "profile",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "profile.name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "users[].active",
      kind: @stencil-contract.ContractKind::Bool,
      required: false,
    },
  ])
  let report = @stencil-contract.check_contract(
    "{{title}} {{profile.name}}",
    schema,
    {
      "title": "Team",
      "profile": { "name": "Ada" },
      "users": [{ "name": "Lin", "active": true }, { "name": "Kai" }],
    },
  )
  assert_true(report.is_valid())
  assert_true(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::UnusedSchemaField,
      "users[].name",
    ),
  )
}

///|
test "required fields and strict sample types are enforced" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "nickname",
      kind: @stencil-contract.ContractKind::String,
      required: false,
    },
    {
      path: "tags",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "tags[]",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract(
    "{{name}} {{nickname}} {{tags}}",
    schema,
    { "name": 42, "tags": [true], "unknown": "extra" },
  )
  assert_false(report.is_valid())
  assert_true(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "name",
    ),
  )
  assert_true(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "tags[]",
    ),
  )
  assert_true(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::UnexpectedField,
      "unknown",
    ),
  )
  assert_false(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
      "nickname",
    ),
  )

  let missing = @stencil-contract.check_contract("{{name}}", schema, {})
  assert_true(
    has_issue(
      missing,
      @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
      "name",
    ),
  )
}

///|
test "optional object parents allow missing descendants and root must be object" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "profile",
      kind: @stencil-contract.ContractKind::Object,
      required: false,
    },
    {
      path: "profile.name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let optional_parent = @stencil-contract.check_contract(
    "{{profile.name}}",
    schema,
    {},
  )
  assert_true(optional_parent.is_valid())

  let invalid_root = @stencil-contract.check_contract(
    "{{profile.name}}", schema, true,
  )
  assert_true(
    has_issue(
      invalid_root,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "",
    ),
  )

  let array_schema = @stencil-contract.ContractSchema::new([
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
  ])
  let empty_array = @stencil-contract.check_contract(
    "{{users}}",
    array_schema,
    { "users": [] },
  )
  assert_true(empty_array.is_valid())
}

///|
test "all JSON kinds and Any values are validated" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "nothing",
      kind: @stencil-contract.ContractKind::Null,
      required: true,
    },
    {
      path: "enabled",
      kind: @stencil-contract.ContractKind::Bool,
      required: true,
    },
    {
      path: "count",
      kind: @stencil-contract.ContractKind::Number,
      required: true,
    },
    {
      path: "label",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "tags",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "tags[]",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "meta",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "meta.kind",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "flexible",
      kind: @stencil-contract.ContractKind::Any,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract(
    "{{nothing}} {{enabled}} {{count}} {{label}} {{tags}} {{meta.kind}} {{flexible.arbitrary}}",
    schema,
    {
      "nothing": null,
      "enabled": false,
      "count": 3,
      "label": "ready",
      "tags": ["one", "two"],
      "meta": { "kind": "leaf" },
      "flexible": { "arbitrary": [1, true, null] },
    },
  )
  assert_true(report.is_valid())
}

///|
test "array item fields are checked and extra nested keys are rejected" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract("{{users}}", schema, {
    "users": [{ "name": "Ada", "admin": true }, { "admin": false }],
  })
  assert_true(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::UnexpectedField,
      "users[].admin",
    ),
  )
  assert_true(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
      "users[].name",
    ),
  )

  let untyped_items = @stencil-contract.check_contract(
    "{{users}}",
    @stencil-contract.ContractSchema::new([
      {
        path: "users",
        kind: @stencil-contract.ContractKind::Array,
        required: true,
      },
    ]),
    { "users": [{ "unknown": true }] },
  )
  assert_true(
    has_issue(
      untyped_items,
      @stencil-contract.ContractDiagnosticCode::UnexpectedField,
      "users[].unknown",
    ),
  )
}

///|
test "template paths are checked literally and dot is not a data field" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "items",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "items[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "items[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let section_report = @stencil-contract.check_contract(
    "{{#items}}{{name}}{{/items}}",
    schema,
    { "items": [{ "name": "Ada" }] },
  )
  assert_true(
    has_issue(
      section_report,
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      "name",
    ),
  )

  let dot_report = @stencil-contract.check_contract(
    "{{.}}",
    @stencil-contract.ContractSchema::new([]),
    {},
  )
  assert_true(dot_report.is_valid())
}

///|
test "context-aware checks resolve nested object and array section fields" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "users[].profile",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].profile.active",
      kind: @stencil-contract.ContractKind::Bool,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract_with_context(
    "{{#users}}{{name}} {{#profile}}{{active}}{{/profile}}{{/users}}",
    schema,
    {
      "users": [
        { "name": "Ada", "profile": { "active": true } },
        { "name": "Lin", "profile": { "active": false } },
      ],
    },
  )
  assert_true(report.is_valid())
  assert_false(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      "name",
    ),
  )
  assert_false(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::UnusedSchemaField,
      "users[].profile.active",
    ),
  )

  let any_schema = @stencil-contract.ContractSchema::new([
    {
      path: "payload",
      kind: @stencil-contract.ContractKind::Any,
      required: true,
    },
  ])
  let any_report = @stencil-contract.check_contract_with_context(
    "{{#payload}}{{name}}{{/payload}}",
    any_schema,
    { "payload": { "name": "Ada" } },
  )
  assert_true(any_report.is_valid())
}

///|
test "context-aware checks retain root fallback and inverted-section scope" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "title",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
  ])
  let fallback = @stencil-contract.check_contract_with_context(
    "{{#users}}{{title}}{{/users}}",
    schema,
    { "title": "Roster", "users": [{}, {}] },
  )
  assert_true(fallback.is_valid())

  let shadowing_schema = @stencil-contract.ContractSchema::new([
    {
      path: "name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let shadowing = @stencil-contract.check_contract_with_context(
    "{{#users}}{{name}}{{/users}}",
    shadowing_schema,
    { "name": "Root", "users": [{ "name": "Ada" }] },
  )
  assert_true(shadowing.is_valid())
  assert_true(
    has_issue(
      shadowing,
      @stencil-contract.ContractDiagnosticCode::UnusedSchemaField,
      "name",
    ),
  )

  let inverted_schema = @stencil-contract.ContractSchema::new([
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let inverted = @stencil-contract.check_contract_with_context(
    "{{^users}}{{name}}{{/users}}",
    inverted_schema,
    { "users": [] },
  )
  assert_true(
    has_issue(
      inverted,
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      "name",
    ),
  )
}

///|
test "context-aware partials inherit each invocation scope" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "profile",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "profile.name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract_with_partials_and_context(
    "{{#users}}{{>label}}{{/users}}{{#profile}}{{>label}}{{/profile}}",
    Map([("label", "{{>identity}}"), ("identity", "{{name}}")]),
    schema,
    { "users": [{ "name": "Ada" }], "profile": { "name": "Lin" } },
  )
  assert_true(report.is_valid())
  assert_false(
    has_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      "identity",
      "name",
    ),
  )
}

///|
test "malformed templates return a syntax diagnostic" {
  let report = @stencil-contract.check_contract(
    "{{#open}}",
    @stencil-contract.ContractSchema::new([]),
    {},
  )
  assert_true(
    has_issue(
      report,
      @stencil-contract.ContractDiagnosticCode::TemplateSyntax,
      "",
    ),
  )
}

///|
test "reachable nested partials are checked against the same root schema" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let partials = Map([("header", "{{>identity}}"), ("identity", "{{name}}")])
  let report = @stencil-contract.check_contract_with_partials(
    "{{>header}}",
    partials,
    schema,
    { "name": "Ada" },
  )
  assert_true(report.is_valid())

  let partial_error = @stencil-contract.check_contract_with_partials(
    "{{>card}}",
    Map([("card", "{{missing}}")]),
    schema,
    { "name": "Ada" },
  )
  assert_true(
    has_issue_from(
      partial_error,
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      "card",
      "missing",
    ),
  )
}

///|
test "missing and cyclic partials produce errors" {
  let schema = @stencil-contract.ContractSchema::new([])
  let missing = @stencil-contract.check_contract_with_partials(
    "{{>absent}}",
    Map([]),
    schema,
    {},
  )
  assert_true(
    has_issue(
      missing,
      @stencil-contract.ContractDiagnosticCode::MissingPartial,
      "absent",
    ),
  )

  let cyclic = @stencil-contract.check_contract_with_partials(
    "{{>a}}",
    Map([("a", "{{>b}}"), ("b", "{{>a}}")]),
    schema,
    {},
  )
  assert_true(
    has_issue(
      cyclic,
      @stencil-contract.ContractDiagnosticCode::PartialCycle,
      "a",
    ),
  )
}

///|
test "batch checks identify each failing sample and preserve duplicates" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract_samples(
    "{{name}}",
    Map([]),
    schema,
    [{ "name": 1 }, { "name": true }, { "name": "Ada" }, true],
    @stencil-contract.ContractPathMode::RootPaths,
  )
  assert_false(report.is_valid())
  assert_true(
    has_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "sample[0]",
      "name",
    ),
  )
  assert_true(
    has_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "sample[1]",
      "name",
    ),
  )
  assert_eq(
    count_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "sample[2]",
      "name",
    ),
    0,
  )
  assert_true(
    has_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "sample[3]",
      "",
    ),
  )
}

///|
test "batch checks analyze shared partials once and validate scoped samples" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: true,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract_samples(
    "{{#users}}{{>label}}{{/users}}",
    Map([("label", "{{name}}")]),
    schema,
    [{ "users": [{ "name": "Ada" }] }, { "users": [{}] }],
    @stencil-contract.ContractPathMode::ContextAware,
  )
  assert_false(report.is_valid())
  assert_true(
    has_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
      "sample[1]",
      "users[].name",
    ),
  )
  assert_eq(
    count_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      "label",
      "name",
    ),
    0,
  )

  let missing_partial = @stencil-contract.check_contract_samples(
    "{{>absent}}",
    Map([]),
    schema,
    [{ "users": [] }, { "users": [] }],
    @stencil-contract.ContractPathMode::RootPaths,
  )
  assert_eq(
    count_issue_from(
      missing_partial,
      @stencil-contract.ContractDiagnosticCode::MissingPartial,
      "template",
      "absent",
    ),
    1,
  )
  assert_eq(
    count_issue_from(
      missing_partial,
      @stencil-contract.ContractDiagnosticCode::UnusedSchemaField,
      "schema",
      "users[].name",
    ),
    1,
  )
}

///|
test "batch checks reject an empty sample list" {
  let report = @stencil-contract.check_contract_samples(
    "{{name}}",
    Map([]),
    @stencil-contract.ContractSchema::new([
      {
        path: "name",
        kind: @stencil-contract.ContractKind::String,
        required: true,
      },
    ]),
    [],
    @stencil-contract.ContractPathMode::RootPaths,
  )
  assert_false(report.is_valid())
  assert_true(
    has_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::NoSamples,
      "samples",
      "",
    ),
  )
}

///|
test "batch diagnostics are ordered independently of object key order" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "alpha",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
    {
      path: "beta",
      kind: @stencil-contract.ContractKind::String,
      required: false,
    },
  ])
  let first = @stencil-contract.check_contract_samples(
    "{{alpha}}",
    Map([]),
    schema,
    [{ "zeta": true, "alpha": 1, "gamma": null }],
    @stencil-contract.ContractPathMode::RootPaths,
  )
  let second = @stencil-contract.check_contract_samples(
    "{{alpha}}",
    Map([]),
    schema,
    [{ "gamma": null, "alpha": 1, "zeta": true }],
    @stencil-contract.ContractPathMode::RootPaths,
  )
  assert_true(reports_have_same_diagnostics(first, second))
  assert_eq(first.diagnostics[0].source, "schema")
  assert_eq(first.diagnostics[0].path, "beta")
  assert_eq(first.diagnostics[1].path, "alpha")
  assert_eq(first.diagnostics[2].path, "gamma")
  assert_eq(first.diagnostics[3].path, "zeta")
}

///|
test "single sample APIs retain the sample source name" {
  let report = @stencil-contract.check_contract(
    "{{name}}",
    @stencil-contract.ContractSchema::new([
      {
        path: "name",
        kind: @stencil-contract.ContractKind::String,
        required: true,
      },
    ]),
    {},
  )
  assert_true(
    has_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
      "sample",
      "name",
    ),
  )
}

///|
test "sample diagnostics retain concrete array element paths" {
  let schema = @stencil-contract.ContractSchema::new([
    {
      path: "users",
      kind: @stencil-contract.ContractKind::Array,
      required: true,
    },
    {
      path: "users[]",
      kind: @stencil-contract.ContractKind::Object,
      required: false,
    },
    {
      path: "users[].name",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let report = @stencil-contract.check_contract_samples(
    "{{users}}",
    Map([]),
    schema,
    [{ "users": [{ "name": 1 }, { "name": 2 }] }],
    @stencil-contract.ContractPathMode::RootPaths,
  )
  assert_eq(
    count_issue_from(
      report,
      @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      "sample[0]",
      "users[].name",
    ),
    2,
  )
  let mut found_first = false
  let mut found_second = false
  for diagnostic in report.diagnostics {
    if diagnostic.source == "sample[0]" && diagnostic.path == "users[].name" {
      match diagnostic.instance_path {
        Some("/users/0/name") => found_first = true
        Some("/users/1/name") => found_second = true
        _ => ()
      }
    }
  }
  assert_true(found_first)
  assert_true(found_second)

  let missing = @stencil-contract.check_contract("{{users}}", schema, {
    "users": [{}],
  })
  let mut found_missing = false
  for diagnostic in missing.diagnostics {
    if diagnostic_code_matches(
        diagnostic.code,
        @stencil-contract.ContractDiagnosticCode::MissingRequiredField,
      ) &&
      diagnostic.path == "users[].name" {
      found_missing = diagnostic.instance_path == Some("/users/0/name")
    }
  }
  assert_true(found_missing)
}

///|
test "sample JSON pointers cover root, extra fields, and escaped keys" {
  let escaped_schema = @stencil-contract.ContractSchema::new([
    {
      path: "a~/b",
      kind: @stencil-contract.ContractKind::String,
      required: true,
    },
  ])
  let escaped_report = @stencil-contract.check_contract(
    "{{a~/b}}",
    escaped_schema,
    { "a~/b": 10, "extra/key~": true },
  )
  let mut found_type = false
  let mut found_extra = false
  for diagnostic in escaped_report.diagnostics {
    match (diagnostic.code, diagnostic.instance_path) {
      (@stencil-contract.ContractDiagnosticCode::TypeMismatch, Some("/a~0~1b")) =>
        found_type = true
      (
        @stencil-contract.ContractDiagnosticCode::UnexpectedField,
        Some("/extra~1key~0"),
      ) => found_extra = true
      _ => ()
    }
  }
  assert_true(found_type)
  assert_true(found_extra)

  let root_report = @stencil-contract.check_contract("", escaped_schema, true)
  let mut found_root = false
  for diagnostic in root_report.diagnostics {
    if diagnostic_code_matches(
        diagnostic.code,
        @stencil-contract.ContractDiagnosticCode::TypeMismatch,
      ) &&
      diagnostic.path == "" {
      found_root = diagnostic.instance_path == Some("")
    }
  }
  assert_true(found_root)
}

///|
test "static diagnostics do not have a sample instance path" {
  let report = @stencil-contract.check_contract(
    "{{missing}}",
    @stencil-contract.ContractSchema::new([]),
    {},
  )
  let mut found_static = false
  for diagnostic in report.diagnostics {
    if diagnostic_code_matches(
        diagnostic.code,
        @stencil-contract.ContractDiagnosticCode::UndeclaredTemplatePath,
      ) {
      found_static = diagnostic.instance_path is None
    }
  }
  assert_true(found_static)
}
