///|
/// JSON kinds accepted by a Stencil data contract.
/// `Any` accepts every JSON value and leaves its nested contents open.
pub(all) enum ContractKind {
  Any
  Null
  Bool
  Number
  String
  Array
  Object
}

///|
/// How template paths are resolved against the schema.
pub(all) enum ContractPathMode {
  RootPaths
  ContextAware
}

///|
/// A schema field. Paths use dots for object fields and repeat `[]` for each
/// nested array level. `kind` describes the value at the end of the full path.
/// `required` on an array-item path requires its containing array property, but
/// does not require any array level to contain items.
pub(all) struct ContractField {
  path : String
  kind : ContractKind
  required : Bool
}

///|
/// An invalid contract schema or unsupported JSON Schema definition.
pub(all) suberror ContractError {
  InvalidFieldPath(String)
  DuplicateFieldPath(String)
  InvalidParentKind(String, ContractKind, ContractKind)
  InvalidJsonSchema(String)
  UnsupportedJsonSchemaFeature(String, String)
}

///|
/// Severity of a contract diagnostic.
pub(all) enum ContractSeverity {
  Error
  Warning
}

///|
/// Stable category for a contract diagnostic.
pub(all) enum ContractDiagnosticCode {
  TemplateSyntax
  MissingPartial
  PartialCycle
  UndeclaredTemplatePath
  MissingRequiredField
  TypeMismatch
  ConstraintViolation
  UnexpectedField
  UnusedSchemaField
  NoSamples
}

///|
/// One deterministic issue found while checking a template and samples.
/// `source` is `template`, a reachable partial name, `sample`, `sample[index]`,
/// `samples`, or `schema`. `path` is the schema/template path; `instance_path`
/// is a JSON Pointer into the sample for sample validation diagnostics.
pub(all) struct ContractDiagnostic {
  severity : ContractSeverity
  code : ContractDiagnosticCode
  source : String
  path : String
  instance_path : String?
  expected : String
  actual : String
  message : String
}

///|
/// All diagnostics from one contract check.
pub(all) struct ContractReport {
  diagnostics : Array[ContractDiagnostic]
}

///|
/// A validated set of flat field declarations.
pub struct ContractSchema {
  fields : Array[ContractField]
  open_object_paths : Array[String]
  value_constraints : Array[(String, Json)]
}

///|
/// Internal parsed path component.
priv struct ContractPathPart {
  key : String
  array_depth : Int
}

///|
/// A template field reference and its owning source.
priv struct TemplateReference {
  source : String
  path : String
  scopes : Array[String]
}

///|
/// Construct a schema and validate paths, duplicates, and declared parent kinds.
/// Parent paths may be omitted; when present, their kinds must match the path
/// structure (`Object` for dotted children and `Array` before `[]`).
pub fn ContractSchema::new(
  fields : Array[ContractField],
) -> ContractSchema raise ContractError {
  contract_schema_new(fields, [], [])
}

///|
fn contract_schema_new(
  fields : Array[ContractField],
  open_object_paths : Array[String],
  value_constraints : Array[(String, Json)],
) -> ContractSchema raise ContractError {
  let copied : Array[ContractField] = []
  let by_path : Map[String, ContractField] = Map([])
  for field in fields {
    if parse_contract_path(field.path) is None {
      raise InvalidFieldPath(field.path)
    }
    if by_path.contains(field.path) {
      raise DuplicateFieldPath(field.path)
    }
    by_path.set(field.path, field)
    copied.push(field)
  }
  for field in copied {
    let parts = parse_contract_path(field.path).unwrap()
    for (parent_path, expected_kind) in contract_parent_requirements(parts) {
      match by_path.get(parent_path) {
        Some(parent) if !contract_kinds_equal(parent.kind, expected_kind) =>
          raise InvalidParentKind(parent_path, expected_kind, parent.kind)
        _ => ()
      }
    }
  }
  for path in open_object_paths {
    if path != "" && parse_contract_path(path) is None {
      raise InvalidFieldPath(path)
    }
  }
  for (path, _) in value_constraints {
    if path != "" && parse_contract_path(path) is None {
      raise InvalidFieldPath(path)
    }
  }
  { fields: copied, open_object_paths, value_constraints, }
}

///|
/// Whether a report contains no errors. Warnings do not make a report invalid.
pub fn ContractReport::is_valid(self : ContractReport) -> Bool {
  for diagnostic in self.diagnostics {
    match diagnostic.severity {
      ContractSeverity::Error => return false
      ContractSeverity::Warning => ()
    }
  }
  true
}

///|
fn parse_contract_path(path : String) -> Array[ContractPathPart]? {
  if path.length() == 0 {
    return None
  }
  let parts : Array[ContractPathPart] = []
  for raw_part in path.view().split(".".view()) {
    match parse_contract_path_part(raw_part.to_owned()) {
      Some(part) => parts.push(part)
      None => return None
    }
  }
  Some(parts)
}

///|
fn parse_contract_path_part(raw : String) -> ContractPathPart? {
  let (key_view, array_depth) = contract_strip_array_suffixes(raw.view(), 0)
  let key = key_view.to_owned()
  if key.length() == 0 ||
    key_view.contains_char('[') ||
    key_view.contains_char(']') {
    None
  } else {
    Some({ key, array_depth, })
  }
}

///|
fn contract_strip_array_suffixes(
  path : StringView,
  depth : Int,
) -> (StringView, Int) {
  match path.strip_suffix("[]".view()) {
    Some(prefix) => contract_strip_array_suffixes(prefix, depth + 1)
    None => (path, depth)
  }
}

///|
fn contract_parent_requirements(
  parts : Array[ContractPathPart],
) -> Array[(String, ContractKind)] {
  let result : Array[(String, ContractKind)] = []
  let mut current = ""
  for i = 0; i < parts.length(); i = i + 1 {
    let part = parts[i]
    let base = contract_join_path(current, part.key)
    current = base
    for _ in 0..<part.array_depth {
      result.push((current, ContractKind::Array))
      current = current + "[]"
    }
    if i < parts.length() - 1 {
      result.push((current, ContractKind::Object))
    }
  }
  result
}

///|
fn contract_join_path(parent : String, child : String) -> String {
  if parent.length() == 0 {
    child
  } else {
    parent + "." + child
  }
}

///|
fn contract_kind_name(kind : ContractKind) -> String {
  match kind {
    ContractKind::Any => "Any"
    ContractKind::Null => "Null"
    ContractKind::Bool => "Bool"
    ContractKind::Number => "Number"
    ContractKind::String => "String"
    ContractKind::Array => "Array"
    ContractKind::Object => "Object"
  }
}

///|
fn contract_json_kind_name(value : Json) -> String {
  match value {
    Null => "Null"
    True | False => "Bool"
    Number(_, ..) => "Number"
    String(_) => "String"
    Array(_) => "Array"
    Object(_) => "Object"
  }
}

///|
fn contract_kind_matches(kind : ContractKind, value : Json) -> Bool {
  match kind {
    ContractKind::Any => true
    ContractKind::Null => value is Null
    ContractKind::Bool =>
      match value {
        True | False => true
        _ => false
      }
    ContractKind::Number => value is Number(_, ..)
    ContractKind::String => value is String(_)
    ContractKind::Array => value is Array(_)
    ContractKind::Object => value is Object(_)
  }
}

///|
fn contract_kinds_equal(left : ContractKind, right : ContractKind) -> Bool {
  match (left, right) {
    (ContractKind::Any, ContractKind::Any)
    | (ContractKind::Null, ContractKind::Null)
    | (ContractKind::Bool, ContractKind::Bool)
    | (ContractKind::Number, ContractKind::Number)
    | (ContractKind::String, ContractKind::String)
    | (ContractKind::Array, ContractKind::Array)
    | (ContractKind::Object, ContractKind::Object) => true
    _ => false
  }
}

///|
fn contract_severities_equal(
  left : ContractSeverity,
  right : ContractSeverity,
) -> Bool {
  match (left, right) {
    (ContractSeverity::Error, ContractSeverity::Error)
    | (ContractSeverity::Warning, ContractSeverity::Warning) => true
    _ => false
  }
}

///|
fn contract_codes_equal(
  left : ContractDiagnosticCode,
  right : ContractDiagnosticCode,
) -> Bool {
  match (left, right) {
    (
      ContractDiagnosticCode::TemplateSyntax,
      ContractDiagnosticCode::TemplateSyntax,
    )
    | (
      ContractDiagnosticCode::MissingPartial,
      ContractDiagnosticCode::MissingPartial,
    )
    | (
      ContractDiagnosticCode::PartialCycle,
      ContractDiagnosticCode::PartialCycle,
    )
    | (
      ContractDiagnosticCode::UndeclaredTemplatePath,
      ContractDiagnosticCode::UndeclaredTemplatePath,
    )
    | (
      ContractDiagnosticCode::MissingRequiredField,
      ContractDiagnosticCode::MissingRequiredField,
    )
    | (
      ContractDiagnosticCode::TypeMismatch,
      ContractDiagnosticCode::TypeMismatch,
    )
    | (
      ContractDiagnosticCode::ConstraintViolation,
      ContractDiagnosticCode::ConstraintViolation,
    )
    | (
      ContractDiagnosticCode::UnexpectedField,
      ContractDiagnosticCode::UnexpectedField,
    )
    | (
      ContractDiagnosticCode::UnusedSchemaField,
      ContractDiagnosticCode::UnusedSchemaField,
    )
    | (ContractDiagnosticCode::NoSamples, ContractDiagnosticCode::NoSamples) =>
      true
    _ => false
  }
}
