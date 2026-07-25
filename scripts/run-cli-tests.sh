#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'usage: scripts/run-cli-tests.sh <compiler> <work-dir>\n' >&2
  exit 2
fi

COMPILER="$1"
WORK_DIR="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -x "$COMPILER" ]] || {
  printf '[cli-tests] compiler is not executable: %s\n' "$COMPILER" >&2
  exit 1
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

run_expected_failure() {
  local name="$1"
  local expected="$2"
  shift 2

  local stdout="$WORK_DIR/${name}.stdout"
  local stderr="$WORK_DIR/${name}.stderr"

  set +e
  "$@" >"$stdout" 2>"$stderr"
  local status=$?
  set -e

  if [[ "$status" == 0 ]]; then
    printf '[cli-tests] %s: expected failure, got success\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$stderr"; then
    printf '[cli-tests] %s: missing diagnostic: %s\n' "$name" "$expected" >&2
    sed -n '1,120p' "$stderr" >&2 || true
    exit 1
  fi
  printf '[cli-tests] ok %s\n' "$name" >&2
}

# main -> usage diagnostic
run_expected_failure \
  usage \
  'usage: weavec0 input.wir output.ll' \
  "$COMPILER"

# driver -> input read diagnostic
read_output="$WORK_DIR/read-failure.ll"
run_expected_failure \
  read-failure \
  'error: could not read file' \
  "$COMPILER" "$WORK_DIR/does-not-exist.wir" "$read_output"
[[ ! -e "$read_output" ]] || {
  printf '[cli-tests] read-failure unexpectedly created output\n' >&2
  exit 1
}

# driver -> lexer diagnostic
lex_output="$WORK_DIR/lex-failure.ll"
run_expected_failure \
  lex-failure \
  'error: lexing failed' \
  "$COMPILER" "$ROOT/test/cli_invalid_byte.wir" "$lex_output"
[[ ! -e "$lex_output" ]] || {
  printf '[cli-tests] lex-failure unexpectedly created output\n' >&2
  exit 1
}

# driver -> output write diagnostic. The parent directory intentionally does
# not exist, so the compiler completes lex/parse/emit before runtime I/O fails.
write_output="$WORK_DIR/missing-parent/write-failure.ll"
run_expected_failure \
  write-failure \
  'error: could not write file' \
  "$COMPILER" "$ROOT/test/02_return_42.wir" "$write_output"
[[ ! -e "$write_output" ]] || {
  printf '[cli-tests] write-failure unexpectedly created output\n' >&2
  exit 1
}

printf '[cli-tests] all CLI error-path tests passed\n' >&2
