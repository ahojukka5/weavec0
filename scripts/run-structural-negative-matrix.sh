#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-structural-negative-matrix.sh <compiler> <work-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
WORK_DIR="$2"

[[ -x "$COMPILER" ]] || {
  printf '[structural-negative] compiler is not executable: %s\n' "$COMPILER" >&2
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
    printf '[structural-negative] %s: expected compiler failure\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$ll" ]]; then
    printf '[structural-negative] %s: failure produced LLVM IR\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$stderr"; then
    printf '[structural-negative] %s: expected diagnostic containing %s\n' \
      "$name" "$expected" >&2
    sed -n '1,40p' "$stderr" >&2 || true
    exit 1
  fi

  count=$((count + 1))
}

run_case empty 'error: parsing failed' ''
run_case empty-list 'error: parsing failed' '()'
run_case module-empty 'error: parsing failed' '(core-module)'
run_case module-no-decls 'error: parsing failed' \
  '(core-module (core-version 1))'
run_case module-truncated-decls 'error: parsing failed' \
  '(core-module (core-version 1) (decls)'
run_case version-missing 'error: parsing failed' \
  '(core-module (core-version) (decls))'
run_case version-extra 'error: parsing failed' \
  '(core-module (core-version 1 2) (decls))'
run_case wrong-decls 'error: parsing failed' \
  '(core-module (core-version 1) (params))'
run_case trailing-token 'error: parsing failed' \
  '(core-module (core-version 1) (decls)) junk'
run_case unknown-decl 'error: parsing failed' \
  '(core-module (core-version 1) (decls (bogus)))'

run_case fn-missing-name 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn)))'
run_case fn-missing-params 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main)))'
run_case fn-missing-returns 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params))))'
run_case fn-return-type-missing 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns))))'
run_case fn-return-type-invalid 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns foo) (do))))'
run_case fn-body-missing 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32))))'
run_case fn-body-wrong 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (then))))'
run_case fn-extra 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do) junk)))'

run_case params-bare 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params x) (returns i32) (do))))'
run_case param-type-missing 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params (x)) (returns i32) (do))))'
run_case param-extra 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params (x i32 i64)) (returns i32) (do))))'
run_case param-type-invalid 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params (x foo)) (returns i32) (do))))'

run_case if-no-condition 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if)))))'
run_case if-condition-empty 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if (condition))))))'
run_case if-condition-extra 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if (condition (const_bool true) (const_bool false)))))))'
run_case if-missing-then 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if (condition (const_bool true)))))))'
run_case if-then-no-do 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if (condition (const_bool true)) (then))))))'
run_case if-missing-else 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if (condition (const_bool true)) (then (do)))))))'
run_case if-else-no-do 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if (condition (const_bool true)) (then (do)) (else))))))'
run_case if-extra 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (if (condition (const_bool true)) (then (do)) (else (do)) junk)))))'

run_case while-no-condition 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (while)))))'
run_case while-condition-empty 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (while (condition))))))'
run_case while-condition-extra 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (while (condition (const_bool true) (const_bool false)))))))'
run_case while-no-body 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (while (condition (const_bool true)))))))'
run_case while-body-wrong 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (while (condition (const_bool true)) (then (do)))))))'

run_case block-truncated 'error: parsing failed' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (return (const_i32 42))))'
run_case unknown-stmt 'error: unknown operator' \
  '(core-module (core-version 1) (decls (fn main (params) (returns i32) (do (bogus)))))'

printf '[structural-negative] all %d generated structural cases passed\n' \
  "$count" >&2
