#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
from __future__ import annotations

import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
EMITTER = ROOT / "src/07_emit_llvm.ll"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one replacement target, found {count}")
    return text.replace(old, new, 1)


def function_bounds(text: str, signature: str) -> tuple[int, int]:
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f"missing function: {signature}")
    end = text.find("\n}\n", start)
    if end < 0:
        raise SystemExit(f"unterminated function: {signature}")
    return start, end + 3


def replace_function(text: str, signature: str, replacement: str) -> str:
    start, end = function_bounds(text, signature)
    return text[:start] + replacement.rstrip() + "\n\n" + text[end:]


def remove_function(text: str, signature: str) -> str:
    start, end = function_bounds(text, signature)
    return text[:start] + text[end:]


def insert_after_function(text: str, signature: str, addition: str) -> str:
    _, end = function_bounds(text, signature)
    return text[:end] + "\n" + addition.rstrip() + "\n" + text[end:]


text = EMITTER.read_text()

text = replace_once(
    text,
    ";   i32  ; current function return type token kind\n; }\n\n%weave.EmitContext = type { ptr, ptr, ptr, i64, i64, i32 }",
    ";   i32, ; current function return type token kind\n"
    ";   i64, ; current function AST range start, inclusive\n"
    ";   i64  ; current function AST range end, exclusive\n"
    "; }\n\n"
    "%weave.EmitContext = type { ptr, ptr, ptr, i64, i64, i32, i64, i64 }",
    "emit context layout",
)

scope_accessors = r'''
define ptr @weave_emit_function_start_ptr(ptr %ctx) {
entry:
  %field = getelementptr inbounds %weave.EmitContext, ptr %ctx, i32 0, i32 6
  ret ptr %field
}

define ptr @weave_emit_function_end_ptr(ptr %ctx) {
entry:
  %field = getelementptr inbounds %weave.EmitContext, ptr %ctx, i32 0, i32 7
  ret ptr %field
}

define i64 @weave_emit_function_start(ptr %ctx) {
entry:
  %field = call ptr @weave_emit_function_start_ptr(ptr %ctx)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_emit_function_end(ptr %ctx) {
entry:
  %field = call ptr @weave_emit_function_end_ptr(ptr %ctx)
  %value = load i64, ptr %field
  ret i64 %value
}

define void @weave_emit_set_function_range(ptr %ctx, i64 %start, i64 %end) {
entry:
  %start_field = call ptr @weave_emit_function_start_ptr(ptr %ctx)
  %end_field = call ptr @weave_emit_function_end_ptr(ptr %ctx)
  store i64 %start, ptr %start_field
  store i64 %end, ptr %end_field
  ret void
}
'''
text = insert_after_function(
    text,
    "define ptr @weave_emit_return_type_ptr(ptr %ctx)",
    scope_accessors,
)

context_init = r'''
define void @weave_emit_context_init(ptr %ctx, ptr %source, ptr %ast, ptr %out) {
entry:
  %source_field = call ptr @weave_emit_source_ptr(ptr %ctx)
  %ast_field = call ptr @weave_emit_ast_ptr(ptr %ctx)
  %out_field = call ptr @weave_emit_out_ptr(ptr %ctx)
  %temp_field = call ptr @weave_emit_temp_counter_ptr(ptr %ctx)
  %label_field = call ptr @weave_emit_label_counter_ptr(ptr %ctx)
  %return_type_field = call ptr @weave_emit_return_type_ptr(ptr %ctx)
  %function_start_field = call ptr @weave_emit_function_start_ptr(ptr %ctx)
  %function_end_field = call ptr @weave_emit_function_end_ptr(ptr %ctx)

  store ptr %source, ptr %source_field
  store ptr %ast, ptr %ast_field
  store ptr %out, ptr %out_field
  store i64 0, ptr %temp_field
  store i64 0, ptr %label_field
  store i32 32, ptr %return_type_field
  store i64 -1, ptr %function_start_field
  store i64 -1, ptr %function_end_field
  ret void
}
'''
text = replace_function(
    text,
    "define void @weave_emit_context_init(ptr %ctx, ptr %source, ptr %ast, ptr %out)",
    context_init,
)

text = replace_once(
    text,
    "@weave.emit.current_param_list = global i64 -1\n",
    "",
    "obsolete global parameter list",
)

text = remove_function(
    text,
    "define i32 @weave_emit_lookup_param_type(",
)

binding_helpers_and_lookup = r'''
define i32 @weave_emit_is_binding_kind(i32 %kind) {
entry:
  %is_param = icmp eq i32 %kind, 30
  %is_let = icmp eq i32 %kind, 7
  %is_binding = or i1 %is_param, %is_let
  %result = zext i1 %is_binding to i32
  ret i32 %result
}

define i64 @weave_emit_find_function_start(ptr %ctx, i64 %function_node) {
entry:
  %has_previous = icmp sgt i64 %function_node, 0
  br i1 %has_previous, label %prepare, label %zero

prepare:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %first = sub i64 %function_node, 1
  br label %scan

scan:
  %index = phi i64 [%first, %prepare], [%previous, %continue]
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %index)
  %is_function = icmp eq i32 %kind, 2
  %is_extern = icmp eq i32 %kind, 17
  %is_separator = or i1 %is_function, %is_extern
  br i1 %is_separator, label %after_separator, label %check_zero

check_zero:
  %at_zero = icmp eq i64 %index, 0
  br i1 %at_zero, label %zero, label %continue

continue:
  %previous = sub i64 %index, 1
  br label %scan

after_separator:
  %start = add i64 %index, 1
  ret i64 %start

zero:
  ret i64 0
}

define i32 @weave_emit_nodes_same_name(ptr %ctx, i64 %lhs_node, i64 %rhs_node) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %source = call ptr @weave_emit_source(ptr %ctx)
  %data = call ptr @weave_source_data(ptr %source)
  %lhs_start = call i64 @weave_ast_text_start(ptr %ast, i64 %lhs_node)
  %lhs_len = call i64 @weave_ast_text_len(ptr %ast, i64 %lhs_node)
  %rhs_start = call i64 @weave_ast_text_start(ptr %ast, i64 %rhs_node)
  %rhs_len = call i64 @weave_ast_text_len(ptr %ast, i64 %rhs_node)
  %lhs_text = getelementptr inbounds i8, ptr %data, i64 %lhs_start
  %rhs_text = getelementptr inbounds i8, ptr %data, i64 %rhs_start
  %same = call i32 @weave_bytes_equal(
    ptr %lhs_text,
    i64 %lhs_len,
    ptr %rhs_text,
    i64 %rhs_len
  )
  ret i32 %same
}

define i32 @weave_emit_validate_bindings(ptr %ctx, i64 %start, i64 %end) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  br label %outer

outer:
  %i = phi i64 [%start, %entry], [%next_i, %outer_continue]
  %outer_done = icmp uge i64 %i, %end
  br i1 %outer_done, label %success, label %outer_kind

outer_kind:
  %kind_i = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %binding_i_status = call i32 @weave_emit_is_binding_kind(i32 %kind_i)
  %binding_i = icmp ne i32 %binding_i_status, 0
  br i1 %binding_i, label %inner_prepare, label %outer_continue

inner_prepare:
  %first_j = add i64 %i, 1
  br label %inner

inner:
  %j = phi i64 [%first_j, %inner_prepare], [%next_j, %inner_continue]
  %inner_done = icmp uge i64 %j, %end
  br i1 %inner_done, label %outer_continue, label %inner_kind

inner_kind:
  %kind_j = call i32 @weave_ast_kind(ptr %ast, i64 %j)
  %binding_j_status = call i32 @weave_emit_is_binding_kind(i32 %kind_j)
  %binding_j = icmp ne i32 %binding_j_status, 0
  br i1 %binding_j, label %compare, label %inner_continue

compare:
  %same_status = call i32 @weave_emit_nodes_same_name(
    ptr %ctx,
    i64 %i,
    i64 %j
  )
  %same = icmp ne i32 %same_status, 0
  br i1 %same, label %fail, label %inner_continue

inner_continue:
  %next_j = add i64 %j, 1
  br label %inner

outer_continue:
  %next_i = add i64 %i, 1
  br label %outer

success:
  ret i32 0

fail:
  ret i32 1
}

define i32 @weave_emit_lookup_local_type(ptr %ctx, i64 %name_start, i64 %name_len) {
entry:
  %start = call i64 @weave_emit_function_start(ptr %ctx)
  %end = call i64 @weave_emit_function_end(ptr %ctx)
  %start_valid = icmp sge i64 %start, 0
  %end_valid = icmp sge i64 %end, 0
  %ordered = icmp ule i64 %start, %end
  %bounds_valid = and i1 %start_valid, %end_valid
  %scope_valid = and i1 %bounds_valid, %ordered
  br i1 %scope_valid, label %prepare, label %not_found

prepare:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %source = call ptr @weave_emit_source(ptr %ctx)
  %data = call ptr @weave_source_data(ptr %source)
  %name_text = getelementptr inbounds i8, ptr %data, i64 %name_start
  br label %loop

loop:
  %i = phi i64 [%start, %prepare], [%next_i, %continue]
  %done = icmp uge i64 %i, %end
  br i1 %done, label %not_found, label %check_kind

check_kind:
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %is_param = icmp eq i32 %kind, 30
  %is_let = icmp eq i32 %kind, 7
  %is_binding = or i1 %is_param, %is_let
  br i1 %is_binding, label %check_name, label %continue

check_name:
  %binding_start = call i64 @weave_ast_text_start(ptr %ast, i64 %i)
  %binding_len = call i64 @weave_ast_text_len(ptr %ast, i64 %i)
  %binding_text = getelementptr inbounds i8, ptr %data, i64 %binding_start
  %same_status = call i32 @weave_bytes_equal(
    ptr %name_text,
    i64 %name_len,
    ptr %binding_text,
    i64 %binding_len
  )
  %same = icmp ne i32 %same_status, 0
  br i1 %same, label %return_type, label %continue

return_type:
  %param_type_wide = call i64 @weave_ast_a(ptr %ast, i64 %i)
  %let_type_wide = call i64 @weave_ast_b(ptr %ast, i64 %i)
  %type_wide = select i1 %is_param, i64 %param_type_wide, i64 %let_type_wide
  %type_kind = trunc i64 %type_wide to i32
  ret i32 %type_kind

continue:
  %next_i = add i64 %i, 1
  br label %loop

not_found:
  ret i32 -1
}
'''
text = replace_function(
    text,
    "define i32 @weave_emit_lookup_local_type(ptr %ctx, i64 %name_start, i64 %name_len)",
    binding_helpers_and_lookup,
)

name_start, name_end = function_bounds(
    text,
    "define i64 @weave_emit_name_expr(ptr %ctx, i64 %node_index)",
)
name_function = text[name_start:name_end]
name_function = replace_once(
    name_function,
    "  %temp = call i64 @weave_emit_next_temp(ptr %ctx)\n"
    "  %type_kind = call i32 @weave_emit_lookup_local_type(ptr %ctx, i64 %name_start, i64 %name_len)\n"
    "  %is_ptr = icmp eq i32 %type_kind, 58\n\n"
    "  %s0 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.emit.indent_tmp)",
    "  %type_kind = call i32 @weave_emit_lookup_local_type(ptr %ctx, i64 %name_start, i64 %name_len)\n"
    "  %missing = icmp eq i32 %type_kind, -1\n"
    "  br i1 %missing, label %fail, label %emit\n\n"
    "emit:\n"
    "  %temp = call i64 @weave_emit_next_temp(ptr %ctx)\n"
    "  %is_ptr = icmp eq i32 %type_kind, 58\n"
    "  %s0 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.emit.indent_tmp)",
    "undefined binding guard",
)
text = text[:name_start] + name_function + text[name_end:]

function_start, function_end = function_bounds(
    text,
    "define i32 @weave_emit_function(ptr %ctx, i64 %node_index)",
)
function_text = text[function_start:function_end]
function_text = replace_once(
    function_text,
    "entry:\n  %ast = call ptr @weave_emit_ast(ptr %ctx)",
    "entry:\n"
    "  %function_start = call i64 @weave_emit_find_function_start(ptr %ctx, i64 %node_index)\n"
    "  call void @weave_emit_set_function_range(ptr %ctx, i64 %function_start, i64 %node_index)\n"
    "  %binding_status = call i32 @weave_emit_validate_bindings(\n"
    "    ptr %ctx,\n"
    "    i64 %function_start,\n"
    "    i64 %node_index\n"
    "  )\n"
    "  %bindings_failed = icmp ne i32 %binding_status, 0\n"
    "  br i1 %bindings_failed, label %fail, label %prepare\n\n"
    "prepare:\n"
    "  %ast = call ptr @weave_emit_ast(ptr %ctx)",
    "function scope setup",
)
function_text = replace_once(
    function_text,
    "  store i64 %param_list, ptr @weave.emit.current_param_list\n",
    "",
    "global parameter list store",
)
function_text = replace_once(
    function_text,
    "success:\n  ret i32 0\n\nfail:\n  ret i32 1",
    "success:\n"
    "  call void @weave_emit_set_function_range(ptr %ctx, i64 -1, i64 -1)\n"
    "  ret i32 0\n\n"
    "fail:\n"
    "  call void @weave_emit_set_function_range(ptr %ctx, i64 -1, i64 -1)\n"
    "  ret i32 1",
    "function scope cleanup",
)
text = text[:function_start] + function_text + text[function_end:]

text = replace_once(
    text,
    ";   No optimization, no verifier, no type checking. The emitter trusts the\n"
    ";   AST built by 06_parser.ll. Bool values are kept as i1 internally and",
    ";   No optimization and no general verifier. The emitter performs the small\n"
    ";   binding-scope validation required to emit well-formed LLVM, then trusts\n"
    ";   the remaining AST built by 06_parser.ll. Bool values are kept as i1 and",
    "emitter boundary documentation",
)

if "weave.emit.current_param_list" in text:
    raise SystemExit("obsolete current_param_list reference remains")
if "define i32 @weave_emit_lookup_param_type" in text:
    raise SystemExit("obsolete parameter lookup remains")

EMITTER.write_text(text)

run_tests = ROOT / "scripts/run-tests.sh"
run_tests_text = run_tests.read_text()
run_tests_text = replace_once(
    run_tests_text,
    'bash "$ROOT/scripts/run-integer-range-negative-matrix.sh" \\\n  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/integer-range-negative-matrix"\n\n',
    'bash "$ROOT/scripts/run-integer-range-negative-matrix.sh" \\\n  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/integer-range-negative-matrix"\n'
    'bash "$ROOT/scripts/run-binding-scope-tests.sh" \\\n  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/binding-scope"\n\n',
    "normal binding-scope workload",
)
run_tests.write_text(run_tests_text)

coverage = ROOT / "scripts/extend-coverage-with-cli.sh"
coverage_text = coverage.read_text()
coverage_text = replace_once(
    coverage_text,
    "printf '[coverage] regenerate aggregate report\\n' >&2\n",
    "printf '[coverage] extend workload with function binding scope cases\\n' >&2\n"
    "WEAVEC0_COVERAGE_OUT=\"$RAW_TSV\" \\\n"
    "  bash \"$ROOT/scripts/run-binding-scope-tests.sh\" \\\n"
    "    \"$INSTRUMENTED_BIN\" \"$BUILD_DIR/binding-scope\"\n\n"
    "printf '[coverage] regenerate aggregate report\\n' >&2\n",
    "coverage binding-scope workload",
)
coverage.write_text(coverage_text)

changelog = ROOT / "CHANGELOG.md"
changelog_text = changelog.read_text()
release_notes = '''## [0.3.3] — 2026-07-25

### Added

- A function-binding regression ladder covering cross-function same-name
  locals, exact i32 parameter lookup, undefined local and parameter reads,
  duplicate parameters, duplicate locals, and parameter/local shadowing.
- The same binding workload is included in the instrumented LLVM coverage
  extension.

### Changed

- Emitter context now carries the active function's AST interval. Binding type
  lookup is restricted to that interval and uses `-1` as an explicit not-found
  result distinct from every valid WIR type.
- Stage 0 defines a no-shadowing rule within a function: parameter names and
  local names must be unique across the whole function body.

### Fixed

- A local in a later function can no longer change the load type emitted for an
  earlier same-named local.
- Undefined `local_get` and `param_get` expressions now fail deterministically
  instead of silently falling back to i32.
- Duplicate parameters, duplicate locals, and parameter/local collisions are
  rejected before function LLVM text is emitted.

'''
changelog_text = replace_once(
    changelog_text,
    "## [Unreleased]\n\n## [0.3.2] — 2026-07-25\n",
    "## [Unreleased]\n\n" + release_notes + "## [0.3.2] — 2026-07-25\n",
    "0.3.3 changelog insertion",
)
changelog.write_text(changelog_text)
(ROOT / "VERSION").write_text("0.3.3\n")

subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", "scripts/run-binding-scope-tests.sh"], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", "scripts/run-tests.sh"], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", "scripts/extend-coverage-with-cli.sh"], cwd=ROOT, check=True)
subprocess.run(["bash", "scripts/run-tests.sh"], cwd=ROOT, check=True)

(ROOT / ".github/workflows/apply-function-binding-scope.yml").unlink()
pathlib.Path(__file__).unlink()

subprocess.run(["git", "add", "-A"], cwd=ROOT, check=True)
subprocess.run(
    [
        "git",
        "-c",
        "user.name=github-actions[bot]",
        "-c",
        "user.email=41898282+github-actions[bot]@users.noreply.github.com",
        "commit",
        "-m",
        "fix: scope bindings to the current function",
    ],
    cwd=ROOT,
    check=True,
)
subprocess.run(
    ["git", "push", "origin", "HEAD:agent/integrate-function-binding-scope"],
    cwd=ROOT,
    check=True,
)
