///|
fn main raise {
  let schema = @contract.ContractSchema::from_json_schema({
    "type": "object",
    "additionalProperties": false,
    "required": ["title", "status"],
    "properties": {
      "title": { "type": "string", "minLength": 1 },
      "status": { "enum": ["draft", "published"] },
    },
  })
  let template = "{{>summary}}"
  let partials = Map([("summary", "{{title}} — {{status}}")])

  let valid = @contract.check_contract_with_partials(
    template,
    partials,
    schema,
    { "title": "Stencil Contract", "status": "published" },
  )
  println("valid sample: " + valid.to_json().stringify())

  let invalid = @contract.check_contract_with_partials(
    template,
    partials,
    schema,
    { "title": "Stencil Contract", "status": "review" },
  )
  println("invalid sample: " + invalid.to_json().stringify())
}
