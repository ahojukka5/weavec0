#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-parser-negative-matrix.sh <compiler> <work-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
WORK_DIR="$2"

[[ -x "$COMPILER" ]] || {
  printf '[negative-matrix] compiler is not executable: %s\n' "$COMPILER" >&2
  exit 1
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
count=0

run_case() {
  local name="$1"
  local expected="$2"
  local source="$3"
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
    printf '[negative-matrix] %s: expected compiler failure\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$ll" ]]; then
    printf '[negative-matrix] %s: failure produced LLVM IR\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$stderr"; then
    printf '[negative-matrix] %s: expected diagnostic containing %s\n' \
      "$name" "$expected" >&2
    sed -n '1,40p' "$stderr" >&2 || true
    exit 1
  fi

  count=$((count + 1))
}

expr_program() {
  printf '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (return %s)))))' "$1"
}

stmt_program() {
  printf '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do %s (return (const_i32 42))))))' "$1"
}

binary_matrix() {
  local operand="$1"
  shift

  local op
  for op in "$@"; do
    run_case "${op}-too-few" 'error: invalid operator arity' \
      "$(expr_program "($op $operand)")"
    run_case "${op}-too-many" 'error: invalid operator arity' \
      "$(expr_program "($op $operand $operand $operand)")"
  done
}

binary_matrix '(const_i32 1)' \
  add_i32 sub_i32 mul_i32 div_i32 mod_i32 \
  eq_i32 ne_i32 lt_i32 le_i32 gt_i32 ge_i32
binary_matrix '(const_i64 1)' \
  add_i64 sub_i64 mul_i64 eq_i64 ne_i64 lt_i64 le_i64
binary_matrix '(const_bool true)' and_bool or_bool
binary_matrix '(const_null)' eq_ptr ne_ptr

run_case ptr_add-too-few 'error: parsing failed' \
  "$(expr_program '(ptr_add (const_null))')"
run_case ptr_add-too-many 'error: parsing failed' \
  "$(expr_program '(ptr_add (const_null) (const_i64 0) (const_i64 1))')"

unary_case() {
  local op="$1"
  local operand="$2"

  run_case "${op}-too-few" 'error: parsing failed' \
    "$(expr_program "($op)")"
  run_case "${op}-too-many" 'error: parsing failed' \
    "$(expr_program "($op $operand $operand)")"
}

unary_case cast_i64_to_i32 '(const_i64 1)'
unary_case cast_i32_to_i64 '(const_i32 1)'
unary_case not_bool '(const_bool true)'
unary_case load_i64 '(const_null)'
unary_case load_i32 '(const_null)'
unary_case load_ptr '(const_null)'
unary_case load_u8 '(const_null)'

run_case const_i32-too-few 'error: parsing failed' \
  "$(expr_program '(const_i32)')"
run_case const_i32-too-many 'error: parsing failed' \
  "$(expr_program '(const_i32 1 2)')"
run_case const_i64-too-few 'error: parsing failed' \
  "$(expr_program '(const_i64)')"
run_case const_i64-too-many 'error: parsing failed' \
  "$(expr_program '(const_i64 1 2)')"
run_case const_bool-too-few 'error: parsing failed' \
  "$(expr_program '(const_bool)')"
run_case const_bool-too-many 'error: parsing failed' \
  "$(expr_program '(const_bool true false)')"
run_case const_string_ptr-too-few 'error: parsing failed' \
  "$(expr_program '(const_string_ptr)')"
run_case const_string_ptr-too-many 'error: parsing failed' \
  "$(expr_program '(const_string_ptr "a" "b")')"
run_case const_null-too-many 'error: parsing failed' \
  "$(expr_program '(const_null 1)')"
run_case param_get-too-few 'error: parsing failed' \
  "$(expr_program '(param_get)')"
run_case param_get-too-many 'error: parsing failed' \
  "$(expr_program '(param_get x y)')"
run_case local_get-too-few 'error: parsing failed' \
  "$(expr_program '(local_get)')"
run_case local_get-too-many 'error: parsing failed' \
  "$(expr_program '(local_get x y)')"

for call in call_i32 call_i64 call_ptr call_void call_bool; do
  run_case "${call}-missing-callee" 'error: parsing failed' \
    "$(expr_program "($call)")"
done

run_case return-too-few 'error: parsing failed' \
  "$(stmt_program '(return)')"
run_case return-too-many 'error: parsing failed' \
  "$(stmt_program '(return (const_i32 1) (const_i32 2))')"
run_case return_void-too-many 'error: parsing failed' \
  "$(stmt_program '(return_void (const_i32 1))')"
run_case set-too-few 'error: parsing failed' \
  "$(stmt_program '(set x)')"
run_case set-too-many 'error: parsing failed' \
  "$(stmt_program '(set x (const_i32 1) (const_i32 2))')"
run_case let-too-few 'error: parsing failed' \
  "$(stmt_program '(let x i32)')"
run_case let-too-many 'error: parsing failed' \
  "$(stmt_program '(let x i32 (const_i32 1) (const_i32 2))')"

store_case() {
  local op="$1"
  local value="$2"

  run_case "${op}-too-few" 'error: parsing failed' \
    "$(stmt_program "($op (const_null))")"
  run_case "${op}-too-many" 'error: parsing failed' \
    "$(stmt_program "($op (const_null) $value $value)")"
}

store_case store_i64 '(const_i64 1)'
store_case store_i32 '(const_i32 1)'
store_case store_ptr '(const_null)'
store_case store_i8 '(const_i32 1)'

printf '[negative-matrix] all %d generated parser-negative cases passed\n' \
  "$count" >&2
