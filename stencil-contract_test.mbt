///|
test "Stencil dependency renders a template" {
  let output = @stencil.render("Hello {{name}}", { "name": "MoonBit" })
  assert_eq(output, "Hello MoonBit")
}
