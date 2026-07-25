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


text = EMITTER.read_text()

helpers = r'''
; ----------------------------------------------------------------------------
; Module symbol validation
; ----------------------------------------------------------------------------
;
; Functions and externs share one declaration namespace. Calls may target any
; declaration regardless of source order. The sole undeclared pseudo-target is
; `print`, which is represented as an i32 call node and lowered directly to
; puts by the emitter.

define i32 @weave_symbol_is_declaration_kind(i32 %kind) {
entry:
  %is_function = icmp eq i32 %kind, 2
  %is_extern = icmp eq i32 %kind, 17
  %is_declaration = or i1 %is_function, %is_extern
  %result = zext i1 %is_declaration to i32
  ret i32 %result
}

define i32 @weave_symbol_is_call_kind(i32 %kind) {
entry:
  %is_i32 = icmp eq i32 %kind, 9
  %is_i64 = icmp eq i32 %kind, 26
  %is_ptr = icmp eq i32 %kind, 18
  %is_void = icmp eq i32 %kind, 19
  %is_bool = icmp eq i32 %kind, 31
  %integer_call = or i1 %is_i32, %is_i64
  %pointer_or_void = or i1 %is_ptr, %is_void
  %value_call = or i1 %integer_call, %pointer_or_void
  %is_call = or i1 %value_call, %is_bool
  %result = zext i1 %is_call to i32
  ret i32 %result
}

define i32 @weave_symbol_call_is_builtin_print(ptr %ctx, i64 %call_node) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %call_node)
  %is_i32_call = icmp eq i32 %kind, 9
  br i1 %is_i32_call, label %compare, label %no

compare:
  %source = call ptr @weave_emit_source(ptr %ctx)
  %data = call ptr @weave_source_data(ptr %source)
  %name_start = call i64 @weave_ast_text_start(ptr %ast, i64 %call_node)
  %name_len = call i64 @weave_ast_text_len(ptr %ast, i64 %call_node)
  %name = getelementptr inbounds i8, ptr %data, i64 %name_start
  %same = call i32 @weave_bytes_equal(
    ptr %name,
    i64 %name_len,
    ptr @weave.emit.print_name,
    i64 5
  )
  ret i32 %same

no:
  ret i32 0
}

define i32 @weave_symbol_validate_unique_declarations(ptr %ctx) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %count = call i64 @weave_ast_count(ptr %ast)
  br label %outer

outer:
  %i = phi i64 [0, %entry], [%next_i, %outer_continue]
  %outer_done = icmp uge i64 %i, %count
  br i1 %outer_done, label %success, label %outer_kind

outer_kind:
  %kind_i = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %decl_i_status = call i32 @weave_symbol_is_declaration_kind(i32 %kind_i)
  %decl_i = icmp ne i32 %decl_i_status, 0
  br i1 %decl_i, label %inner_prepare, label %outer_continue

inner_prepare:
  %first_j = add i64 %i, 1
  br label %inner

inner:
  %j = phi i64 [%first_j, %inner_prepare], [%next_j, %inner_continue]
  %inner_done = icmp uge i64 %j, %count
  br i1 %inner_done, label %outer_continue, label %inner_kind

inner_kind:
  %kind_j = call i32 @weave_ast_kind(ptr %ast, i64 %j)
  %decl_j_status = call i32 @weave_symbol_is_declaration_kind(i32 %kind_j)
  %decl_j = icmp ne i32 %decl_j_status, 0
  br i1 %decl_j, label %compare, label %inner_continue

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

define i32 @weave_symbol_target_exists(ptr %ctx, i64 %call_node) {
entry:
  %builtin_status = call i32 @weave_symbol_call_is_builtin_print(
    ptr %ctx,
    i64 %call_node
  )
  %is_builtin = icmp ne i32 %builtin_status, 0
  br i1 %is_builtin, label %found, label %prepare

prepare:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %count = call i64 @weave_ast_count(ptr %ast)
  br label %loop

loop:
  %i = phi i64 [0, %prepare], [%next_i, %continue]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %missing, label %check_kind

check_kind:
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %decl_status = call i32 @weave_symbol_is_declaration_kind(i32 %kind)
  %is_declaration = icmp ne i32 %decl_status, 0
  br i1 %is_declaration, label %compare, label %continue

compare:
  %same_status = call i32 @weave_emit_nodes_same_name(
    ptr %ctx,
    i64 %call_node,
    i64 %i
  )
  %same = icmp ne i32 %same_status, 0
  br i1 %same, label %found, label %continue

continue:
  %next_i = add i64 %i, 1
  br label %loop

found:
  ret i32 1

missing:
  ret i32 0
}

define i32 @weave_symbol_validate_call_targets(ptr %ctx) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %count = call i64 @weave_ast_count(ptr %ast)
  br label %loop

loop:
  %i = phi i64 [0, %entry], [%next_i, %continue]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %success, label %check_kind

check_kind:
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %call_status = call i32 @weave_symbol_is_call_kind(i32 %kind)
  %is_call = icmp ne i32 %call_status, 0
  br i1 %is_call, label %lookup, label %continue

lookup:
  %exists_status = call i32 @weave_symbol_target_exists(ptr %ctx, i64 %i)
  %exists = icmp ne i32 %exists_status, 0
  br i1 %exists, label %continue, label %fail

continue:
  %next_i = add i64 %i, 1
  br label %loop

success:
  ret i32 0

fail:
  ret i32 1
}

define i32 @weave_symbol_validate_module(ptr %ctx) {
entry:
  %unique_status = call i32 @weave_symbol_validate_unique_declarations(ptr %ctx)
  %unique_failed = icmp ne i32 %unique_status, 0
  br i1 %unique_failed, label %fail, label %calls

calls:
  %call_status = call i32 @weave_symbol_validate_call_targets(ptr %ctx)
  %calls_failed = icmp ne i32 %call_status, 0
  br i1 %calls_failed, label %fail, label %success

success:
  ret i32 0

fail:
  ret i32 1
}
'''

marker = "; ----------------------------------------------------------------------------\n; weave_emit_llvm\n"
text = replace_once(text, marker, helpers + "\n" + marker, "module validator insertion")

emit_entry = r'''
define i32 @weave_emit_llvm(ptr %source, ptr %ast, i64 %program_node, ptr %out) {
entry:
  %ctx_storage = alloca %weave.EmitContext
  call void @weave_emit_context_init(ptr %ctx_storage, ptr %source, ptr %ast, ptr %out)
  %validation_status = call i32 @weave_symbol_validate_module(ptr %ctx_storage)
  %validation_failed = icmp ne i32 %validation_status, 0
  br i1 %validation_failed, label %fail, label %emit

emit:
  %status = call i32 @weave_emit_program(ptr %ctx_storage, i64 %program_node)
  ret i32 %status

fail:
  ret i32 1
}
'''
text = replace_function(
    text,
    "define i32 @weave_emit_llvm(ptr %source, ptr %ast, i64 %program_node, ptr %out)",
    emit_entry,
)

text = replace_once(
    text,
    ";   1 on any emission failure (allocation, unknown extern, write error).\n"
    ";     The caller should discard `out` rather than write it to disk.",
    ";   1 on symbol-validation or emission failure. Validation runs before the\n"
    ";     module header, so the caller can discard an empty `out` buffer.",
    "emitter result documentation",
)

EMITTER.write_text(text)

run_tests = ROOT / "scripts/run-tests.sh"
run_tests_text = run_tests.read_text()
run_tests_text = replace_once(
    run_tests_text,
    'bash "$ROOT/scripts/run-binding-scope-tests.sh" \\\n  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/binding-scope"\n\n',
    'bash "$ROOT/scripts/run-binding-scope-tests.sh" \\\n  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/binding-scope"\n'
    'bash "$ROOT/scripts/run-module-symbol-tests.sh" \\\n  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/module-symbols"\n\n',
    "normal module-symbol workload",
)
run_tests.write_text(run_tests_text)

coverage = ROOT / "scripts/extend-coverage-with-cli.sh"
coverage_text = coverage.read_text()
coverage_text = replace_once(
    coverage_text,
    "printf '[coverage] regenerate aggregate report\\n' >&2\n",
    "printf '[coverage] extend workload with module symbol cases\\n' >&2\n"
    "WEAVEC0_COVERAGE_OUT=\"$RAW_TSV\" \\\n"
    "  bash \"$ROOT/scripts/run-module-symbol-tests.sh\" \\\n"
    "    \"$INSTRUMENTED_BIN\" \"$BUILD_DIR/module-symbols\"\n\n"
    "printf '[coverage] regenerate aggregate report\\n' >&2\n",
    "coverage module-symbol workload",
)
coverage.write_text(coverage_text)

changelog = ROOT / "CHANGELOG.md"
changelog_text = changelog.read_text()
release_notes = '''## [0.3.4] — 2026-07-25

### Added

- An eleven-case module-symbol ladder covering forward function calls, declared
  extern calls, the built-in `print` lowering, all five undefined call
  categories, duplicate functions, duplicate externs, and function/extern name
  collisions.
- The same symbol workload is included in the instrumented LLVM coverage
  extension.

### Changed

- Functions and externs now share one validated module declaration namespace.
  Forward calls remain valid because validation sees the complete parsed AST.
- The internal `print` pseudo-call is explicitly admitted without requiring a
  source-level declaration; every other call target must resolve to a function
  or extern declaration.

### Fixed

- Undefined call targets now fail before any LLVM module text is emitted.
- Duplicate functions, duplicate externs, and function/extern name collisions
  are rejected deterministically instead of producing invalid LLVM IR.

'''
changelog_text = replace_once(
    changelog_text,
    "## [Unreleased]\n\n## [0.3.3] — 2026-07-25\n",
    "## [Unreleased]\n\n" + release_notes + "## [0.3.3] — 2026-07-25\n",
    "0.3.4 changelog insertion",
)
changelog.write_text(changelog_text)
(ROOT / "VERSION").write_text("0.3.4\n")

subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", "scripts/run-module-symbol-tests.sh"], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", "scripts/run-tests.sh"], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", "scripts/extend-coverage-with-cli.sh"], cwd=ROOT, check=True)
subprocess.run(["bash", "scripts/run-tests.sh"], cwd=ROOT, check=True)

(ROOT / ".github/workflows/apply-module-symbol-validation.yml").unlink()
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
        "fix: validate module declarations and call targets",
    ],
    cwd=ROOT,
    check=True,
)
subprocess.run(
    ["git", "push", "origin", "HEAD:agent/integrate-module-symbol-validation"],
    cwd=ROOT,
    check=True,
)
