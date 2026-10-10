///|
/// Check a template and a sample JSON value against a schema.
pub fn check_contract(
  template : String,
  schema : ContractSchema,
  sample : Json,
) -> ContractReport {
  contract_check_one(
    template,
    Map([]),
    schema,
    sample,
    ContractPathMode::RootPaths,
  )
}

///|
/// Check a template using Stencil's nested section and fallback lookup scopes.
/// Fields inside object and array sections are resolved relative to that scope.
pub fn check_contract_with_context(
  template : String,
  schema : ContractSchema,
  sample : Json,
) -> ContractReport {
  contract_check_one(
    template,
    Map([]),
    schema,
    sample,
    ContractPathMode::ContextAware,
  )
}

///|
/// Check a template, its reachable named partials, and a sample JSON value.
pub fn check_contract_with_partials(
  template : String,
  partials : Map[String, String],
  schema : ContractSchema,
  sample : Json,
) -> ContractReport {
  contract_check_one(
    template,
    partials,
    schema,
    sample,
    ContractPathMode::RootPaths,
  )
}

///|
/// Check a template and its reachable partials using Stencil's current context
/// for section-local lookups. Partials inherit the context at their call site.
pub fn check_contract_with_partials_and_context(
  template : String,
  partials : Map[String, String],
  schema : ContractSchema,
  sample : Json,
) -> ContractReport {
  contract_check_one(
    template,
    partials,
    schema,
    sample,
    ContractPathMode::ContextAware,
  )
}

///|
/// Check one template against multiple sample values.
/// Template and reachable partials are analyzed once. Sample diagnostics use
/// `sample[index]` as their source, with zero-based input indices.
pub fn check_contract_samples(
  template : String,
  partials : Map[String, String],
  schema : ContractSchema,
  samples : Array[Json],
  path_mode : ContractPathMode,
) -> ContractReport {
  contract_check_many(template, partials, schema, samples, path_mode, true)
}

///|
fn contract_check_one(
  template : String,
  partials : Map[String, String],
  schema : ContractSchema,
  sample : Json,
  path_mode : ContractPathMode,
) -> ContractReport {
  contract_check_many(template, partials, schema, [sample], path_mode, false)
}

///|
fn contract_check_many(
  template : String,
  partials : Map[String, String],
  schema : ContractSchema,
  samples : Array[Json],
  path_mode : ContractPathMode,
  indexed_sample_sources : Bool,
) -> ContractReport {
  let context_aware = match path_mode {
    ContractPathMode::RootPaths => false
    ContractPathMode::ContextAware => true
  }
  let diagnostics : Array[ContractDiagnostic] = []
  let references : Array[TemplateReference] = []
  let visited_partials : Array[String] = []
  let active_partials : Array[String] = []
  contract_walk_source(
    "template",
    template,
    partials,
    active_partials,
    visited_partials,
    references,
    diagnostics,
    [""],
    context_aware,
    schema,
  )

  let used_paths : Array[String] = []
  for reference in references {
    let resolved_paths = if context_aware {
      contract_resolve_reference(schema, reference.scopes, reference.path)
    } else if contract_schema_has_field(schema, reference.path) {
      [reference.path]
    } else {
      []
    }
    if resolved_paths.length() == 0 {
      contract_add_diagnostic(
        diagnostics,
        ContractSeverity::Error,
        ContractDiagnosticCode::UndeclaredTemplatePath,
        reference.source,
        reference.path,
        "declared schema path",
        "",
        "template path is not declared in schema: \{reference.path}",
      )
    } else {
      for resolved_path in resolved_paths {
        if !used_paths.contains(resolved_path) {
          used_paths.push(resolved_path)
        }
      }
    }
  }
  for field in schema.fields {
    let mut field_is_used = false
    for used_path in used_paths {
      if used_path == field.path ||
        contract_path_is_descendant(used_path, field.path) {
        field_is_used = true
      }
    }
    if !field_is_used {
      contract_add_diagnostic(
        diagnostics,
        ContractSeverity::Warning,
        ContractDiagnosticCode::UnusedSchemaField,
        "schema",
        field.path,
        "template reference",
        "",
        "schema field is not referenced by the template: \{field.path}",
      )
    }
  }

  let sample_indices : Map[String, Int] = Map([])
  if samples.length() == 0 {
    contract_add_diagnostic(
      diagnostics,
      ContractSeverity::Error,
      ContractDiagnosticCode::NoSamples,
      "samples",
      "",
      "at least one sample",
      "0",
      "at least one sample is required",
    )
  }
  for i in 0..<samples.length() {
    let sample_source = if indexed_sample_sources {
      "sample[" + i.to_string() + "]"
    } else {
      "sample"
    }
    sample_indices.set(sample_source, i)
    contract_validate_sample(schema, samples[i], sample_source, diagnostics)
  }
  diagnostics.sort_by((left, right) => {
    contract_compare_diagnostics(left, right, sample_indices)
  })
  { diagnostics, }
}

///|
fn contract_compare_diagnostics(
  left : ContractDiagnostic,
  right : ContractDiagnostic,
  sample_indices : Map[String, Int],
) -> Int {
  let left_group = contract_diagnostic_group(left.code)
  let right_group = contract_diagnostic_group(right.code)
  let group_order = contract_compare_int(left_group, right_group)
  if group_order != 0 {
    return group_order
  }
  if left_group == 0 {
    let source_order = contract_compare_strings(left.source, right.source)
    if source_order != 0 {
      return source_order
    }
  } else if left_group == 1 {
    let path_order = contract_compare_strings(left.path, right.path)
    if path_order != 0 {
      return path_order
    }
  } else {
    let left_index = contract_diagnostic_sample_index(
      left.source,
      sample_indices,
    )
    let right_index = contract_diagnostic_sample_index(
      right.source,
      sample_indices,
    )
    let index_order = contract_compare_int(left_index, right_index)
    if index_order != 0 {
      return index_order
    }
  }
  let path_order = contract_compare_strings(left.path, right.path)
  if path_order != 0 {
    return path_order
  }
  let instance_path_order = contract_compare_optional_strings(
    left.instance_path,
    right.instance_path,
  )
  if instance_path_order != 0 {
    return instance_path_order
  }
  let code_order = contract_compare_int(
    contract_diagnostic_code_rank(left.code),
    contract_diagnostic_code_rank(right.code),
  )
  if code_order != 0 {
    return code_order
  }
  let expected_order = contract_compare_strings(left.expected, right.expected)
  if expected_order != 0 {
    return expected_order
  }
  let actual_order = contract_compare_strings(left.actual, right.actual)
  if actual_order != 0 {
    return actual_order
  }
  let source_order = contract_compare_strings(left.source, right.source)
  if source_order != 0 {
    return source_order
  }
  let severity_order = contract_compare_int(
    contract_diagnostic_severity_rank(left.severity),
    contract_diagnostic_severity_rank(right.severity),
  )
  if severity_order != 0 {
    return severity_order
  }
  contract_compare_strings(left.message, right.message)
}

///|
fn contract_diagnostic_group(code : ContractDiagnosticCode) -> Int {
  match code {
    ContractDiagnosticCode::TemplateSyntax
    | ContractDiagnosticCode::MissingPartial
    | ContractDiagnosticCode::PartialCycle
    | ContractDiagnosticCode::UndeclaredTemplatePath => 0
    ContractDiagnosticCode::UnusedSchemaField => 1
    ContractDiagnosticCode::MissingRequiredField
    | ContractDiagnosticCode::TypeMismatch
    | ContractDiagnosticCode::ConstraintViolation
    | ContractDiagnosticCode::UnexpectedField
    | ContractDiagnosticCode::NoSamples => 2
  }
}

///|
fn contract_diagnostic_code_rank(code : ContractDiagnosticCode) -> Int {
  match code {
    ContractDiagnosticCode::TemplateSyntax => 0
    ContractDiagnosticCode::MissingPartial => 1
    ContractDiagnosticCode::PartialCycle => 2
    ContractDiagnosticCode::UndeclaredTemplatePath => 3
    ContractDiagnosticCode::MissingRequiredField => 4
    ContractDiagnosticCode::TypeMismatch => 5
    ContractDiagnosticCode::ConstraintViolation => 6
    ContractDiagnosticCode::UnexpectedField => 7
    ContractDiagnosticCode::UnusedSchemaField => 8
    ContractDiagnosticCode::NoSamples => 9
  }
}

///|
fn contract_diagnostic_severity_rank(severity : ContractSeverity) -> Int {
  match severity {
    ContractSeverity::Error => 0
    ContractSeverity::Warning => 1
  }
}

///|
fn contract_diagnostic_sample_index(
  source : String,
  sample_indices : Map[String, Int],
) -> Int {
  match sample_indices.get(source) {
    Some(index) => index
    None => -1
  }
}

///|
fn contract_compare_int(left : Int, right : Int) -> Int {
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
fn contract_compare_strings(left : String, right : String) -> Int {
  left.view().lexical_compare(right.view())
}

///|
fn contract_compare_optional_strings(left : String?, right : String?) -> Int {
  match (left, right) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(left_value), Some(right_value)) =>
      contract_compare_strings(left_value, right_value)
  }
}

///|
fn contract_walk_source(
  source_name : String,
  source : String,
  partials : Map[String, String],
  active_partials : Array[String],
  visited_partials : Array[String],
  references : Array[TemplateReference],
  diagnostics : Array[ContractDiagnostic],
  scopes : Array[String],
  context_aware : Bool,
  schema : ContractSchema,
) -> Unit {
  try {
    let nodes = @stencil.parse(@stencil.scan(source))
    contract_walk_nodes(
      source_name, nodes, partials, active_partials, visited_partials, references,
      diagnostics, scopes, context_aware, schema,
    )
  } catch {
    @stencil.TemplateError(message) =>
      contract_add_diagnostic(
        diagnostics,
        ContractSeverity::Error,
        ContractDiagnosticCode::TemplateSyntax,
        source_name,
        "",
        "valid Stencil template",
        "",
        "template parse failed in \{source_name}: \{message}",
      )
  }
}

///|
fn contract_walk_nodes(
  source_name : String,
  nodes : Array[@stencil.Node],
  partials : Map[String, String],
  active_partials : Array[String],
  visited_partials : Array[String],
  references : Array[TemplateReference],
  diagnostics : Array[ContractDiagnostic],
  scopes : Array[String],
  context_aware : Bool,
  schema : ContractSchema,
) -> Unit {
  for node in nodes {
    match node {
      @stencil.TextNode(_) => ()
      @stencil.VarNode(path, _) =>
        if path != "." {
          contract_add_reference(references, source_name, path, scopes)
        }
      @stencil.SectionNode(path, children, inverted) => {
        if path != "." {
          contract_add_reference(references, source_name, path, scopes)
        }
        let child_scopes = if context_aware && !inverted {
          contract_section_scopes(schema, scopes, path)
        } else {
          scopes
        }
        contract_walk_nodes(
          source_name, children, partials, active_partials, visited_partials, references,
          diagnostics, child_scopes, context_aware, schema,
        )
      }
      @stencil.PartialNode(name, _) =>
        if active_partials.contains(name) {
          contract_add_diagnostic(
            diagnostics,
            ContractSeverity::Error,
            ContractDiagnosticCode::PartialCycle,
            source_name,
            name,
            "acyclic partial graph",
            name,
            "partial cycle detected: \{name}",
          )
        } else if context_aware || !visited_partials.contains(name) {
          match partials.get(name) {
            Some(partial_source) => {
              active_partials.push(name)
              contract_walk_source(
                name, partial_source, partials, active_partials, visited_partials,
                references, diagnostics, scopes, context_aware, schema,
              )
              ignore(active_partials.pop())
              if !visited_partials.contains(name) {
                visited_partials.push(name)
              }
            }
            None =>
              contract_add_diagnostic(
                diagnostics,
                ContractSeverity::Error,
                ContractDiagnosticCode::MissingPartial,
                source_name,
                name,
                "registered partial",
                "missing",
                "missing partial: \{name}",
              )
          }
        }
    }
  }
}

///|
fn contract_schema_has_field(schema : ContractSchema, path : String) -> Bool {
  for field in schema.fields {
    if field.path == path ||
      contract_path_is_descendant(field.path, path) ||
      (
        contract_kinds_equal(field.kind, ContractKind::Any) &&
        contract_path_is_descendant(path, field.path)
      ) {
      return true
    }
  }
  false
}

///|
fn contract_resolve_reference(
  schema : ContractSchema,
  scopes : Array[String],
  path : String,
) -> Array[String] {
  let matches : Array[String] = []
  if path == "." {
    for scope in scopes {
      matches.push(scope)
    }
    return matches
  }
  for scope in scopes {
    let candidate = contract_join_path(scope, path)
    if contract_schema_has_field(schema, candidate) &&
      !matches.contains(candidate) {
      matches.push(candidate)
      if contract_schema_path_is_guaranteed_non_null(schema, candidate) {
        break
      }
    }
  }
  matches
}

///|
fn contract_schema_path_is_guaranteed_non_null(
  schema : ContractSchema,
  path : String,
) -> Bool {
  match contract_schema_get_field(schema, path) {
    Some(field) =>
      field.required &&
      !contract_kinds_equal(field.kind, ContractKind::Null) &&
      !contract_kinds_equal(field.kind, ContractKind::Any)
    None => {
      for field in schema.fields {
        if field.required && contract_path_is_descendant(field.path, path) {
          return true
        }
      }
      false
    }
  }
}

///|
fn contract_section_scopes(
  schema : ContractSchema,
  scopes : Array[String],
  path : String,
) -> Array[String] {
  let child_scopes : Array[String] = []
  for candidate in contract_resolve_reference(schema, scopes, path) {
    for child_scope in contract_section_child_scopes(schema, candidate) {
      if !child_scopes.contains(child_scope) {
        child_scopes.push(child_scope)
      }
    }
  }
  for scope in scopes {
    if !child_scopes.contains(scope) {
      child_scopes.push(scope)
    }
  }
  child_scopes
}

///|
fn contract_section_child_scopes(
  schema : ContractSchema,
  path : String,
) -> Array[String] {
  match contract_schema_get_field(schema, path) {
    Some(field) =>
      match field.kind {
        ContractKind::Object => [path]
        ContractKind::Array => {
          let item_path = path + "[]"
          match contract_schema_get_field(schema, item_path) {
            Some(item) if contract_kinds_equal(item.kind, ContractKind::Object) =>
              [item_path]
            Some(item) if contract_kinds_equal(item.kind, ContractKind::Any) =>
              [item_path]
            Some(item) if contract_kinds_equal(item.kind, ContractKind::Array) =>
              [item_path]
            Some(_) =>
              if contract_schema_has_path_or_descendant(schema, item_path) {
                [item_path]
              } else {
                []
              }
            None =>
              if contract_schema_has_path_or_descendant(schema, item_path) {
                [item_path]
              } else {
                []
              }
          }
        }
        ContractKind::Any => [path, path + "[]"]
        _ => []
      }
    None => {
      let result : Array[String] = []
      let item_path = path + "[]"
      if contract_schema_has_path_or_descendant(schema, item_path) {
        result.push(item_path)
      }
      if contract_schema_has_dotted_child(schema, path) {
        result.push(path)
      }
      result
    }
  }
}

///|
fn contract_schema_has_dotted_child(
  schema : ContractSchema,
  path : String,
) -> Bool {
  let prefix = path + "."
  for field in schema.fields {
    if field.path.view().has_prefix(prefix.view()) {
      return true
    }
  }
  false
}

///|
fn contract_string_arrays_equal(
  left : Array[String],
  right : Array[String],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i = 0; i < left.length(); i = i + 1 {
    if left[i] != right[i] {
      return false
    }
  }
  true
}

///|
fn contract_add_reference(
  references : Array[TemplateReference],
  source : String,
  path : String,
  scopes : Array[String],
) -> Unit {
  for existing in references {
    if existing.source == source &&
      existing.path == path &&
      contract_string_arrays_equal(existing.scopes, scopes) {
      return
    }
  }
  let copied_scopes : Array[String] = []
  for scope in scopes {
    copied_scopes.push(scope)
  }
  references.push({ source, path, scopes: copied_scopes, })
}

///|
fn contract_schema_get_field(
  schema : ContractSchema,
  path : String,
) -> ContractField? {
  for field in schema.fields {
    if field.path == path {
      return Some(field)
    }
  }
  None
}

///|
fn contract_validate_sample(
  schema : ContractSchema,
  sample : Json,
  source : String,
  diagnostics : Array[ContractDiagnostic],
) -> Unit {
  contract_validate_value_constraints(
    schema, "", sample, "", source, diagnostics,
  )
  match sample {
    Object(_) => {
      for field in schema.fields {
        let parts = parse_contract_path(field.path).unwrap()
        contract_validate_field(
          sample, parts, 0, "", "", field, schema, source, diagnostics,
        )
      }
      contract_validate_extra_fields(
        sample, "", "", schema, source, diagnostics,
      )
    }
    _ =>
      contract_add_diagnostic_at(
        diagnostics,
        ContractSeverity::Error,
        ContractDiagnosticCode::TypeMismatch,
        source,
        "",
        Some(""),
        "Object",
        contract_json_kind_name(sample),
        "sample root must be an Object",
      )
  }
}

///|
fn contract_validate_field(
  current : Json,
  parts : Array[ContractPathPart],
  index : Int,
  schema_prefix : String,
  instance_path : String,
  field : ContractField,
  schema : ContractSchema,
  source : String,
  diagnostics : Array[ContractDiagnostic],
) -> Unit {
  if index >= parts.length() {
    return
  }
  match current {
    Object(map) => {
      let part = parts[index]
      let key_path = contract_join_path(schema_prefix, part.key)
      let key_instance_path = contract_json_pointer_member(
        instance_path,
        part.key,
      )
      match map.get(part.key) {
        None => {
          let is_leaf = index == parts.length() - 1
          let parent_field = contract_schema_get_field(schema, key_path)
          if field.required &&
            ((part.array_depth == 0 && is_leaf) || parent_field is None) {
            contract_add_diagnostic_at(
              diagnostics,
              ContractSeverity::Error,
              ContractDiagnosticCode::MissingRequiredField,
              source,
              field.path,
              Some(key_instance_path),
              "present",
              "missing",
              "required sample path is missing: \{field.path}",
            )
          }
        }
        Some(value) =>
          contract_validate_path_value(
            value,
            parts,
            index,
            part.array_depth,
            key_path,
            key_instance_path,
            field,
            schema,
            source,
            diagnostics,
          )
      }
    }
    _ =>
      if contract_schema_get_field(schema, schema_prefix) is None {
        contract_add_diagnostic_at(
          diagnostics,
          ContractSeverity::Error,
          ContractDiagnosticCode::TypeMismatch,
          source,
          schema_prefix,
          Some(instance_path),
          "Object",
          contract_json_kind_name(current),
          "expected Object, got \{contract_json_kind_name(current)} at \{schema_prefix}",
        )
      }
  }
}

///|
fn contract_validate_path_value(
  value : Json,
  parts : Array[ContractPathPart],
  index : Int,
  array_depth : Int,
  schema_path : String,
  instance_path : String,
  field : ContractField,
  schema : ContractSchema,
  source : String,
  diagnostics : Array[ContractDiagnostic],
) -> Unit {
  contract_validate_value_constraints(
    schema, schema_path, value, instance_path, source, diagnostics,
  )
  if array_depth > 0 {
    match value {
      Array(items) => {
        let item_schema_path = schema_path + "[]"
        for item_index, item in items {
          contract_validate_path_value(
            item,
            parts,
            index,
            array_depth - 1,
            item_schema_path,
            contract_json_pointer_index(instance_path, item_index),
            field,
            schema,
            source,
            diagnostics,
          )
        }
      }
      _ =>
        if contract_schema_get_field(schema, schema_path) is None {
          contract_add_diagnostic_at(
            diagnostics,
            ContractSeverity::Error,
            ContractDiagnosticCode::TypeMismatch,
            source,
            schema_path,
            Some(instance_path),
            "Array",
            contract_json_kind_name(value),
            "expected Array, got \{contract_json_kind_name(value)} at \{schema_path}",
          )
        }
    }
  } else if index == parts.length() - 1 {
    if !contract_kind_matches(field.kind, value) {
      contract_add_diagnostic_at(
        diagnostics,
        ContractSeverity::Error,
        ContractDiagnosticCode::TypeMismatch,
        source,
        schema_path,
        Some(instance_path),
        contract_kind_name(field.kind),
        contract_json_kind_name(value),
        "expected \{contract_kind_name(field.kind)}, got \{contract_json_kind_name(value)} at \{schema_path}",
      )
    }
  } else {
    match value {
      Object(_) =>
        contract_validate_field(
          value,
          parts,
          index + 1,
          schema_path,
          instance_path,
          field,
          schema,
          source,
          diagnostics,
        )
      _ =>
        if contract_schema_get_field(schema, schema_path) is None {
          contract_add_diagnostic_at(
            diagnostics,
            ContractSeverity::Error,
            ContractDiagnosticCode::TypeMismatch,
            source,
            schema_path,
            Some(instance_path),
            "Object",
            contract_json_kind_name(value),
            "expected Object, got \{contract_json_kind_name(value)} at \{schema_path}",
          )
        }
    }
  }
}

///|
fn contract_validate_value_constraints(
  schema : ContractSchema,
  schema_path : String,
  value : Json,
  instance_path : String,
  source : String,
  diagnostics : Array[ContractDiagnostic],
) -> Unit {
  for (constraint_path, constraint_json) in schema.value_constraints {
    if constraint_path == schema_path {
      match constraint_json {
        Object(keywords) => {
          match keywords.get("enum") {
            Some(Array(values)) => {
              let mut matches = false
              for allowed in values {
                if Json::equal(value, allowed) {
                  matches = true
                }
              }
              if !matches {
                contract_add_constraint_violation(
                  source,
                  schema_path,
                  instance_path,
                  "one of " + Json::array(values).stringify(),
                  value.stringify(),
                  "value is not in the allowed enum at \{schema_path}",
                  diagnostics,
                )
              }
            }
            _ => ()
          }

          match keywords.get("const") {
            Some(expected) if !Json::equal(value, expected) =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "equal to " + expected.stringify(),
                value.stringify(),
                "value does not match const at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("minimum")) {
            (Number(actual, ..), Some(Number(minimum, ..))) if actual < minimum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                ">= " + minimum.to_string(),
                actual.to_string(),
                "number is below minimum at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("maximum")) {
            (Number(actual, ..), Some(Number(maximum, ..))) if actual > maximum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "<= " + maximum.to_string(),
                actual.to_string(),
                "number is above maximum at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("exclusiveMinimum")) {
            (Number(actual, ..), Some(Number(minimum, ..))) if actual <= minimum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "> " + minimum.to_string(),
                actual.to_string(),
                "number does not exceed exclusive minimum at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("exclusiveMaximum")) {
            (Number(actual, ..), Some(Number(maximum, ..))) if actual >= maximum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "< " + maximum.to_string(),
                actual.to_string(),
                "number does not meet exclusive maximum at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("minItems")) {
            (Array(items), Some(Number(minimum, ..))) if items
              .length()
              .to_double() <
              minimum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "at least \{minimum.to_string()} items",
                "\{items.length()} items",
                "array has fewer than minItems at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("maxItems")) {
            (Array(items), Some(Number(maximum, ..))) if items
              .length()
              .to_double() >
              maximum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "at most \{maximum.to_string()} items",
                "\{items.length()} items",
                "array has more than maxItems at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("minLength")) {
            (String(text), Some(Number(minimum, ..))) if text
              .char_length()
              .to_double() <
              minimum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "at least \{minimum.to_string()} characters",
                "\{text.char_length()} characters",
                "string is shorter than minLength at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("maxLength")) {
            (String(text), Some(Number(maximum, ..))) if text
              .char_length()
              .to_double() >
              maximum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "at most \{maximum.to_string()} characters",
                "\{text.char_length()} characters",
                "string is longer than maxLength at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("minProperties")) {
            (Object(properties), Some(Number(minimum, ..))) if properties
              .length()
              .to_double() <
              minimum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "at least \{minimum.to_string()} properties",
                "\{properties.length()} properties",
                "object has fewer than minProperties at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("maxProperties")) {
            (Object(properties), Some(Number(maximum, ..))) if properties
              .length()
              .to_double() >
              maximum =>
              contract_add_constraint_violation(
                source,
                schema_path,
                instance_path,
                "at most \{maximum.to_string()} properties",
                "\{properties.length()} properties",
                "object has more than maxProperties at \{schema_path}",
                diagnostics,
              )
            _ => ()
          }
          match (value, keywords.get("uniqueItems")) {
            (Array(items), Some(True)) =>
              for i = 0; i < items.length(); i = i + 1 {
                for j = i + 1; j < items.length(); j = j + 1 {
                  if Json::equal(items[i], items[j]) {
                    contract_add_constraint_violation(
                      source,
                      schema_path,
                      contract_json_pointer_index(instance_path, j),
                      "unique item",
                      items[j].stringify(),
                      "array contains a duplicate item at \{schema_path}",
                      diagnostics,
                    )
                  }
                }
              }
            _ => ()
          }
        }
        _ => ()
      }
    }
  }
}

///|
fn contract_add_constraint_violation(
  source : String,
  path : String,
  instance_path : String,
  expected : String,
  actual : String,
  message : String,
  diagnostics : Array[ContractDiagnostic],
) -> Unit {
  contract_add_diagnostic_at(
    diagnostics,
    ContractSeverity::Error,
    ContractDiagnosticCode::ConstraintViolation,
    source,
    path,
    Some(instance_path),
    expected,
    actual,
    message,
  )
}

///|
fn contract_validate_extra_fields(
  value : Json,
  schema_prefix : String,
  instance_path : String,
  schema : ContractSchema,
  source : String,
  diagnostics : Array[ContractDiagnostic],
) -> Unit {
  match value {
    Object(map) =>
      map.each((key, child) => {
        let child_path = contract_join_path(schema_prefix, key)
        let child_instance_path = contract_json_pointer_member(
          instance_path, key,
        )
        if contract_schema_has_path_or_descendant(schema, child_path) {
          match contract_schema_get_field(schema, child_path) {
            Some(field) if contract_kinds_equal(field.kind, ContractKind::Any) =>
              ()
            _ =>
              contract_validate_extra_fields(
                child, child_path, child_instance_path, schema, source, diagnostics,
              )
          }
        } else if schema.open_object_paths.contains(schema_prefix) {
          ()
        } else {
          contract_add_diagnostic_at(
            diagnostics,
            ContractSeverity::Error,
            ContractDiagnosticCode::UnexpectedField,
            source,
            child_path,
            Some(child_instance_path),
            "declared schema path",
            "present",
            "sample contains undeclared field: \{child_path}",
          )
        }
      })
    Array(items) => {
      let item_path = schema_prefix + "[]"
      for item_index, item in items {
        match contract_schema_get_field(schema, item_path) {
          Some(field) if contract_kinds_equal(field.kind, ContractKind::Any) =>
            ()
          _ =>
            contract_validate_extra_fields(
              item,
              item_path,
              contract_json_pointer_index(instance_path, item_index),
              schema,
              source,
              diagnostics,
            )
        }
      }
    }
    _ => ()
  }
}

///|
fn contract_schema_has_path_or_descendant(
  schema : ContractSchema,
  path : String,
) -> Bool {
  for field in schema.fields {
    if field.path == path || contract_path_is_descendant(field.path, path) {
      return true
    }
  }
  false
}

///|
fn contract_path_is_descendant(path : String, parent : String) -> Bool {
  if path.length() <= parent.length() {
    return false
  }
  if !path.view().has_prefix(parent.view()) {
    return false
  }
  match path.view().strip_prefix(parent.view()) {
    Some(remaining) =>
      match remaining.get_char(0) {
        Some('.') => true
        Some('[') => remaining.has_prefix("[]".view())
        _ => false
      }
    None => false
  }
}

///|
fn contract_json_pointer_member(parent : String, key : String) -> String {
  let escaped = key
    .view()
    .replace_all(old="~".view(), new="~0".view())
    .replace_all(old="/".view(), new="~1".view())
    .to_owned()
  parent + "/" + escaped
}

///|
fn contract_json_pointer_index(parent : String, index : Int) -> String {
  parent + "/" + index.to_string()
}

///|
fn contract_add_diagnostic(
  diagnostics : Array[ContractDiagnostic],
  severity : ContractSeverity,
  code : ContractDiagnosticCode,
  source : String,
  path : String,
  expected : String,
  actual : String,
  message : String,
) -> Unit {
  contract_add_diagnostic_at(
    diagnostics,
    severity,
    code,
    source,
    path,
    None,
    expected,
    actual,
    message,
  )
}

///|
fn contract_add_diagnostic_at(
  diagnostics : Array[ContractDiagnostic],
  severity : ContractSeverity,
  code : ContractDiagnosticCode,
  source : String,
  path : String,
  instance_path : String?,
  expected : String,
  actual : String,
  message : String,
) -> Unit {
  for existing in diagnostics {
    if contract_severities_equal(existing.severity, severity) &&
      contract_codes_equal(existing.code, code) &&
      existing.source == source &&
      existing.path == path &&
      contract_compare_optional_strings(existing.instance_path, instance_path) ==
      0 &&
      existing.expected == expected &&
      existing.actual == actual {
      return
    }
  }
  diagnostics.push({
    severity,
    code,
    source,
    path,
    instance_path,
    expected,
    actual,
    message,
  })
}
