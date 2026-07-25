#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/coverage"
INSTRUMENTED_BIN="$BUILD_DIR/weavec0-coverage"
MAP_TSV="$BUILD_DIR/coverage-map.tsv"
RAW_TSV="$BUILD_DIR/coverage-raw.tsv"
REPORT_JSON="$BUILD_DIR/coverage-report.json"

for path in "$INSTRUMENTED_BIN" "$MAP_TSV" "$RAW_TSV"; do
  [[ -e "$path" ]] || {
    printf '[coverage] missing prerequisite: %s\n' "$path" >&2
    printf '[coverage] run scripts/run-coverage.sh first\n' >&2
    exit 1
  }
done

printf '[coverage] extend workload with CLI error paths\n' >&2
WEAVEC0_COVERAGE_OUT="$RAW_TSV" \
  bash "$ROOT/scripts/run-cli-tests.sh" \
    "$INSTRUMENTED_BIN" "$BUILD_DIR/cli-tests"

printf '[coverage] extend workload with generated parser-negative matrix\n' >&2
WEAVEC0_COVERAGE_OUT="$RAW_TSV" \
  bash "$ROOT/scripts/run-parser-negative-matrix.sh" \
    "$INSTRUMENTED_BIN" "$BUILD_DIR/parser-negative-matrix"

printf '[coverage] extend workload with structural-negative matrix\n' >&2
WEAVEC0_COVERAGE_OUT="$RAW_TSV" \
  bash "$ROOT/scripts/run-structural-negative-matrix.sh" \
    "$INSTRUMENTED_BIN" "$BUILD_DIR/structural-negative-matrix"

printf '[coverage] extend workload with extern-signature matrix\n' >&2
WEAVEC0_COVERAGE_OUT="$RAW_TSV" \
  bash "$ROOT/scripts/run-extern-signature-negative-matrix.sh" \
    "$INSTRUMENTED_BIN" "$BUILD_DIR/extern-signature-negative-matrix"

printf '[coverage] extend workload with function-local binding cases\n' >&2
WEAVEC0_COVERAGE_OUT="$RAW_TSV" \
  bash "$ROOT/scripts/run-binding-scope-tests.sh" \
    "$INSTRUMENTED_BIN" "$BUILD_DIR/binding-scope"

printf '[coverage] extend workload with module-symbol cases\n' >&2
WEAVEC0_COVERAGE_OUT="$RAW_TSV" \
  bash "$ROOT/scripts/run-module-symbol-tests.sh" \
    "$INSTRUMENTED_BIN" "$BUILD_DIR/module-symbols"

printf '[coverage] regenerate aggregate report\n' >&2
python3 "$ROOT/scripts/report_llvm_coverage.py" \
  --map "$MAP_TSV" \
  --raw "$RAW_TSV" \
  --json "$REPORT_JSON" \
  --fail-under-functions "${WEAVEC0_MIN_FUNCTION_COVERAGE:-0}" \
  --fail-under-blocks "${WEAVEC0_MIN_BLOCK_COVERAGE:-0}" \
  --fail-under-branch-outcomes "${WEAVEC0_MIN_BRANCH_OUTCOME_COVERAGE:-0}"
