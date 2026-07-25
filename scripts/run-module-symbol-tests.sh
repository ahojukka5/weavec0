#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-module-symbol-tests.sh <compiler> <work-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
WORK_DIR="$2"

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

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
count=0

run_positive() {
  local name="$1"
  local expected_exit="$2"
  local source="$3"
  local wir="$WORK_DIR/${name}.wir"
  local ll="$WORK_DIR/${name}.ll"
  local bc="$WORK_DIR/${name}.bc"
  local exe="$WORK_DIR/${name}.out"

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
  if [[ "$status" != "$expected_exit" ]]; then
    printf '[module-symbols] %s returned %s, expected %s\n' \
      "$name" "$status" "$expected_exit" >&2
    exit 1
  fi
  count=$((count + 1))
}

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
    printf '[module-symbols] %s: expected compiler failure\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$ll" ]]; then
    printf '[module-symbols] %s: failure produced LLVM IR\n' "$name" >&2
    sed -n '1,120p' "$ll" >&2 || true
    exit 1
  fi
  if ! grep -Fq 'error: LLVM emit failed' "$stderr"; then
    printf '[module-symbols] %s: expected emitter diagnostic\n' "$name" >&2
    sed -n '1,120p' "$stderr" >&2 || true
    exit 1
  fi
  count=$((count + 1))
}

# Functions and externs share one declaration namespace, and forward function
# calls are valid because the module validator sees the complete parsed AST.
run_positive forward-function-call 42 '
(core-module (core-version 1) (decls
  (fn first (params) (returns i32)
    (do (return (call_i32 second))))
  (fn second (params) (returns i32)
    (do (return (const_i32 42))))
  (fn main (params) (returns i32)
    (do (return (call_i32 first))))))'

run_positive declared-extern-call 42 '
(core-module (core-version 1) (decls
  (extern puts (params (text ptr)) (returns i32))
  (fn main (params) (returns i32) (do
    (call_i32 puts (const_string_ptr "symbol target ok"))
    (return (const_i32 42))))))'

# `print` is the one Stage 0 pseudo-call. It does not name a WIR declaration,
# although its lowering still requires the ordinary admitted puts declaration.
run_positive builtin-print 42 '
(core-module (core-version 1) (decls
  (extern puts (params (text ptr)) (returns i32))
  (fn main (params) (returns i32) (do
    (print (const_string "builtin target ok"))
    (return (const_i32 42))))))'

run_failure undefined-call-i32 '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32)
    (do (return (call_i32 missing))))))'

run_failure undefined-call-i64 '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32)
    (do (return (cast_i64_to_i32 (call_i64 missing)))))))'

run_failure undefined-call-ptr '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (let p ptr (call_ptr missing))
    (return (const_i32 42))))))'

run_failure undefined-call-bool '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (if (condition (call_bool missing))
      (then (do (return (const_i32 42))))
      (else (do (return (const_i32 0)))))))))'

run_failure undefined-call-void '
(core-module (core-version 1) (decls
  (fn main (params) (returns i32) (do
    (call_void missing)
    (return (const_i32 42))))))'

run_failure duplicate-functions '
(core-module (core-version 1) (decls
  (fn f (params) (returns i32) (do (return (const_i32 1))))
  (fn f (params) (returns i32) (do (return (const_i32 2))))))'

run_failure duplicate-externs '
(core-module (core-version 1) (decls
  (extern puts (params (text ptr)) (returns i32))
  (extern puts (params (text ptr)) (returns i32))))'

run_failure function-extern-collision '
(core-module (core-version 1) (decls
  (extern puts (params (text ptr)) (returns i32))
  (fn puts (params) (returns i32)
    (do (return (const_i32 42))))))'

printf '[module-symbols] all %d module symbol cases passed\n' "$count" >&2
