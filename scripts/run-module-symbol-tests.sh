#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-module-symbol-tests.sh <weavec0> <output-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"

for tool in llvm-as clang; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf '[module-symbols] required tool not found: %s\n' "$tool" >&2
    exit 1
  }
done
[[ -x "$COMPILER" ]] || {
  printf '[module-symbols] compiler is not executable: %s\n' "$COMPILER" >&2
  exit 1
}

run_positive() {
  local name="$1"
  local expected_exit="$2"
  local source="$3"
  local wir="$OUT_DIR/$name.wir"
  local ll="$OUT_DIR/$name.ll"
  local bc="$OUT_DIR/$name.bc"
  local exe="$OUT_DIR/$name.out"

  printf '%s\n' "$source" > "$wir"
  rm -f "$ll" "$bc" "$exe"
  "$COMPILER" "$wir" "$ll"
  [[ -s "$ll" ]] || {
    printf '[module-symbols] %s produced no LLVM IR\n' "$name" >&2
    exit 1
  }
  llvm-as "$ll" -o "$bc"
  clang -Wno-override-module "$ll" -o "$exe"
  set +e
  "$exe" > /dev/null
  local status=$?
  set -e
  [[ "$status" == "$expected_exit" ]] || {
    printf '[module-symbols] %s returned %s, expected %s\n' \
      "$name" "$status" "$expected_exit" >&2
    exit 1
  }
  printf '[module-symbols] ok %s\n' "$name" >&2
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
    printf '[module-symbols] %s unexpectedly compiled successfully\n' "$name" >&2
    exit 1
  }
  [[ ! -s "$ll" ]] || {
    printf '[module-symbols] %s produced LLVM IR on failure\n' "$name" >&2
    sed -n '1,120p' "$ll" >&2 || true
    exit 1
  }
  grep -Fq 'error: LLVM emit failed' "$stderr" || {
    printf '[module-symbols] %s did not report emitter failure\n' "$name" >&2
    sed -n '1,120p' "$stderr" >&2 || true
    exit 1
  }
  printf '[module-symbols] ok %s\n' "$name" >&2
}

run_positive forward_function_call 42 '
(core-module (core-version 1) (decls
  (fn first (params) (returns i32)
    (do (return (call_i32 second))))
  (fn second (params) (returns i32)
    (do (return (const_i32 42))))
  (fn main (params) (returns i32)
    (do (return (call_i32 first))))))'

run_positive declared_extern_call 42 '
(core-module (core-version 1) (decls
  (extern puts (params (text ptr)) (returns i32))
  (fn main (params) (returns i32) (do
    (call_i32 puts (const_string_ptr "symbol target ok"))
    (return (const_i32 42))))))'

run_failure undefined_call_i32 '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32)
    (do (return (call_i32 missing))))))'

run_failure undefined_call_i64 '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32)
    (do (return (cast_i64_to_i32 (call_i64 missing)))))))'

run_failure undefined_call_ptr '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (let p ptr (call_ptr missing))
    (return (const_i32 42))))))'

run_failure undefined_call_bool '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (if (condition (call_bool missing))
      (then (do (return (const_i32 42))))
      (else (do (return (const_i32 0)))))))))'

run_failure undefined_call_void '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (call_void missing)
    (return (const_i32 42))))))'

run_failure duplicate_functions '
(core-module (core-version 1) (decls
  (fn f (params) (returns i32) (do (return (const_i32 1))))
  (fn f (params) (returns i32) (do (return (const_i32 2))))))'

run_failure duplicate_externs '
(core-module (core-version 1) (decls
  (extern puts (params (text ptr)) (returns i32))
  (extern puts (params (text ptr)) (returns i32))))'

run_failure function_extern_collision '
(core-module (core-version 1) (decls
  (extern puts (params (text ptr)) (returns i32))
  (fn puts (params) (returns i32)
    (do (return (const_i32 42))))))'

printf '[module-symbols] all module symbol tests passed\n' >&2
