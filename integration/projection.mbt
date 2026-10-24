///|
pub(all) suberror PipelineError {
  Rejected(stage~ : String, path~ : String)
}

///|
/// Project only the explicitly supported, lossless JSON-compatible Ion domain.
pub fn project_for_template(
  value : @ion_model.IonValue,
) -> Json raise PipelineError {
  project_value(value, "")
}

///|
fn projection_path(parent : String, key : String) -> String {
  parent +
  "/" +
  key
  .view()
  .replace_all(old="~".view(), new="~0".view())
  .replace_all(old="/".view(), new="~1".view())
  .to_owned()
}

///|
fn project_value(
  value : @ion_model.IonValue,
  path : String,
) -> Json raise PipelineError {
  if value.annotations().length() > 0 {
    raise Rejected(stage="projection:annotations", path~)
  }
  match value {
    @ion_model.IonValue::Null(@ion_model.IonNull::Null) => Json::null()
    @ion_model.IonValue::Bool(value) => Json::boolean(value)
    @ion_model.IonValue::String(value) => Json::string(value)
    @ion_model.IonValue::Int(value) => {
      let limit = @bigint.BigInt::from_string("9007199254740991")
      if value < -limit || value > limit {
        raise Rejected(stage="projection:unsafe_integer", path~)
      }
      @contract.parse_contract_json(value.to_string()) catch {
        _ => raise Rejected(stage="projection:number", path~)
      }
    }
    @ion_model.IonValue::List(values) => {
      let items : Array[Json] = []
      for i in 0..<values.length() {
        items.push(
          project_value(values[i], projection_path(path, i.to_string())),
        )
      }
      Json::array(items)
    }
    @ion_model.IonValue::Struct(fields) => {
      let members : Map[String, Json] = Map([])
      for (symbol, value) in fields {
        let name = match symbol.text_value() {
          Some(name) => name
          None => raise Rejected(stage="projection:unresolved_symbol", path~)
        }
        let field_path = projection_path(path, name)
        if members.contains(name) {
          raise Rejected(stage="projection:duplicate_field", path=field_path)
        }
        members.set(name, project_value(value, field_path))
      }
      Json::object(members)
    }
    _ => raise Rejected(stage="projection:unsupported_ion_kind", path~)
  }
}
