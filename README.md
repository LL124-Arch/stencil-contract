# stencil-contract

MoonBit package for checking data contracts used by Stencil templates and partials. It checks template paths against an explicit schema, validates a sample JSON value, and reports missing or cyclic partials.

Rendering is provided by `LL124-Arch/stencil`.
The checker is implemented in MoonBit and uses the Stencil package for template
analysis. JSON Schema import supports the documented subset and returns an
error for unsupported validation keywords instead of silently ignoring them.
The project is licensed under Apache-2.0; see `LICENSE`.

## Define a contract

Schema paths use dots for object fields and repeat `[]` for each array level. For example, `matrix[][]` validates every value inside each inner array, while `matrix[][].name` validates a property on each object at that level. Declared parents must match the path structure (`Array` for each array level and `Object` before a nested field). `required` checks for a containing property and never requires arrays to be non-empty. Any undeclared sample fields are errors, including keys inside nested arrays. Use an `Any` declaration for an arbitrary value and its contents.

```moonbit
import {
  "LL124-Arch/stencil-contract" @contract,
}

let schema = @contract.ContractSchema::new([
  { path: "title", kind: @contract.ContractKind::String, required: true },
  { path: "profile", kind: @contract.ContractKind::Object, required: true },
  { path: "profile.name", kind: @contract.ContractKind::String, required: true },
  { path: "users", kind: @contract.ContractKind::Array, required: true },
  { path: "users[]", kind: @contract.ContractKind::Object, required: false },
  { path: "users[].name", kind: @contract.ContractKind::String, required: true },
])

let report = @contract.check_contract(
  "{{title}} — {{profile.name}}",
  schema,
  {
    "title": "Team",
    "profile": { "name": "Ada" },
    "users": [{ "name": "Lin" }],
  },
)
if !report.is_valid() {
  for diagnostic in report.diagnostics {
    println(diagnostic.message)
  }
}
```

Use `check_contract_with_partials(template, partials, schema, sample)` to include named partial sources. The checker follows partials reachable from the root template, detects missing references and cycles, and reports source names and field paths. This API treats every template path literally from the root. `{{.}}` is skipped by template-path matching.

```moonbit
import {
  "LL124-Arch/stencil-contract" @contract,
}

let partial_schema = @contract.ContractSchema::new([
  { path: "title", kind: @contract.ContractKind::String, required: true },
])
let partials = Map([("heading", "{{title}}")])
let partial_report = @contract.check_contract_with_partials(
  "{{>heading}}",
  partials,
  partial_schema,
  { "title": "Team" },
)
```

Import a supported JSON Schema directly with `ContractSchema::from_json_schema`.
The importer flattens `properties`, `required`, primitive `type`, nested array
`items`, boolean `additionalProperties`, `propertyNames`, and
`dependentRequired` into the contract checks below.
JSON Schema's default `additionalProperties: true` is preserved per object;
`false` rejects undeclared keys. `integer` maps to `Number`. Acyclic local
JSON Pointer references into `$defs` or `definitions` are expanded at each
use site, including references inside array `items`. Pointer tokens decode
`~1` and `~0` for `/` and `~`. External or recursive references and validation
keywords next to `$ref` return `ContractError`. Nested `$id` resource scopes
are also rejected because they change how relative references resolve. The
importer checks `enum`, `const`, numeric `minimum`/`maximum`, exclusive
bounds and `multipleOf`, array `minItems`/`maxItems` and `uniqueItems`, string
`minLength`/`maxLength`, `pattern`, and the `date`, `time`, `date-time`, and
`uuid` formats, and object `minProperties`/`maxProperties`.
String lengths count Unicode code points. `multipleOf` uses decimal integer
arithmetic to avoid binary floating-point remainder errors. `pattern` uses
MoonBit core's `Regex` syntax; patterns that the engine cannot compile return
`ContractError`. Patterns are searched within the string unless anchored with
`^` or `$`. A failed assertion produces a `constraint_violation` diagnostic
with the schema path and concrete instance path. Formats use RFC 3339 date/time
syntax and the hyphenated UUID text layout; unsupported formats such as
`email` and `uri` return `ContractError`. Other constraints such as
`patternProperties` and schema-composition keywords also return `ContractError`
instead of being discarded. The recognized formats are enforced as assertions
by this checker. `propertyNames` supports boolean schemas and the
string `type`, `enum`, `const`, `pattern`, `format`, `minLength`, and
`maxLength` assertions; a name failure points to that key's JSON Pointer.
`dependentRequired` reports a missing dependent property only when its trigger
property is present. The root remains subject to this checker's Object
requirement.

```moonbit
let imported_schema = @contract.ContractSchema::from_json_schema({
  "type": "object",
  "additionalProperties": false,
  "required": ["id"],
  "properties": {
    "id": { "type": "integer" },
    "request_id": { "type": "string", "format": "uuid" },
    "created_at": { "type": "string", "format": "date-time" },
    "delivery_date": { "type": "string", "format": "date" },
    "status": { "enum": ["draft", "published"] },
    "score": { "type": "number", "minimum": 0, "exclusiveMaximum": 100 },
    "code": { "type": "string", "pattern": "^[A-Z]{2}-[0-9]{4}$" },
    "price": { "type": "number", "multipleOf": 0.05 },
    "billing_address": { "type": "string" },
    "billing_city": { "type": "string" },
    "labels": {
      "type": "array",
      "minItems": 1,
      "uniqueItems": true,
      "items": { "type": "string", "minLength": 1 },
    },
  },
  "propertyNames": { "type": "string", "pattern": "^[a-z_]+$" },
  "dependentRequired": { "billing_address": ["billing_city"] },
})
```

For Mustache-style lookups inside sections, use `check_contract_with_context`. It resolves object fields from the innermost section scope outward, including array item paths such as `users[].name`. Inverted sections keep the surrounding scope. Use `check_contract_with_partials_and_context` when partials are present; each partial is analyzed in the context of its call site, including when the same partial is called from multiple sections.

```moonbit
let user_schema = @contract.ContractSchema::new([
  { path: "users", kind: @contract.ContractKind::Array, required: true },
  { path: "users[]", kind: @contract.ContractKind::Object, required: true },
  { path: "users[].name", kind: @contract.ContractKind::String, required: true },
])
let user_report = @contract.check_contract_with_context(
  "{{#users}}{{name}}{{/users}}",
  user_schema,
  { "users": [{ "name": "Ada" }] },
)
```

Use `check_contract_samples(template, partials, schema, samples, path_mode)` to validate multiple samples with one template and schema analysis. Choose `RootPaths` to keep literal root lookups or `ContextAware` for section scopes and partial inheritance. Sample diagnostics identify the zero-based input index as `sample[0]`, `sample[1]`, and so on. An empty sample list produces `NoSamples`.

```moonbit
let batch_report = @contract.check_contract_samples(
  "{{#users}}{{>user}}{{/users}}",
  Map([("user", "{{name}}")]),
  user_schema,
  [
    { "users": [{ "name": "Ada" }] },
    { "users": [{ "name": "Lin" }] },
  ],
  @contract.ContractPathMode::ContextAware,
)
```

Sample diagnostics keep the schema path in `path` and add the concrete sample
location in `instance_path`, formatted as a JSON Pointer. For example, a type
error in the first user keeps `path = "users[].name"` and reports
`instance_path = Some("/users/0/name")`. Missing fields point to where the
member should be, while unexpected fields point to the extra member. The root
location is `Some("")`; template, partial, and schema diagnostics use `None`.
Pointer keys escape `~` as `~0` and `/` as `~1`.

For consecutive nested arrays, schema paths retain each wildcard while
`instance_path` records every concrete array index. For example,
`matrix[][].name` can report `instance_path = Some("/matrix/1/0/name")`.

Diagnostics have a stable order: template and partial issues first, schema warnings next, then sample issues in input order, schema path, and concrete instance path order. `ContractDiagnosticCode` distinguishes syntax errors, partial errors, undeclared template paths, type and value-constraint failures, unexpected sample fields, unused schema fields, and an empty sample list. `ContractReport::is_valid()` is false when any error is present; unused schema fields are warnings.

Export a report for CI logs or another tool with `ContractReport::to_json()`.
The JSON contains a `valid` flag and ordered diagnostics with stable snake-case
severity and code names. `instance_path` is a JSON `null` when a diagnostic
does not refer to a sample value.

```moonbit
println(report.to_json().stringify())
```

## Run the example

The executable example checks a partial against an imported JSON Schema and
prints reports for one valid and one invalid sample:

```sh
moon run examples/contract_demo
```

Expected output:

```text
valid sample: {"valid":true,"diagnostics":[]}
invalid sample: {"valid":false,"diagnostics":[{"severity":"error","code":"constraint_violation","source":"sample","path":"status","instance_path":"/status","expected":"one of [\"draft\",\"published\"]","actual":"\"review\"","message":"value is not in the allowed enum at status"}]}
```

## Validate changes

Run the same checks used by CI from the repository root:

```sh
moon update
moon fmt --check
moon check --deny-warn --target all
moon build
moon test --deny-warn --target all
moon run examples/contract_demo
```
