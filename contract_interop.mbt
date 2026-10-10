///|
/// Import the supported object-oriented subset of JSON Schema.
///
/// Supported validation keywords are `type`, `properties`, `required`,
/// `items`, boolean `additionalProperties`, `propertyNames`,
/// `dependentRequired`, the string formats `date`, `time`, `date-time`, and
/// `uuid`, and acyclic local JSON Pointer `$ref` references.
/// JSON Schema's default additional-properties behavior is preserved.
/// Unsupported constraints raise `ContractError` instead of being silently
/// discarded. The root schema must be compatible with the checker's object-root
/// sample contract.
pub fn ContractSchema::from_json_schema(
  schema : Json,
) -> ContractSchema raise ContractError {
  let fields : Array[ContractField] = []
  let open_object_paths : Array[String] = []
  let active_refs : Array[String] = []
  let value_constraints : Array[(String, Json)] = []
  contract_import_json_schema_node(
    schema, schema, "", false, true, fields, open_object_paths, active_refs, value_constraints,
  )
  contract_schema_new(fields, open_object_paths, value_constraints)
}

///|
fn contract_import_json_schema_node(
  root_schema : Json,
  schema : Json,
  path : String,
  required : Bool,
  is_root : Bool,
  fields : Array[ContractField],
  open_object_paths : Array[String],
  active_refs : Array[String],
  value_constraints : Array[(String, Json)],
) -> Unit raise ContractError {
  match schema {
    True =>
      if is_root {
        contract_add_open_object_path(open_object_paths, "")
      } else {
        fields.push({ path, kind: ContractKind::Any, required, })
      }
    False =>
      raise UnsupportedJsonSchemaFeature(
        contract_json_schema_path_label(path),
        "false schema",
      )
    Object(keywords) => {
      contract_validate_json_schema_definitions(keywords, path)
      if keywords.contains("$id") &&
        (path.length() > 0 || active_refs.length() > 0) {
        raise UnsupportedJsonSchemaFeature(
          contract_json_schema_path_label(path),
          "nested $id resource scope",
        )
      }
      if keywords.contains("$ref") {
        contract_import_json_schema_reference(
          root_schema, keywords, path, required, is_root, fields, open_object_paths,
          active_refs, value_constraints,
        )
        return
      }
      for (keyword, _) in keywords {
        if !contract_json_schema_keyword_is_supported(keyword) {
          raise UnsupportedJsonSchemaFeature(
            contract_json_schema_path_label(path),
            keyword,
          )
        }
      }
      match contract_parse_json_schema_value_constraint(keywords, path) {
        Some(constraint) => value_constraints.push((path, constraint))
        None => ()
      }

      let properties = match keywords.get("properties") {
        Some(Object(properties)) => Some(properties)
        Some(_) =>
          raise InvalidJsonSchema(
            contract_json_schema_path_label(path) + ".properties",
          )
        None => None
      }
      let required_names : Array[String] = []
      match keywords.get("required") {
        Some(Array(names)) =>
          for name in names {
            match name {
              String(name) =>
                if !required_names.contains(name) {
                  required_names.push(name)
                }
              _ =>
                raise InvalidJsonSchema(
                  contract_json_schema_path_label(path) + ".required",
                )
            }
          }
        Some(_) =>
          raise InvalidJsonSchema(
            contract_json_schema_path_label(path) + ".required",
          )
        None => ()
      }

      let type_name = match keywords.get("type") {
        Some(String(name)) => Some(name)
        Some(Array(_)) =>
          raise UnsupportedJsonSchemaFeature(
            contract_json_schema_path_label(path),
            "type union",
          )
        Some(_) =>
          raise InvalidJsonSchema(
            contract_json_schema_path_label(path) + ".type",
          )
        None => None
      }
      let has_items = keywords.contains("items")
      let has_object_keywords = properties is Some(_) ||
        keywords.contains("required") ||
        keywords.contains("additionalProperties") ||
        keywords.contains("propertyNames") ||
        keywords.contains("dependentRequired")
      let kind = match type_name {
        Some(name) => contract_json_schema_kind(name, path)
        None if has_object_keywords => ContractKind::Object
        None if has_items => ContractKind::Array
        None => ContractKind::Any
      }

      if properties is Some(_) &&
        !contract_kinds_equal(kind, ContractKind::Object) {
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + ".properties",
        )
      }
      if keywords.contains("required") &&
        !contract_kinds_equal(kind, ContractKind::Object) {
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + ".required",
        )
      }
      if has_items && !contract_kinds_equal(kind, ContractKind::Array) {
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + ".items",
        )
      }

      let allows_additional_properties = match
        keywords.get("additionalProperties") {
        Some(True) => true
        Some(False) => false
        Some(_) =>
          raise UnsupportedJsonSchemaFeature(
            contract_json_schema_path_label(path),
            "additionalProperties",
          )
        None => true
      }
      if keywords.contains("additionalProperties") &&
        !contract_kinds_equal(kind, ContractKind::Object) {
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + ".additionalProperties",
        )
      }
      if keywords.contains("propertyNames") &&
        !contract_kinds_equal(kind, ContractKind::Object) {
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + ".propertyNames",
        )
      }
      if keywords.contains("dependentRequired") &&
        !contract_kinds_equal(kind, ContractKind::Object) {
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + ".dependentRequired",
        )
      }

      if is_root {
        if !contract_kinds_equal(kind, ContractKind::Object) &&
          !contract_kinds_equal(kind, ContractKind::Any) {
          raise InvalidJsonSchema(contract_json_schema_path_label(path))
        }
        if contract_kinds_equal(kind, ContractKind::Any) {
          contract_add_open_object_path(open_object_paths, "")
        }
      } else {
        fields.push({ path, kind, required, })
      }

      if contract_kinds_equal(kind, ContractKind::Object) {
        if allows_additional_properties {
          contract_add_open_object_path(open_object_paths, path)
        }
        match properties {
          Some(property_map) =>
            for (name, property_schema) in property_map {
              let property_path = contract_join_path(path, name)
              contract_import_json_schema_node(
                root_schema,
                property_schema,
                property_path,
                required_names.contains(name),
                false,
                fields,
                open_object_paths,
                active_refs,
                value_constraints,
              )
            }
          None => ()
        }
        for name in required_names {
          match properties {
            Some(property_map) if property_map.contains(name) => ()
            _ => {
              if !allows_additional_properties {
                raise UnsupportedJsonSchemaFeature(
                  contract_json_schema_path_label(path),
                  "required property without a declared property schema",
                )
              }
              let property_path = contract_join_path(path, name)
              fields.push({
                path: property_path,
                kind: ContractKind::Any,
                required: true,
              })
            }
          }
        }
      } else if contract_kinds_equal(kind, ContractKind::Array) {
        match keywords.get("items") {
          Some(Array(_)) =>
            raise UnsupportedJsonSchemaFeature(
              contract_json_schema_path_label(path),
              "tuple items",
            )
          Some(item_schema) =>
            contract_import_json_schema_node(
              root_schema,
              item_schema,
              path + "[]",
              false,
              false,
              fields,
              open_object_paths,
              active_refs,
              value_constraints,
            )
          None =>
            fields.push({
              path: path + "[]",
              kind: ContractKind::Any,
              required: false,
            })
        }
      }
    }
    _ => raise InvalidJsonSchema(contract_json_schema_path_label(path))
  }
}

///|
fn contract_import_json_schema_reference(
  root_schema : Json,
  keywords : Map[String, Json],
  path : String,
  required : Bool,
  is_root : Bool,
  fields : Array[ContractField],
  open_object_paths : Array[String],
  active_refs : Array[String],
  value_constraints : Array[(String, Json)],
) -> Unit raise ContractError {
  let reference = match keywords.get("$ref") {
    Some(String(reference)) => reference
    _ =>
      raise InvalidJsonSchema(contract_json_schema_path_label(path) + ".$ref")
  }
  for (keyword, _) in keywords {
    if keyword != "$ref" &&
      !contract_json_schema_annotation_keyword_is_supported(keyword) &&
      keyword != "$defs" &&
      keyword != "definitions" {
      raise UnsupportedJsonSchemaFeature(
        contract_json_schema_path_label(path),
        "$ref sibling " + keyword,
      )
    }
  }
  if active_refs.contains(reference) {
    raise UnsupportedJsonSchemaFeature(
      contract_json_schema_path_label(path),
      "recursive $ref",
    )
  }
  let target = contract_resolve_json_schema_reference(
    root_schema, reference, path,
  )
  active_refs.push(reference)
  contract_import_json_schema_node(
    root_schema, target, path, required, is_root, fields, open_object_paths, active_refs,
    value_constraints,
  )
  ignore(active_refs.pop())
}

///|
fn contract_resolve_json_schema_reference(
  root_schema : Json,
  reference : String,
  path : String,
) -> Json raise ContractError {
  if reference == "#" {
    return root_schema
  }
  let pointer = match reference.view().strip_prefix("#/".view()) {
    Some(pointer) => pointer
    None =>
      raise UnsupportedJsonSchemaFeature(
        contract_json_schema_path_label(path),
        "external or non-pointer $ref",
      )
  }
  let mut current = root_schema
  for raw_token in pointer.split("/".view()) {
    let token = contract_decode_json_schema_pointer_token(
      raw_token.to_owned(),
      path,
    )
    current = match current {
      Object(object) =>
        match object.get(token) {
          Some(value) => value
          None =>
            raise InvalidJsonSchema(
              contract_json_schema_path_label(path) + ".$ref",
            )
        }
      _ =>
        raise InvalidJsonSchema(contract_json_schema_path_label(path) + ".$ref")
    }
  }
  current
}

///|
fn contract_decode_json_schema_pointer_token(
  token : String,
  path : String,
) -> String raise ContractError {
  let decoded = token
    .view()
    .replace_all(old="~1".view(), new="/".view())
    .replace_all(old="~0".view(), new="~".view())
    .to_owned()
  let encoded = decoded
    .view()
    .replace_all(old="~".view(), new="~0".view())
    .replace_all(old="/".view(), new="~1".view())
    .to_owned()
  if encoded != token {
    raise InvalidJsonSchema(contract_json_schema_path_label(path) + ".$ref")
  }
  decoded
}

///|
fn contract_validate_json_schema_definitions(
  keywords : Map[String, Json],
  path : String,
) -> Unit raise ContractError {
  for name in ["$defs", "definitions"] {
    match keywords.get(name) {
      Some(Object(_)) | None => ()
      Some(_) =>
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + "." + name,
        )
    }
  }
}

///|
fn contract_parse_json_schema_value_constraint(
  keywords : Map[String, Json],
  path : String,
) -> Json? raise ContractError {
  match keywords.get("enum") {
    Some(Array(values)) if values.length() > 0 => {
      for i = 0; i < values.length(); i = i + 1 {
        for j = i + 1; j < values.length(); j = j + 1 {
          if Json::equal(values[i], values[j]) {
            raise InvalidJsonSchema(
              contract_json_schema_path_label(path) + ".enum",
            )
          }
        }
      }
      ()
    }
    Some(_) =>
      raise InvalidJsonSchema(contract_json_schema_path_label(path) + ".enum")
    None => ()
  }
  ignore(contract_json_schema_number_keyword(keywords, "minimum", path))
  ignore(contract_json_schema_number_keyword(keywords, "maximum", path))
  ignore(
    contract_json_schema_number_keyword(keywords, "exclusiveMinimum", path),
  )
  ignore(
    contract_json_schema_number_keyword(keywords, "exclusiveMaximum", path),
  )
  for
    keyword in [
      "minItems", "maxItems", "minLength", "maxLength", "minProperties", "maxProperties",
    ] {
    ignore(contract_json_schema_count_keyword(keywords, keyword, path))
  }
  match keywords.get("pattern") {
    Some(String(_)) | None => ()
    Some(_) =>
      raise InvalidJsonSchema(
        contract_json_schema_path_label(path) + ".pattern",
      )
  }
  ignore(contract_json_schema_format_keyword(keywords, path))
  match contract_json_schema_number_keyword(keywords, "multipleOf", path) {
    Some(value) if value > 0.0 => ()
    Some(_) =>
      raise InvalidJsonSchema(
        contract_json_schema_path_label(path) + ".multipleOf",
      )
    None => ()
  }
  contract_validate_json_schema_dependent_required(keywords, path)
  let constraint_keywords : Map[String, Json] = Map([])
  for
    name in [
      "enum", "const", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
      "minItems", "maxItems", "minLength", "maxLength", "minProperties", "maxProperties",
      "pattern", "format", "multipleOf",
    ] {
    match keywords.get(name) {
      Some(value) => constraint_keywords.set(name, value)
      None => ()
    }
  }
  match keywords.get("uniqueItems") {
    Some(True) => constraint_keywords.set("uniqueItems", Json::boolean(true))
    Some(False) | None => ()
    Some(_) =>
      raise InvalidJsonSchema(
        contract_json_schema_path_label(path) + ".uniqueItems",
      )
  }
  match keywords.get("dependentRequired") {
    Some(value) => constraint_keywords.set("dependentRequired", value)
    None => ()
  }
  match keywords.get("propertyNames") {
    Some(value) =>
      constraint_keywords.set(
        "propertyNames",
        contract_validate_json_schema_property_names(
          value,
          contract_json_schema_path_label(path) + ".propertyNames",
        ),
      )
    None => ()
  }
  if constraint_keywords.is_empty() {
    None
  } else {
    Some(Json::object(constraint_keywords))
  }
}

///|
fn contract_validate_json_schema_dependent_required(
  keywords : Map[String, Json],
  path : String,
) -> Unit raise ContractError {
  match keywords.get("dependentRequired") {
    Some(Object(dependencies)) =>
      for (trigger, value) in dependencies {
        match value {
          Array(required_names) => {
            for i = 0; i < required_names.length(); i = i + 1 {
              for j = i + 1; j < required_names.length(); j = j + 1 {
                if Json::equal(required_names[i], required_names[j]) {
                  raise InvalidJsonSchema(
                    contract_json_schema_path_label(path) +
                    ".dependentRequired." +
                    trigger,
                  )
                }
              }
            }
            for name in required_names {
              match name {
                String(_) => ()
                _ =>
                  raise InvalidJsonSchema(
                    contract_json_schema_path_label(path) +
                    ".dependentRequired." +
                    trigger,
                  )
              }
            }
          }
          _ =>
            raise InvalidJsonSchema(
              contract_json_schema_path_label(path) +
              ".dependentRequired." +
              trigger,
            )
        }
      }
    Some(_) =>
      raise InvalidJsonSchema(
        contract_json_schema_path_label(path) + ".dependentRequired",
      )
    None => ()
  }
}

///|
fn contract_validate_json_schema_property_names(
  schema : Json,
  path : String,
) -> Json raise ContractError {
  match schema {
    True | False => schema
    Object(keywords) => {
      for (keyword, _) in keywords {
        if keyword != "type" &&
          keyword != "enum" &&
          keyword != "const" &&
          keyword != "pattern" &&
          keyword != "format" &&
          keyword != "minLength" &&
          keyword != "maxLength" &&
          !contract_json_schema_annotation_keyword_is_supported(keyword) {
          raise UnsupportedJsonSchemaFeature(path, keyword)
        }
      }
      match keywords.get("type") {
        Some(String(name)) => ignore(contract_json_schema_kind(name, path))
        Some(Array(_)) => raise UnsupportedJsonSchemaFeature(path, "type union")
        Some(_) => raise InvalidJsonSchema(path + ".type")
        None => ()
      }
      match keywords.get("pattern") {
        Some(String(_)) | None => ()
        Some(_) => raise InvalidJsonSchema(path + ".pattern")
      }
      ignore(contract_json_schema_format_keyword(keywords, path))
      ignore(contract_json_schema_count_keyword(keywords, "minLength", path))
      ignore(contract_json_schema_count_keyword(keywords, "maxLength", path))
      match keywords.get("enum") {
        Some(Array(values)) if values.length() > 0 => {
          for i = 0; i < values.length(); i = i + 1 {
            for j = i + 1; j < values.length(); j = j + 1 {
              if Json::equal(values[i], values[j]) {
                raise InvalidJsonSchema(path + ".enum")
              }
            }
          }
          schema
        }
        Some(_) => raise InvalidJsonSchema(path + ".enum")
        None => schema
      }
    }
    _ => raise InvalidJsonSchema(path)
  }
}

///|
fn contract_json_schema_number_keyword(
  keywords : Map[String, Json],
  keyword : String,
  path : String,
) -> Double? raise ContractError {
  match keywords.get(keyword) {
    Some(Number(value, ..)) => {
      let representation = value.to_string()
      if value == value &&
        representation != "Infinity" &&
        representation != "-Infinity" {
        Some(value)
      } else {
        raise InvalidJsonSchema(
          contract_json_schema_path_label(path) + "." + keyword,
        )
      }
    }
    Some(_) =>
      raise InvalidJsonSchema(
        contract_json_schema_path_label(path) + "." + keyword,
      )
    None => None
  }
}

///|
fn contract_json_schema_count_keyword(
  keywords : Map[String, Json],
  keyword : String,
  path : String,
) -> Double? raise ContractError {
  match contract_json_schema_number_keyword(keywords, keyword, path) {
    Some(value) if value >= 0.0 && value.floor() == value => Some(value)
    Some(_) =>
      raise InvalidJsonSchema(
        contract_json_schema_path_label(path) + "." + keyword,
      )
    None => None
  }
}

///|
fn contract_json_schema_format_keyword(
  keywords : Map[String, Json],
  path : String,
) -> String? raise ContractError {
  match keywords.get("format") {
    Some(String(format)) if contract_json_schema_format_is_supported(format) =>
      Some(format)
    Some(String(format)) =>
      raise UnsupportedJsonSchemaFeature(
        contract_json_schema_path_label(path),
        "format=" + format,
      )
    Some(_) =>
      raise InvalidJsonSchema(contract_json_schema_path_label(path) + ".format")
    None => None
  }
}

///|
fn contract_json_schema_kind(
  name : String,
  path : String,
) -> ContractKind raise ContractError {
  match name {
    "object" => ContractKind::Object
    "array" => ContractKind::Array
    "null" => ContractKind::Null
    "boolean" => ContractKind::Bool
    "number" | "integer" => ContractKind::Number
    "string" => ContractKind::String
    _ =>
      raise UnsupportedJsonSchemaFeature(
        contract_json_schema_path_label(path),
        "type=" + name,
      )
  }
}

///|
fn contract_json_schema_keyword_is_supported(keyword : String) -> Bool {
  match keyword {
    "type"
    | "properties"
    | "required"
    | "items"
    | "additionalProperties"
    | "propertyNames"
    | "dependentRequired"
    | "enum"
    | "const"
    | "minimum"
    | "maximum"
    | "exclusiveMinimum"
    | "exclusiveMaximum"
    | "minItems"
    | "maxItems"
    | "minLength"
    | "maxLength"
    | "minProperties"
    | "maxProperties"
    | "uniqueItems"
    | "pattern"
    | "format"
    | "multipleOf"
    | "$defs"
    | "definitions"
    | "$schema"
    | "$id"
    | "$anchor"
    | "$comment"
    | "title"
    | "description"
    | "default"
    | "examples"
    | "deprecated"
    | "readOnly"
    | "writeOnly" => true
    _ => false
  }
}

///|
fn contract_json_schema_annotation_keyword_is_supported(
  keyword : String,
) -> Bool {
  match keyword {
    "$schema"
    | "$id"
    | "$anchor"
    | "$comment"
    | "title"
    | "description"
    | "default"
    | "examples"
    | "deprecated"
    | "readOnly"
    | "writeOnly" => true
    _ => false
  }
}

///|
fn contract_add_open_object_path(paths : Array[String], path : String) -> Unit {
  if !paths.contains(path) {
    paths.push(path)
  }
}

///|
fn contract_json_schema_path_label(path : String) -> String {
  if path.length() == 0 {
    "$"
  } else {
    path
  }
}

///|
/// Convert a report to a stable JSON object for logs and CI integrations.
/// Each diagnostic contains `severity`, `code`, `source`, `path`,
/// `instance_path`, `expected`, `actual`, and `message` fields.
pub fn ContractReport::to_json(self : ContractReport) -> Json {
  let diagnostics : Array[Json] = []
  for diagnostic in self.diagnostics {
    let instance_path = match diagnostic.instance_path {
      Some(path) => Json::string(path)
      None => Json::null()
    }
    diagnostics.push(
      Json::object(
        Map([
          (
            "severity",
            Json::string(contract_severity_name(diagnostic.severity)),
          ),
          ("code", Json::string(contract_diagnostic_code_name(diagnostic.code))),
          ("source", Json::string(diagnostic.source)),
          ("path", Json::string(diagnostic.path)),
          ("instance_path", instance_path),
          ("expected", Json::string(diagnostic.expected)),
          ("actual", Json::string(diagnostic.actual)),
          ("message", Json::string(diagnostic.message)),
        ]),
      ),
    )
  }
  Json::object(
    Map([
      ("valid", Json::boolean(self.is_valid())),
      ("diagnostics", Json::array(diagnostics)),
    ]),
  )
}

///|
fn contract_severity_name(severity : ContractSeverity) -> String {
  match severity {
    ContractSeverity::Error => "error"
    ContractSeverity::Warning => "warning"
  }
}

///|
fn contract_diagnostic_code_name(code : ContractDiagnosticCode) -> String {
  match code {
    ContractDiagnosticCode::TemplateSyntax => "template_syntax"
    ContractDiagnosticCode::MissingPartial => "missing_partial"
    ContractDiagnosticCode::PartialCycle => "partial_cycle"
    ContractDiagnosticCode::UndeclaredTemplatePath => "undeclared_template_path"
    ContractDiagnosticCode::MissingRequiredField => "missing_required_field"
    ContractDiagnosticCode::TypeMismatch => "type_mismatch"
    ContractDiagnosticCode::ConstraintViolation => "constraint_violation"
    ContractDiagnosticCode::UnexpectedField => "unexpected_field"
    ContractDiagnosticCode::UnusedSchemaField => "unused_schema_field"
    ContractDiagnosticCode::NoSamples => "no_samples"
  }
}
