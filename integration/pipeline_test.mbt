///|
fn render_failure(value : @ion_model.IonValue) -> (String, String) {
  try {
    ignore(@stencil-contract-integration.render_order(value))
    ("accepted", "")
  } catch {
    @stencil-contract-integration.PipelineError::Rejected(stage~, path~) =>
      (stage, path)
  }
}

///|
fn projection_failure(value : @ion_model.IonValue) -> (String, String) {
  try {
    ignore(@stencil-contract-integration.project_for_template(value))
    ("accepted", "")
  } catch {
    @stencil-contract-integration.PipelineError::Rejected(stage~, path~) =>
      (stage, path)
  }
}

///|
test "ISL import patch validation projection contract render and inverse form one endpoint" {
  let report = @stencil-contract-integration.run_pipeline()
  assert_eq(
    report.stringify(),
    "{\"status\":\"passed\",\"output\":\"Order 42: MoonBit x3\",\"inverse_restored\":true}",
  )
}

///|
test "compiled imported constraints reject invalid values before rendering" {
  for
    source in [
      "{id:42,title:\"MoonBit\",quantity:0}", "{id:42,title:\"MoonBit\",quantity:101}",
      "{id:42,title:\"MoonBit\",quantity:2.5}", "{id:42,title:\"MoonBit\",quantity:null.int}",
      "{id:42,title:\"\",quantity:1}", "{id:9007199254740992,title:\"MoonBit\",quantity:1}",
      "{id:42,title:\"MoonBit\"}", "{id:42,title:\"MoonBit\",quantity:1,extra:true}",
    ] {
    let (stage, _) = render_failure(@ion.parse_one_text(source))
    assert_eq(stage, "isl")
  }
  let (stage, _) = render_failure(
    @ion.parse_one_text("{id:42,title:\"MoonBit\",quantity:tag::1}"),
  )
  assert_eq(stage, "projection:annotations")
}

///|
test "projection rejects Ion semantics JSON cannot preserve" {
  for
    (source, expected) in [
      ("{n:9007199254740992}", "projection:unsafe_integer"),
      ("{n:null.int}", "projection:unsupported_ion_kind"),
      ("{n:1.0}", "projection:unsupported_ion_kind"),
      ("{n:foo}", "projection:unsupported_ion_kind"),
      ("{n:(1)}", "projection:unsupported_ion_kind"),
      ("{n:tag::1}", "projection:annotations"),
      ("{n:1,n:2}", "projection:duplicate_field"),
    ] {
    assert_eq(projection_failure(@ion.parse_one_text(source)), (expected, "/n"))
  }
  let unknown = @ion_model.IonValue::Struct([
    (@ion_model.IonSymbol::from_sid(77), @ion_model.IonValue::Bool(true)),
  ])
  assert_eq(projection_failure(unknown), ("projection:unresolved_symbol", ""))
  let safe = @stencil-contract-integration.project_for_template(
    @ion.parse_one_text(
      "{n:9007199254740991,negative:-9007199254740991,items:[true,null,\"text\"]}",
    ),
  )
  assert_true(safe.stringify().contains("9007199254740991"))
}

///|
test "patch is not a validation bypass and inverse restores a valid render" {
  let before = @ion.parse_text("{id:42,title:\"MoonBit\",quantity:2}")
  let invalid = @ion.parse_text("{id:42,title:\"MoonBit\",quantity:0}")
  let operations = @patch.diff(before[:], invalid[:])
  let patched = @patch.apply(before[:], operations[:])
  let (stage, path) = render_failure(patched[0])
  assert_eq(stage, "isl")
  assert_true(path.contains("quantity"))
  let reverse = @patch.invert(before[:], operations[:])
  let restored = @patch.apply(patched[:], reverse[:])
  assert_eq(
    @stencil-contract-integration.render_order(restored[0]),
    "Order 42: MoonBit x2",
  )
  assert_true(@patch.equal_values(restored[:], before[:]))
}
