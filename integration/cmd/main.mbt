///|
fn main {
  let report = @pipeline.run_pipeline() catch {
    _ => abort("contract pipeline failed before rendering")
  }
  println(report.stringify())
}
