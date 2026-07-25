#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-integer-range-negative-matrix.sh <compiler> <work-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
WORK_DIR="$2"

[[ -x "$COMPILER" ]] || {
  printf '[integer-range-negative] compiler is not executable: %s\n' "$COMPILER" >&2
  exit 1
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
count=0

run_case() {
  local name="$1"
  local expression="$2"
  local wir="$WORK_DIR/${name}.wir"
  local ll="$WORK_DIR/${name}.ll"
  local stderr="$WORK_DIR/${name}.stderr"

  cat > "$wir" <<CASE
(core-module
  (core-version 1)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return $expression)))))
CASE
  rm -f "$ll" "$stderr"

  set +e
  "$COMPILER" "$wir" "$ll" > /dev/null 2>"$stderr"
  local status=$?
  set -e

  if [[ "$status" == 0 ]]; then
    printf '[integer-range-negative] %s: expected compiler failure\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$ll" ]]; then
    printf '[integer-range-negative] %s: failure produced LLVM IR\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq 'error: lexing failed' "$stderr"; then
    printf '[integer-range-negative] %s: expected lexing diagnostic\n' "$name" >&2
    sed -n '1,40p' "$stderr" >&2 || true
    exit 1
  fi

  count=$((count + 1))
}

run_case i32-max-plus-one '(const_i32 2147483648)'
run_case i32-min-minus-one '(const_i32 -2147483649)'
run_case i64-max-plus-one '(cast_i64_to_i32 (const_i64 9223372036854775808))'
run_case i64-min-minus-one '(cast_i64_to_i32 (const_i64 -9223372036854775809))'
run_case huge-positive '(cast_i64_to_i32 (const_i64 9999999999999999999999999999999999999999999999999999999999999999))'
run_case huge-negative '(cast_i64_to_i32 (const_i64 -9999999999999999999999999999999999999999999999999999999999999999))'

printf '[integer-range-negative] all %d generated cases passed\n' "$count" >&2
