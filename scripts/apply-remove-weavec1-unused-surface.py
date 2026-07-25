#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text)


def replace_once(text: str, old: str, new: str, *, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def remove_label(text: str, label: str) -> str:
    pattern = re.compile(
        rf"(?ms)^({re.escape(label)}):\n.*?(?=^[A-Za-z0-9_.-]+:\n|^define |^; -|\Z)"
    )
    text, count = pattern.subn("", text, count=1)
    if count != 1:
        raise SystemExit(f"label {label}: expected one block, found {count}")
    return text


def remove_line(text: str, line: str, *, label: str) -> str:
    return replace_once(text, line + "\n", "", label=label)


def run(*args: str, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    subprocess.run(args, cwd=cwd, env=env, check=True)


# ---------------------------------------------------------------------------
# Token surface: keep numeric gaps reserved so existing required token values
# remain stable, but stop recognizing the five forms absent from pinned weavec1.
# ---------------------------------------------------------------------------
prelude = read("src/00_prelude.ll")
for old, new in [
    ("; TOKEN_BLOCK   = 24", "; TOKEN_RESERVED_24 = 24"),
    ("; TOKEN_CONST_STRING = 41", "; TOKEN_RESERVED_41 = 41"),
    ("; TOKEN_PRINT        = 45", "; TOKEN_RESERVED_45 = 45"),
    ("; TOKEN_GT_I64       = 91", "; TOKEN_RESERVED_91 = 91"),
    ("; TOKEN_GE_I64       = 92", "; TOKEN_RESERVED_92 = 92"),
]:
    prelude = replace_once(prelude, old, new, label=old)
write("src/00_prelude.ll", prelude)

lexer = read("src/04_lexer.ll")
for line in [
    '@weave.kw.block = private unnamed_addr constant [6 x i8] c"block\\00"',
    '@weave.kw.const_string = private unnamed_addr constant [13 x i8] c"const_string\\00"',
    '@weave.kw.print = private unnamed_addr constant [6 x i8] c"print\\00"',
    '@weave.kw.gt_i64 = private unnamed_addr constant [7 x i8] c"gt_i64\\00"',
    '@weave.kw.ge_i64 = private unnamed_addr constant [7 x i8] c"ge_i64\\00"',
]:
    lexer = remove_line(lexer, line, label=line)
lexer = replace_once(
    lexer,
    "  br i1 %set_yes, label %return_set, label %check_block",
    "  br i1 %set_yes, label %return_set, label %check_core_module",
    label="lexer block bypass",
)
lexer = remove_label(lexer, "check_block")
lexer = replace_once(
    lexer,
    "  br i1 %cast_i64_to_i32_yes, label %return_cast_i64_to_i32, label %check_const_string",
    "  br i1 %cast_i64_to_i32_yes, label %return_cast_i64_to_i32, label %check_const_string_ptr",
    label="lexer const_string bypass",
)
lexer = remove_label(lexer, "check_const_string")
lexer = replace_once(
    lexer,
    "  br i1 %add_i32_yes, label %return_add_i32, label %check_print",
    "  br i1 %add_i32_yes, label %return_add_i32, label %check_lt_i64",
    label="lexer print bypass",
)
lexer = remove_label(lexer, "check_print")
lexer = replace_once(
    lexer,
    "  br i1 %cast_i32_to_i64_yes, label %return_cast_i32_to_i64, label %check_gt_i64",
    "  br i1 %cast_i32_to_i64_yes, label %return_cast_i32_to_i64, label %return_ident",
    label="lexer i64 comparison tail",
)
for label in [
    "check_gt_i64",
    "check_ge_i64",
    "return_block",
    "return_const_string",
    "return_print",
    "return_gt_i64",
    "return_ge_i64",
]:
    lexer = remove_label(lexer, label)
write("src/04_lexer.ll", lexer)

# ---------------------------------------------------------------------------
# Parser: const_string_ptr remains and continues to use the shared string AST.
# Remove only the plain-string convenience form, print pseudo-call, and the two
# unused i64 comparison operators.
# ---------------------------------------------------------------------------
parser = read("src/06_parser.ll")
parser = parser.replace("const_string,\n;     const_string_ptr", "const_string_ptr")
parser = replace_once(
    parser,
    "  br i1 %is_eq_i64, label %eq_i64, label %check_gt_i64",
    "  br i1 %is_eq_i64, label %eq_i64, label %check_and_bool",
    label="parser binary i64 tail",
)
for label in ["check_gt_i64", "check_ge_i64", "gt_i64", "ge_i64"]:
    parser = remove_label(parser, label)
old_const_dispatch = """check_const_string:
  %is_plain_const_string = icmp eq i32 %head_kind, 41
  %is_const_string_ptr = icmp eq i32 %head_kind, 83
  %is_const_string = or i1 %is_plain_const_string, %is_const_string_ptr
  br i1 %is_const_string, label %parse_const_string, label %check_param_get
"""
new_const_dispatch = """check_const_string:
  %is_const_string_ptr = icmp eq i32 %head_kind, 83
  br i1 %is_const_string_ptr, label %parse_const_string, label %check_param_get
"""
parser = replace_once(parser, old_const_dispatch, new_const_dispatch, label="parser string dispatch")
parser = replace_once(
    parser,
    "  br i1 %is_ne_ptr, label %parse_ne_ptr, label %check_print",
    "  br i1 %is_ne_ptr, label %parse_ne_ptr, label %unknown_operator",
    label="parser print bypass",
)
for label in ["check_print", "parse_print", "print_close", "make_print", "parse_gt_i64", "parse_ge_i64"]:
    parser = remove_label(parser, label)
write("src/06_parser.ll", parser)

# ---------------------------------------------------------------------------
# Emitter: ordinary call_i32 + const_string_ptr already covers puts. Remove the
# special print lowering and the unused i64 operator strings/dispatch.
# ---------------------------------------------------------------------------
emitter = read("src/07_emit_llvm.ll")
for line in [
    '@weave.emit.icmp_gt_i64 = private unnamed_addr constant [17 x i8] c" = icmp sgt i64 \\00"',
    '@weave.emit.icmp_ge_i64 = private unnamed_addr constant [17 x i8] c" = icmp sge i64 \\00"',
    '@weave.emit.print_name = private unnamed_addr constant [6 x i8] c"print\\00"',
    '@weave.emit.puts_call = private unnamed_addr constant [28 x i8] c" = call i32 @puts(ptr @.str\\00"',
]:
    emitter = remove_line(emitter, line, label=line)
emitter = replace_once(
    emitter,
    "  br i1 %is_eq_i64, label %eq_i64, label %check_gt_i64",
    "  br i1 %is_eq_i64, label %eq_i64, label %fail",
    label="emitter binary i64 tail",
)
for label in ["check_gt_i64", "check_ge_i64", "gt_i64", "ge_i64"]:
    emitter = remove_label(emitter, label)
print_entry = """  %source = call ptr @weave_emit_source(ptr %ctx)
  %source_data = call ptr @weave_source_data(ptr %source)
  %name_text = getelementptr inbounds i8, ptr %source_data, i64 %name_start
  %is_print_i32 = call i32 @weave_bytes_equal(ptr %name_text, i64 %name_len, ptr @weave.emit.print_name, i64 5)
  %is_print = icmp ne i32 %is_print_i32, 0
  br i1 %is_print, label %print_call, label %normal_call
"""
emitter = replace_once(emitter, print_entry, "  br label %normal_call\n", label="print emitter entry")
for label in ["print_call", "read_print_arg", "emit_print", "print_success"]:
    emitter = remove_label(emitter, label)
write("src/07_emit_llvm.ll", emitter)

# ---------------------------------------------------------------------------
# Tests: retain required string tokenization, escaping, empty-string, and global
# emission coverage through the actual Stage 1 path: const_string_ptr + puts.
# ---------------------------------------------------------------------------
for path in [
    "test/10_string_literal.wir",
    "test/48_string_escape.wir",
    "test/85_string_empty.wir",
    "test/100_grand_finale.wir",
]:
    text = read(path)
    text = text.replace("(print", "(call_i32 puts")
    text = text.replace("(const_string ", "(const_string_ptr ")
    text = text.replace(") ;; print", ") ;; call_i32")
    text = text.replace("const_string handling with runtime print interaction", "const_string_ptr handling through the required puts call path")
    text = text.replace("through const_string emission", "through const_string_ptr emission")
    text = text.replace("and a print", "and a puts call")
    write(path, text)

for path in ["test/39_i64_ge_gt.wir", "test/39_i64_ge_gt.expected.ll"]:
    target = ROOT / path
    if not target.exists():
        raise SystemExit(f"missing removal target: {path}")
    target.unlink()

manifest = read("test/manifest.txt")
manifest = replace_once(
    manifest,
    "pass 39_i64_ge_gt                       42\n",
    "",
    label="manifest i64 comparison test",
)
write("test/manifest.txt", manifest)

negative = read("scripts/run-parser-negative-matrix.sh")
negative = replace_once(
    negative,
    "  add_i64 sub_i64 mul_i64 eq_i64 ne_i64 lt_i64 le_i64 gt_i64 ge_i64",
    "  add_i64 sub_i64 mul_i64 eq_i64 ne_i64 lt_i64 le_i64",
    label="negative i64 operator matrix",
)
negative = re.sub(
    r"run_case const_string-too-few .*?\n  \"\$\(expr_program '\(const_string\)'\)\"\n"
    r"run_case const_string-too-many .*?\n  \"\$\(expr_program '\(const_string \"a\" \"b\"\)'\)\"\n",
    "",
    negative,
    count=1,
    flags=re.S,
)
if "const_string-too-few" in negative or "const_string-too-many" in negative:
    raise SystemExit("failed to remove const_string negative cases")
write("scripts/run-parser-negative-matrix.sh", negative)

# Documentation describes the retained pointer-valued string form.
wir_doc = read("docs/weave-intermediate-representation.md")
wir_doc = wir_doc.replace("### `(const_string TEXT)`", "### `(const_string_ptr TEXT)`")
wir_doc = wir_doc.replace('(const_string "hello")', '(const_string_ptr "hello")')
write("docs/weave-intermediate-representation.md", wir_doc)

changelog = read("CHANGELOG.md")
marker = "## [Unreleased]\n"
addition = """## [Unreleased]

### Removed

- Five Stage 0 WIR forms absent from the pinned `weavec1` production corpus:
  `block`, `const_string`, `print`, `gt_i64`, and `ge_i64`.
- The print-specific LLVM lowering path; required string output remains available
  through `call_i32 puts` with `const_string_ptr`.
"""
changelog = replace_once(changelog, marker, addition, label="changelog unreleased")
write("CHANGELOG.md", changelog)

# Reject accidental retained admissions in compiler source.
for token in ["weave.kw.block", "weave.kw.const_string =", "weave.kw.print", "weave.kw.gt_i64", "weave.kw.ge_i64", "@weave.emit.print_name", "@weave.emit.puts_call"]:
    for path in ["src/04_lexer.ll", "src/06_parser.ll", "src/07_emit_llvm.ll"]:
        if token in read(path):
            raise SystemExit(f"retained removed surface {token} in {path}")

# Regenerate only intentionally changed string goldens, then run every normal
# and generated-negative test.
run("bash", "build.sh", "--regen-goldens")
run("bash", "scripts/run-tests.sh")

# Compile the exact pinned Stage 1 module corpus and verify the machine-readable
# surface inventory no longer reports test-only WIR forms.
weavec1_dir = ROOT / "build" / "weavec1-minimization-audit"
shutil.rmtree(weavec1_dir, ignore_errors=True)
commit = read("WEAVEC1_BOOTSTRAP_COMMIT").strip()
run("git", "clone", "--filter=blob:none", "--no-checkout", "https://github.com/ahojukka5/weavec1.git", str(weavec1_dir))
run("git", "-C", str(weavec1_dir), "fetch", "--depth", "1", "origin", commit)
run("git", "-C", str(weavec1_dir), "checkout", "--detach", "FETCH_HEAD")
run("bash", "scripts/run-coverage.sh", "--weavec1-dir", str(weavec1_dir))
surface = json.loads((ROOT / "build/coverage/bootstrap-surface.json").read_text())
if surface["unused_by_weavec1"]:
    raise SystemExit(f"remaining Stage 0 forms unused by weavec1: {surface['unused_by_weavec1']}")

run("git", "diff", "--check")

# Staging mechanism must not remain in the finished change.
for path in [
    ROOT / "scripts/apply-remove-weavec1-unused-surface.py",
    ROOT / ".github/workflows/apply-remove-weavec1-unused-surface.yml",
]:
    path.unlink(missing_ok=True)

run("git", "add", "-A")
run("git", "commit", "-m", "refactor: remove WIR forms unused by weavec1")
run("git", "push", "origin", "HEAD:agent/remove-weavec1-unused-surface")
