"""Reproduce the committee-review evidence with Python 3 stdlib and moon."""
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CODEGEN = ROOT.parent / "ion-schema-codegen"
PATCH = ROOT.parent / "ion-patch"
PINNED = {
    "ion-schema-codegen": "558dc610cdbb559a1e46d4ee285a702b72dfc65b",
    "ion-patch": "f956351ddbed8aa87b0895b68246b2c2308f80cb",
}
records = []


def execute(args, cwd, expected=0):
    result = subprocess.run(args, cwd=cwd, text=True, encoding="utf-8",
                            errors="replace", capture_output=True)
    output = result.stdout + result.stderr
    ok = result.returncode == expected if expected == 0 else result.returncode != 0
    if not ok:
        raise RuntimeError(f"{args!r} failed ({result.returncode}):\n{output}")
    return output.strip(), result.returncode


def checked(args, cwd, label):
    output, code = execute(args, cwd)
    summaries = re.findall(r"Total tests: [^\r\n]+", output)
    command = [os.path.relpath(arg, cwd).replace("\\", "/")
               if Path(arg).is_absolute() else arg for arg in args]
    records.append({"check": label, "cwd": os.path.relpath(cwd, HERE).replace("\\", "/"),
                    "command": command, "exit_code": code,
                    "test_summaries": summaries})
    print(label + ": passed", flush=True)
    return output


def digest(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def main():
    for name, directory in [("ion-schema-codegen", CODEGEN), ("ion-patch", PATCH)]:
        revision, _ = execute(["git", "rev-parse", "HEAD"], directory)
        if revision != PINNED[name]:
            raise RuntimeError(f"{name}: check out pinned revision {PINNED[name]}")
        dirty, _ = execute(["git", "status", "--porcelain", "--untracked-files=no"], directory)
        if dirty:
            raise RuntimeError(f"{name}: dependency contains tracked modifications")

    version, _ = execute(["moon", "version"], ROOT)
    compiler, _ = execute(["moonc", "-v"], ROOT)
    api_path = ROOT / "pkg.generated.mbti"
    api_before = digest(api_path)
    for args, label in [
        (["moon", "fmt", "--check"], "library-format"),
        (["moon", "check", "--deny-warn", "--target", "all"], "library-check"),
        (["moon", "build", "--target", "all"], "library-build"),
        (["moon", "test", "--deny-warn", "--target", "all"], "library-tests"),
        (["moon", "info"], "library-public-api"),
        (["moon", "run", "--target", "native", "examples/contract_demo"], "library-demo"),
    ]:
        checked(args, ROOT, label)
    if api_before != digest(api_path):
        raise RuntimeError("pkg.generated.mbti is stale: inspect the refreshed public API")

    generated = HERE / "generated.mbt"
    before = digest(generated)
    checked(["moon", "run", "--target", "native", "./cli", str(HERE / "order.isl"),
             str(generated)], CODEGEN, "isl-import-regeneration")
    checked(["moon", "fmt", ".", "./cmd"], HERE, "integration-format")
    if before != digest(generated):
        raise RuntimeError("generated.mbt is stale: inspect the regenerated source")
    for action in ["check", "build", "test"]:
        args = ["moon", action, "--target", "all"]
        if action != "build":
            args.append("--deny-warn")
        if action == "test":
            args.append(".")
        checked(args, HERE, "integration-" + action)
    output = checked(["moon", "run", "--target", "native", "./cmd"], HERE, "pipeline-render")
    rendered = json.loads(output.splitlines()[-1])
    if rendered != {"status": "passed", "output": "Order 42: MoonBit x3",
                    "inverse_restored": True}:
        raise RuntimeError("unexpected pipeline result")

    negative = []
    with tempfile.TemporaryDirectory(prefix="stencil-compatibility-") as folder:
        directory = Path(folder)
        (directory / "common.isl").write_text((HERE / "common.isl").read_text(encoding="utf-8"), encoding="utf-8")
        (directory / "cycle.isl").write_text('$ion_schema_2_0 schema_header::{imports:[{id:"bad.isl"}]} type::{name:Cycle,type:int}', encoding="utf-8")
        (directory / "middle.isl").write_text('$ion_schema_2_0 schema_header::{imports:[{id:"common.isl",type:PositiveQuantity}]} type::{name:Bridge,type:PositiveQuantity}', encoding="utf-8")
        cases = [
            ("missing-schema", '$ion_schema_2_0 schema_header::{imports:[{id:"missing.isl"}]} type::{name:X,type:int}', "cannot resolve schema file"),
            ("unknown-imported-type", '$ion_schema_2_0 schema_header::{imports:[{id:"common.isl",type:Missing}]} type::{name:X,type:int}', "is not declared"),
            ("cyclic-schema-import", '$ion_schema_2_0 schema_header::{imports:[{id:"cycle.isl"}]} type::{name:X,type:int}', "cycle"),
            ("no-transitive-visibility", '$ion_schema_2_0 schema_header::{imports:[{id:"middle.isl",type:Bridge}]} type::{name:X,type:PositiveQuantity}', "unknown"),
            ("unsupported-constraint", '$ion_schema_2_0 type::{name:X,type:int,scale:1}', "unsupported"),
        ]
        for name, source, message in cases:
            source_path = directory / "bad.isl"
            destination = directory / "output.mbt"
            source_path.write_text(source, encoding="utf-8")
            destination.write_text("existing output must survive", encoding="utf-8")
            error, code = execute(["moon", "run", "--target", "native", "./cli",
                                   str(source_path), str(destination)], CODEGEN, expected=1)
            if message not in error.lower() or destination.read_text(encoding="utf-8") != "existing output must survive":
                raise RuntimeError(f"{name}: wrong error or output overwritten:\n{error}")
            negative.append({"case": name, "exit_code": code, "output_unchanged": True})
            print(name + ": rejected as expected", flush=True)

    report = {"status": "passed", "toolchain": version, "compiler": compiler,
              "dependency_revisions": PINNED,
              "schema_sha256": {name: digest(HERE / name) for name in ["common.isl", "order.isl"]},
              "generated_sha256": digest(generated), "checks": records,
              "negative_cli_cases": negative, "pipeline": rendered}
    (HERE / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Evidence saved to integration/verification.json", flush=True)


if __name__ == "__main__":
    main()
