#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-binding-scope-tests.sh <weavec0> <output-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"

command -v llvm-as >/dev/null 2>&1 || {
  printf '[binding-scope] required tool not found: llvm-as\n' >&2
  exit 1
}
command -v clang >/dev/null 2>&1 || {
  printf '[binding-scope] required tool not found: clang\n' >&2
  exit 1
}
[[ -x "$COMPILER" ]] || {
  printf '[binding-scope] compiler is not executable: %s\n' "$COMPILER" >&2
  exit 1
}

run_failure() {
  local name="$1"
  local source="$2"
  local wir="$OUT_DIR/$name.wir"
  local ll="$OUT_DIR/$name.ll"
  local stderr="$OUT_DIR/$name.stderr"

  printf '%s\n' "$source" > "$wir"
  rm -f "$ll" "$stderr"
  set +e
  "$COMPILER" "$wir" "$ll" > /dev/null 2>"$stderr"
  local status=$?
  set -e

  [[ "$status" != 0 ]] || {
    printf '[binding-scope] %s unexpectedly compiled successfully\n' "$name" >&2
    exit 1
  }
  [[ ! -s "$ll" ]] || {
    printf '[binding-scope] %s produced LLVM IR on failure\n' "$name" >&2
    sed -n '1,120p' "$ll" >&2 || true
    exit 1
  }
  grep -q 'LLVM emit failed' "$stderr" || {
    printf '[binding-scope] %s did not report emitter failure\n' "$name" >&2
    sed -n '1,120p' "$stderr" >&2 || true
    exit 1
  }
  printf '[binding-scope] ok %s\n' "$name" >&2
}

POSITIVE_WIR="$OUT_DIR/cross_function_local_scope.wir"
POSITIVE_LL="$OUT_DIR/cross_function_local_scope.ll"
POSITIVE_BC="$OUT_DIR/cross_function_local_scope.bc"
POSITIVE_EXE="$OUT_DIR/cross_function_local_scope.out"

cat > "$POSITIVE_WIR" <<'WIR'
(core-module
  (core-version 1)
  (decls
    (fn first
      (params)
      (returns i32)
      (do
        (let x i32 (const_i32 42))
        (return (local_get x))))
    (fn second
      (params)
      (returns i32)
      (do
        (let x i64 (const_i64 7))
        (return (cast_i64_to_i32 (local_get x)))))
    (fn main
      (params)
      (returns i32)
      (do
        (return (call_i32 first))))))
WIR

rm -f "$POSITIVE_LL" "$POSITIVE_BC" "$POSITIVE_EXE"
"$COMPILER" "$POSITIVE_WIR" "$POSITIVE_LL"
[[ -s "$POSITIVE_LL" ]] || {
  printf '[binding-scope] positive reproducer produced no LLVM IR\n' >&2
  exit 1
}
grep -q ' = load i32, ptr %x' "$POSITIVE_LL" || {
  printf '[binding-scope] first.x was not emitted as i32\n' >&2
  exit 1
}
grep -q ' = load i64, ptr %x' "$POSITIVE_LL" || {
  printf '[binding-scope] second.x was not emitted as i64\n' >&2
  exit 1
}
llvm-as "$POSITIVE_LL" -o "$POSITIVE_BC"
clang -Wno-override-module "$POSITIVE_LL" -o "$POSITIVE_EXE"
set +e
"$POSITIVE_EXE"
positive_status=$?
set -e
[[ "$positive_status" == 42 ]] || {
  printf '[binding-scope] positive reproducer returned %s, expected 42\n' "$positive_status" >&2
  exit 1
}
printf '[binding-scope] ok cross_function_local_scope\n' >&2

run_failure undefined_local_get '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (return (local_get missing))))))'

run_failure undefined_param_get '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (return (param_get missing))))))'

run_failure duplicate_parameters '
(core-module (core-version 1) (decls
  (fn duplicate_parameters
    (params (x i32) (x i32))
    (returns i32)
    (do (return (param_get x))))))'

run_failure duplicate_locals '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (let x i32 (const_i32 1))
    (let x i32 (const_i32 2))
    (return (local_get x))))))'

run_failure parameter_local_shadowing '
(core-module (core-version 1) (decls
  (fn parameter_local_shadowing
    (params (x i32))
    (returns i32)
    (do
      (let x i32 (const_i32 2))
      (return (local_get x))))))'

printf '[binding-scope] all function-local binding tests passed\n' >&2
