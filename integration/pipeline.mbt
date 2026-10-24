///|
fn order_template_schema() -> @contract.ContractSchema raise PipelineError {
  @contract.ContractSchema::from_json_schema({
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": false,
    "required": ["id", "title", "quantity"],
    "properties": {
      "id": { "type": "integer", "minimum": 0, "maximum": 9007199254740991 },
      "title": { "type": "string", "minLength": 1, "maxLength": 80 },
      "quantity": { "type": "integer", "minimum": 1, "maximum": 100 },
    },
  }) catch {
    _ => raise Rejected(stage="json_schema", path="")
  }
}

///|
fn conversion_path(error : ConversionError) -> String {
  match error {
    TypeMismatch(path~, ..)
    | InvalidValue(path~, ..)
    | MissingRequiredField(path~)
    | DuplicateField(path~)
    | FieldOccurrenceMismatch(path~, ..)
    | UnknownField(path~)
    | UnknownSymbol(path~, ..)
    | NullNotAllowed(path~)
    | AnnotatedValueNotSupported(path~) => path
  }
}

///|
/// ISL decoder is authoritative. A patch result must pass it again before
/// projection, template checking and rendering can produce any output.
pub fn render_order(value : @ion_model.IonValue) -> String raise PipelineError {
  ignore(Order::from_ion(value)) catch {
    error => raise Rejected(stage="isl", path=conversion_path(error))
  }
  let sample = project_for_template(value)
  let template = "Order {{id}}: {{title}} x{{quantity}}"
  let report = @contract.check_contract(
    template,
    order_template_schema(),
    sample,
  )
  if !report.is_valid() {
    raise Rejected(stage="template_contract", path=report.diagnostics[0].path)
  }
  @stencil.render(template, sample) catch {
    _ => raise Rejected(stage="render", path="")
  }
}

///|
pub fn run_pipeline() -> Json raise PipelineError {
  let before = @ion.parse_text("{id:42,title:\"MoonBit\",quantity:2}") catch {
    _ => raise Rejected(stage="parse_before", path="")
  }
  let after = @ion.parse_text("{id:42,title:\"MoonBit\",quantity:3}") catch {
    _ => raise Rejected(stage="parse_after", path="")
  }
  ignore(render_order(before[0]))
  let updated = try {
    let operations = @patch.diff(before[:], after[:])
    let updated = @patch.apply_checked(before[:], before[:], operations[:])
    let reverse = @patch.invert(before[:], operations[:])
    let restored = @patch.apply(updated[:], reverse[:])
    if !@patch.equal_values(restored[:], before[:]) ||
      !@patch.equal_values(updated[:], after[:]) {
      raise Rejected(stage="patch_invariant", path="")
    }
    updated
  } catch {
    Rejected(stage~, path~) => raise Rejected(stage~, path~)
    _ => raise Rejected(stage="patch", path="")
  }
  let output = render_order(updated[0])
  Json::object(
    Map([
      ("status", Json::string("passed")),
      ("output", Json::string(output)),
      ("inverse_restored", Json::boolean(true)),
    ]),
  )
}
