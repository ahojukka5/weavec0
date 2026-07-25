#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/coverage"
MANIFEST="$ROOT/test/manifest.txt"
WEAVEC1_DIR=""

usage() {
  cat <<'EOF'
usage: bash scripts/run-coverage.sh [--weavec1-dir PATH]

Build and verify weavec0, instrument the linked handwritten LLVM IR, run the
complete Stage 0 test corpus through the instrumented compiler, and optionally
compile the pinned weavec1 module corpus as an additional production workload.

Coverage thresholds can be set with:
  WEAVEC0_MIN_FUNCTION_COVERAGE
  WEAVEC0_MIN_BLOCK_COVERAGE
  WEAVEC0_MIN_BRANCH_OUTCOME_COVERAGE
EOF
}

while (($#)); do
  case "$1" in
    --weavec1-dir)
      (($# >= 2)) || { printf 'missing value for --weavec1-dir\n' >&2; exit 2; }
      WEAVEC1_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[coverage] required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

for tool in bash python3 clang llvm-as llvm-dis; do
  require_tool "$tool"
done

printf '[coverage] run correctness and golden ladder first\n' >&2
(cd "$ROOT" && ./build.sh)

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/test-output" "$BUILD_DIR/weavec1-output"

LINKED_LL="$BUILD_DIR/weavec0.linked.ll"
INSTRUMENTED_LL="$BUILD_DIR/weavec0.instrumented.ll"
INSTRUMENTED_BC="$BUILD_DIR/weavec0.instrumented.bc"
INSTRUMENTED_BIN="$BUILD_DIR/weavec0-coverage"
MAP_TSV="$BUILD_DIR/coverage-map.tsv"
RAW_TSV="$BUILD_DIR/coverage-raw.tsv"
REPORT_JSON="$BUILD_DIR/coverage-report.json"
RUNTIME_C="$BUILD_DIR/coverage-runtime.c"
SURFACE_JSON="$BUILD_DIR/bootstrap-surface.json"

printf '[coverage] disassemble linked compiler bitcode\n' >&2
llvm-dis "$ROOT/build/bootstrap-tests/weavec0.bc" -o "$LINKED_LL"

printf '[coverage] instrument basic blocks and conditional branches\n' >&2
python3 "$ROOT/scripts/instrument_llvm_coverage.py" \
  --input "$LINKED_LL" \
  --src-dir "$ROOT/src" \
  --output "$INSTRUMENTED_LL" \
  --map "$MAP_TSV" \
  --runtime "$RUNTIME_C"

llvm-as "$INSTRUMENTED_LL" -o "$INSTRUMENTED_BC"
clang -Wno-override-module "$INSTRUMENTED_BC" "$ROOT/runtime.c" "$RUNTIME_C" \
  -o "$INSTRUMENTED_BIN"

: > "$RAW_TSV"

run_compiler_case() {
  local kind="$1"
  local name="$2"
  local src="$ROOT/test/${name}.wir"
  local ll="$BUILD_DIR/test-output/${name}.ll"
  local stderr="$BUILD_DIR/test-output/${name}.stderr"
  rm -f "$ll" "$stderr"

  set +e
  WEAVEC0_COVERAGE_OUT="$RAW_TSV" "$INSTRUMENTED_BIN" "$src" "$ll" \
    > /dev/null 2>"$stderr"
  local status=$?
  set -e

  case "$kind" in
    pass)
      [[ "$status" == 0 ]] || {
        printf '[coverage] positive case failed under instrumentation: %s\n' "$name" >&2
        sed -n '1,120p' "$stderr" >&2 || true
        exit 1
      }
      [[ -s "$ll" ]] || {
        printf '[coverage] positive case produced no LLVM IR: %s\n' "$name" >&2
        exit 1
      }
      ;;
    fail)
      [[ "$status" != 0 ]] || {
        printf '[coverage] negative case succeeded under instrumentation: %s\n' "$name" >&2
        exit 1
      }
      ;;
    *)
      printf '[coverage] unknown manifest kind: %s\n' "$kind" >&2
      exit 1
      ;;
  esac
}

printf '[coverage] run Stage 0 WIR corpus\n' >&2
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" ]] && continue
  read -r kind name rest <<<"$line"
  run_compiler_case "$kind" "$name"
done < "$MANIFEST"

if [[ -n "$WEAVEC1_DIR" ]]; then
  [[ -f "$WEAVEC1_DIR/build.sh" ]] || {
    printf '[coverage] invalid weavec1 checkout: %s\n' "$WEAVEC1_DIR" >&2
    exit 1
  }

  printf '[coverage] compile the pinned weavec1 production corpus\n' >&2
  mapfile -t modules < <(
    awk '
      /^MODULES=\(/ { in_modules=1; next }
      in_modules && /^\)/ { exit }
      in_modules {
        sub(/#.*/, "")
        gsub(/[[:space:]\"]/, "")
        if (length($0)) print $0
      }
    ' "$WEAVEC1_DIR/build.sh"
  )
  for module in "${modules[@]}"; do
    src="$WEAVEC1_DIR/src/${module}.wir"
    ll="$BUILD_DIR/weavec1-output/${module}.ll"
    stderr="$BUILD_DIR/weavec1-output/${module}.stderr"
    [[ -f "$src" ]] || {
      printf '[coverage] missing pinned weavec1 module: %s\n' "$src" >&2
      exit 1
    }
    set +e
    WEAVEC0_COVERAGE_OUT="$RAW_TSV" "$INSTRUMENTED_BIN" "$src" "$ll" \
      > /dev/null 2>"$stderr"
    status=$?
    set -e
    [[ "$status" == 0 && -s "$ll" ]] || {
      printf '[coverage] failed to compile pinned weavec1 module: %s\n' "$module" >&2
      sed -n '1,120p' "$stderr" >&2 || true
      exit 1
    }
  done

  printf '[coverage] audit Stage 0 keyword surface against pinned weavec1\n' >&2
  python3 "$ROOT/scripts/audit_bootstrap_surface.py" \
    --weavec0 "$ROOT" \
    --weavec1 "$WEAVEC1_DIR" \
    --json "$SURFACE_JSON"
fi

printf '[coverage] aggregate report\n' >&2
python3 "$ROOT/scripts/report_llvm_coverage.py" \
  --map "$MAP_TSV" \
  --raw "$RAW_TSV" \
  --json "$REPORT_JSON" \
  --fail-under-functions "${WEAVEC0_MIN_FUNCTION_COVERAGE:-0}" \
  --fail-under-blocks "${WEAVEC0_MIN_BLOCK_COVERAGE:-0}" \
  --fail-under-branch-outcomes "${WEAVEC0_MIN_BRANCH_OUTCOME_COVERAGE:-0}"
