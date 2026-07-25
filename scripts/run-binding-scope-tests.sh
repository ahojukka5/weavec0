#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-binding-scope-tests.sh <compiler> <work-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
WORK_DIR="$2"

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

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
count=0

run_failure() {
  local name="$1"
  local source="$2"
  local wir="$WORK_DIR/${name}.wir"
  local ll="$WORK_DIR/${name}.ll"
  local stderr="$WORK_DIR/${name}.stderr"

  printf '%s\n' "$source" > "$wir"
  rm -f "$ll" "$stderr"

  set +e
  "$COMPILER" "$wir" "$ll" > /dev/null 2>"$stderr"
  local status=$?
  set -e

  if [[ "$status" == 0 ]]; then
    printf '[binding-scope] %s: expected compiler failure\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$ll" ]]; then
    printf '[binding-scope] %s: failure produced LLVM IR\n' "$name" >&2
    sed -n '1,120p' "$ll" >&2 || true
    exit 1
  fi
  if ! grep -Fq 'error: LLVM emit failed' "$stderr"; then
    printf '[binding-scope] %s: expected emitter diagnostic\n' "$name" >&2
    sed -n '1,120p' "$stderr" >&2 || true
    exit 1
  fi

  count=$((count + 1))
}

POSITIVE_WIR="$WORK_DIR/cross-function-local-scope.wir"
POSITIVE_LL="$WORK_DIR/cross-function-local-scope.ll"
POSITIVE_BC="$WORK_DIR/cross-function-local-scope.bc"
POSITIVE_EXE="$WORK_DIR/cross-function-local-scope.out"

# The spelling `x` deliberately denotes an i32 local, an i64 local, and an i32
# parameter in three different functions. None may influence another function.
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
    (fn identity
      (params (x i32))
      (returns i32)
      (do
        (return (param_get x))))
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
grep -Fq ' = load i32, ptr %x' "$POSITIVE_LL" || {
  printf '[binding-scope] i32 binding was not emitted as i32\n' >&2
  exit 1
}
grep -Fq ' = load i64, ptr %x' "$POSITIVE_LL" || {
  printf '[binding-scope] second.x was not emitted as i64\n' >&2
  exit 1
}
llvm-as "$POSITIVE_LL" -o "$POSITIVE_BC"
clang -Wno-override-module "$POSITIVE_LL" -o "$POSITIVE_EXE"
set +e
"$POSITIVE_EXE"
positive_status=$?
set -e
if [[ "$positive_status" != 42 ]]; then
  printf '[binding-scope] positive reproducer returned %s, expected 42\n' "$positive_status" >&2
  exit 1
fi
count=$((count + 1))

run_failure undefined-local-get '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (return (local_get missing))))))'

run_failure undefined-param-get '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (return (param_get missing))))))'

run_failure duplicate-parameters '
(core-module (core-version 1) (decls
  (fn duplicate_parameters
    (params (x i32) (x i32))
    (returns i32)
    (do (return (param_get x))))))'

run_failure duplicate-locals '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (let x i32 (const_i32 1))
    (let x i32 (const_i32 2))
    (return (local_get x))))))'

run_failure parameter-local-shadowing '
(core-module (core-version 1) (decls
  (fn parameter_local_shadowing
    (params (x i32))
    (returns i32)
    (do
      (let x i32 (const_i32 2))
      (return (local_get x))))))'

printf '[binding-scope] all %d function-local binding cases passed\n' "$count" >&2
