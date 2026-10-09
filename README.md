# stencil-contract

MoonBit package for checking data contracts used by Stencil templates and partials. It checks template paths against an explicit schema, validates a sample JSON value, and reports missing or cyclic partials.

Rendering is provided by `LL124-Arch/stencil`.

## Define a contract

Schema paths use dots for object fields and `[]` for array elements. Declare nested parents when you need to constrain their type or requiredness. Any undeclared sample fields are errors, including keys inside array objects. Use an `Any` declaration for an arbitrary value and its contents.

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

Diagnostics have a stable order: template and partial issues first, schema warnings next, then sample issues in input order, schema path, and concrete instance path order. `ContractDiagnosticCode` distinguishes syntax errors, partial errors, undeclared template paths, sample validation errors, unused schema fields, and an empty sample list. `ContractReport::is_valid()` is false when any error is present; unused schema fields are warnings.

```sh
moon check
moon test
```
