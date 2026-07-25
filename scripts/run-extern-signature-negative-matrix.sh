#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-extern-signature-negative-matrix.sh <compiler> <work-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
WORK_DIR="$2"

[[ -x "$COMPILER" ]] || {
  printf '[extern-signature-negative] compiler is not executable: %s\n' "$COMPILER" >&2
  exit 1
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
count=0

run_case() {
  local name="$1"
  local extern_decl="$2"
  local wir="$WORK_DIR/${name}.wir"
  local ll="$WORK_DIR/${name}.ll"
  local stderr="$WORK_DIR/${name}.stderr"

  cat > "$wir" <<CASE
(core-module
  (core-version 1)
  (decls
    $extern_decl))
CASE
  rm -f "$ll" "$stderr"

  set +e
  "$COMPILER" "$wir" "$ll" > /dev/null 2>"$stderr"
  local status=$?
  set -e

  if [[ "$status" == 0 ]]; then
    printf '[extern-signature-negative] %s: expected compiler failure\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$ll" ]]; then
    printf '[extern-signature-negative] %s: failure produced LLVM IR\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq 'error: parsing failed' "$stderr"; then
    printf '[extern-signature-negative] %s: expected parsing diagnostic\n' "$name" >&2
    sed -n '1,40p' "$stderr" >&2 || true
    exit 1
  fi

  count=$((count + 1))
}

run_abi_cases() {
  local name="$1"
  local valid_params="$2"
  local wrong_params="$3"
  local valid_return="$4"
  local wrong_return="$5"

  run_case "${name}-wrong-param-count" \
    "(extern $name (params) (returns $valid_return))"
  run_case "${name}-wrong-param-type" \
    "(extern $name (params $wrong_params) (returns $valid_return))"
  run_case "${name}-wrong-return-type" \
    "(extern $name (params $valid_params) (returns $wrong_return))"
}

# Every admitted extern is checked for parameter count, parameter type, and
# return type mismatches. Existing positive test 101 covers the exact valid ABI.
run_abi_cases puts '(text ptr)' '(text i32)' i32 i64
run_abi_cases malloc '(size i64)' '(size i32)' ptr i64
run_abi_cases free '(p ptr)' '(p i32)' void i64
run_abi_cases realloc '(p ptr) (size i64)' '(p i32) (size i64)' ptr i64
run_abi_cases memcpy '(dst ptr) (src ptr) (n i64)' '(dst i32) (src ptr) (n i64)' ptr i64
run_abi_cases strlen '(s ptr)' '(s i32)' i64 i32
run_abi_cases strcmp '(a ptr) (b ptr)' '(a i32) (b ptr)' i32 i64
run_abi_cases strncmp '(a ptr) (b ptr) (n i64)' '(a i32) (b ptr) (n i64)' i32 i64
run_abi_cases atoi '(s ptr)' '(s i32)' i32 i64
run_abi_cases putchar '(ch i32)' '(ch ptr)' i32 i64
run_abi_cases weave_rt_read_file '(path ptr) (out_len ptr)' '(path i32) (out_len ptr)' ptr i64
run_abi_cases weave_rt_write_file '(path ptr) (data ptr) (length i64)' '(path i32) (data ptr) (length i64)' i32 i64
run_abi_cases weave_rt_fatal '(message ptr)' '(message i32)' void i64

# Structural signature failures: missing, reordered, duplicated, malformed,
# and extra forms must all fail before the parser discards the extern tail.
run_case missing-params '(extern malloc (returns ptr))'
run_case missing-returns '(extern malloc (params (size i64)))'
run_case reordered-forms '(extern malloc (returns ptr) (params (size i64)))'
run_case duplicate-params '(extern malloc (params (size i64)) (params (size i64)) (returns ptr))'
run_case duplicate-returns '(extern malloc (params (size i64)) (returns ptr) (returns ptr))'
run_case missing-param-name '(extern malloc (params (i64)) (returns ptr))'
run_case missing-param-type '(extern malloc (params (size)) (returns ptr))'
run_case extra-param-token '(extern malloc (params (size i64 extra)) (returns ptr))'
run_case invalid-param-type '(extern malloc (params (size bool)) (returns ptr))'
run_case missing-return-type '(extern malloc (params (size i64)) (returns))'
run_case invalid-return-type '(extern malloc (params (size i64)) (returns bool))'
run_case extra-return-token '(extern malloc (params (size i64)) (returns ptr i32))'
run_case extra-form '(extern malloc (params (size i64)) (returns ptr) (do))'
run_case too-many-params '(extern memcpy (params (a ptr) (b ptr) (c i64) (d i32)) (returns ptr))'

printf '[extern-signature-negative] all %d generated cases passed\n' "$count" >&2
