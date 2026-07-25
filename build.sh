#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavec0 — Stage 0 bootstrap compiler build & test ladder
# =============================================================================
#
# This script runs three phases, in order:
#
#   1. Assemble the hand-written LLVM-IR Stage 0 compiler (`weavec0`) from
#      the source modules under `src/` plus the small C runtime in `runtime.c`.
#   2. Run the complete correctness ladder under `test/`, driven by
#      `test/manifest.txt`.
#   3. After every correctness case has passed, compare all generated LLVM IR
#      files with their checked-in golden fixtures.
#
# Each positive test case (manifest line: `pass <name> <exit>`) verifies:
#
#   - weavec0 compiles `test/<name>.wir` to LLVM IR
#   - `llvm-as` accepts the generated LLVM
#   - `clang` builds an executable from it
#   - the executable exits with the declared code
#   - in the final phase, the generated LLVM matches
#     `test/<name>.expected.ll` exactly
#
# Each negative case (`fail <name> <substring>`) verifies:
#
#   - weavec0 exits non-zero
#   - no .ll is produced
#   - stderr contains the declared diagnostic substring
#
# Flags:
#
#   --regen-goldens
#       On any golden mismatch, overwrite the expected .ll with the just-
#       generated output instead of erroring. Useful after intentional
#       output-format changes; review the resulting `git diff` before
#       committing.
#
# This script is intentionally bash, not CMake, to keep the bootstrap build
# explicit and consistent with the other lower compiler stages.
# =============================================================================

REGEN_GOLDENS=0
for arg in "$@"; do
  case "$arg" in
    --regen-goldens) REGEN_GOLDENS=1 ;;
    -h|--help)
      sed -n '4,40p' "$0"
      exit 0
      ;;
    *) printf 'unknown flag: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$BOOTSTRAP_DIR/src"
TEST_DIR="$BOOTSTRAP_DIR/test"
BUILD_DIR="$BOOTSTRAP_DIR/build/bootstrap-tests"
BC_DIR="$BUILD_DIR/bc"
GEN_LL_DIR="$BUILD_DIR/ll"
MANIFEST="$TEST_DIR/manifest.txt"

WEAVEC0="$BOOTSTRAP_DIR/weavec0"
WEAVEC0_BC="$BUILD_DIR/weavec0.bc"
PRELUDE_LL="$BUILD_DIR/module_prelude.ll"
DECLS_LL="$BUILD_DIR/module_declarations.ll"

# Source modules in dependency order. Numeric prefixes are load-bearing:
# they pin the assemble/link order and give readers a stable mental map of
# the pipeline (prelude → runtime → strings → tokens → lexer → ast → parser
# → emit → driver → main).
MODULES=(
  "$SRC_DIR/01_runtime_bindings.ll"
  "$SRC_DIR/02_strings.ll"
  "$SRC_DIR/03_tokens.ll"
  "$SRC_DIR/04_lexer.ll"
  "$SRC_DIR/05_ast.ll"
  "$SRC_DIR/06_parser.ll"
  "$SRC_DIR/07_emit_llvm.ll"
  "$SRC_DIR/08_driver.ll"
  "$SRC_DIR/09_main.ll"
)

mkdir -p "$BUILD_DIR" "$BC_DIR" "$GEN_LL_DIR"

log()  { printf '[bootstrap] %s\n' "$*" >&2; }
fail() { printf '[bootstrap] error: %s\n' "$*" >&2; exit 1; }
require_tool() { command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"; }

# -----------------------------------------------------------------------------
# Building weavec0 itself
# -----------------------------------------------------------------------------

# Extract the module-wide prelude (target triple, type definitions, ABI notes)
# from 00_prelude.ll. The constants below the "Token kind constants" banner are
# documentation only and must NOT be prepended to every module, so we cut
# everything from that banner onward. The leading SPDX line is also dropped:
# each module file carries its own SPDX header as its first line, so emitting
# the prelude verbatim would duplicate it in every assembled module.
extract_module_prelude() {
  sed -e '/^; SPDX-License-Identifier:/d' \
      -e '/^; Token kind constants/,$d' \
      "$SRC_DIR/00_prelude.ll" > "$PRELUDE_LL"
}

# Build a single "all declarations" file by extracting every `define` signature
# from every module and rewriting it as a `declare`.
#
# Why this exists: each module compiles independently with `llvm-as`. A module
# that calls a function defined in another module needs a `declare` for it, or
# llvm-as rejects the file. Rather than maintain per-module declare blocks by
# hand, we synthesize them here from the actual `define` signatures, then
# filter out a module's own definitions before prepending the rest as decls.
extract_module_decls() {
  awk '
    function emit_signature() {
      gsub(/\n/, " ", signature)
      sub(/[[:space:]]*\{[[:space:]]*$/, "", signature)
      sub(/^define /, "declare ", signature)
      print signature
      signature = ""
      in_define = 0
    }
    /^declare / { print; next }
    /^define / {
      signature = $0
      if ($0 ~ /\{[[:space:]]*$/) { emit_signature() } else { in_define = 1 }
      next
    }
    in_define {
      signature = signature "\n" $0
      if ($0 ~ /\{[[:space:]]*$/) { emit_signature() }
    }
  ' "${MODULES[@]}" > "$DECLS_LL"
}

# Assemble one module: write a self-contained .ll combining the prelude, the
# externals-from-other-modules block, and the module's own source, then
# `llvm-as` it to bitcode. Returns the bitcode path on stdout.
assemble_module() {
  local module="$1"
  local base module_ll module_bc module_names module_decls

  base="$(basename "$module" .ll)"
  module_ll="$GEN_LL_DIR/$base.ll"
  module_bc="$BC_DIR/$base.bc"
  module_names="$BUILD_DIR/$base.names"
  module_decls="$BUILD_DIR/$base.decls.ll"

  # Names defined in THIS module — they must be skipped when prepending decls
  # from elsewhere (otherwise llvm-as complains about duplicate definitions).
  awk '/^(define|declare) / {
    if (match($0, /@[A-Za-z0-9_.$-]+/)) { print substr($0, RSTART, RLENGTH) }
  }' "$module" > "$module_names"

  awk 'NR == FNR { skip[$1] = 1; next }
    {
      if (match($0, /@[A-Za-z0-9_.$-]+/)) {
        name = substr($0, RSTART, RLENGTH)
        if (name in skip) next
      }
      print
    }' "$module_names" "$DECLS_LL" > "$module_decls"

  {
    cat "$PRELUDE_LL"
    printf '\n; ---- external declarations ----\n\n'
    cat "$module_decls"
    printf '\n; ---- %s ----\n\n' "$base"
    sed '/^source_filename = /d; /^target triple = /d; /^target datalayout = /d' "$module"
  } > "$module_ll"

  log "assemble $base"
  llvm-as "$module_ll" -o "$module_bc"
  printf '%s\n' "$module_bc"
}

# Link all module bitcodes into a single .bc, then clang it with the C runtime
# to produce the weavec0 executable.
link_compiler() {
  local bitcodes=("$@")
  log "link bitcode"
  llvm-link "${bitcodes[@]}" -o "$WEAVEC0_BC"
  log "link executable"
  clang -Wno-override-module "$WEAVEC0_BC" "$BOOTSTRAP_DIR/runtime.c" -o "$WEAVEC0"
}

build_weavec0() {
  log "building weavec0"
  require_tool llvm-as
  require_tool llvm-link
  require_tool clang

  extract_module_prelude
  extract_module_decls

  local bitcodes=()
  for module in "${MODULES[@]}"; do
    bitcodes+=("$(assemble_module "$module")")
  done
  link_compiler "${bitcodes[@]}"
}

# -----------------------------------------------------------------------------
# Test runners
# -----------------------------------------------------------------------------

run_correctness_case() {
  local name="$1"
  local expected_exit="$2"

  local src="$TEST_DIR/${name}.wir"
  local ll="$BUILD_DIR/${name}.ll"
  local generated_bc="$BUILD_DIR/${name}.generated.bc"
  local exe="$BUILD_DIR/${name}.out"

  [[ -f "$src" ]] || fail "missing test source: $src"

  log "compile $name"
  "$WEAVEC0" "$src" "$ll"

  [[ -s "$ll" ]] || fail "compiler produced empty LLVM IR for $name"

  log "llvm-as $name"
  llvm-as "$ll" -o "$generated_bc"

  log "clang $name"
  clang -Wno-override-module "$ll" -o "$exe"

  log "run $name"
  set +e
  "$exe"
  local actual_exit=$?
  set -e

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    printf '\n--- generated LLVM IR: %s ---\n' "$ll" >&2
    sed -n '1,200p' "$ll" >&2 || true
    printf '\n' >&2
    fail "$name: expected exit $expected_exit, got $actual_exit"
  fi

  log "ok correctness $name"
}

compare_golden_case() {
  local name="$1"

  local expected_ll="$TEST_DIR/${name}.expected.ll"
  local ll="$BUILD_DIR/${name}.ll"

  [[ -s "$ll" ]] || {
    printf '[bootstrap] error: missing generated LLVM IR for golden comparison: %s\n' "$ll" >&2
    return 1
  }

  log "compare $name"
  if [[ ! -f "$expected_ll" ]]; then
    if (( REGEN_GOLDENS )); then
      cp "$ll" "$expected_ll"
      log "regen $name (new golden)"
      return 0
    fi

    printf '[bootstrap] error: missing expected LLVM IR: %s (rerun with --regen-goldens to create)\n' \
      "$expected_ll" >&2
    return 1
  fi

  if diff -u "$expected_ll" "$ll" >/dev/null; then
    log "ok golden $name"
    return 0
  fi

  if (( REGEN_GOLDENS )); then
    cp "$ll" "$expected_ll"
    log "regen $name (updated golden)"
    return 0
  fi

  diff -u "$expected_ll" "$ll" || true
  printf '[bootstrap] error: %s: generated LLVM IR differs from expected fixture (rerun with --regen-goldens to accept)\n' \
    "$name" >&2
  return 1
}

run_compile_fail_case() {
  local name="$1"
  local expected_message="$2"

  local src="$TEST_DIR/${name}.wir"
  local ll="$BUILD_DIR/${name}.ll"
  local stderr="$BUILD_DIR/${name}.stderr"

  [[ -f "$src" ]] || fail "missing test source: $src"

  log "compile-fail $name"
  rm -f "$ll" "$stderr"
  set +e
  "$WEAVEC0" "$src" "$ll" 2>"$stderr"
  local compile_status=$?
  set -e

  if [[ "$compile_status" == 0 ]]; then
    printf '\n--- unexpected generated LLVM IR: %s ---\n' "$ll" >&2
    sed -n '1,120p' "$ll" >&2 || true
    printf '\n' >&2
    fail "$name: expected compiler failure, got success"
  fi

  if [[ -s "$ll" ]]; then
    printf '\n--- unexpected generated LLVM IR: %s ---\n' "$ll" >&2
    sed -n '1,120p' "$ll" >&2 || true
    printf '\n' >&2
    fail "$name: compiler failure still produced non-empty LLVM IR"
  fi

  if ! grep -q "$expected_message" "$stderr"; then
    printf '\n--- compiler stderr: %s ---\n' "$stderr" >&2
    sed -n '1,120p' "$stderr" >&2 || true
    printf '\n' >&2
    fail "$name: expected diagnostic containing: $expected_message"
  fi

  log "ok correctness $name"
}

# First pass: run every semantic correctness check. Golden-output drift must not
# prevent later correctness cases from running.
run_manifest_correctness() {
  [[ -f "$MANIFEST" ]] || fail "missing test manifest: $MANIFEST"

  local kind name rest
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue

    read -r kind name rest <<<"$line"
    case "$kind" in
      pass) run_correctness_case "$name" "$rest" ;;
      fail) run_compile_fail_case "$name" "$rest" ;;
      *)    fail "unknown manifest entry kind: $kind (line: $line)" ;;
    esac
  done < "$MANIFEST"
}

# Second pass: compare every positive case after the complete correctness phase.
# Report all stale or missing goldens in one run instead of stopping at the first.
run_manifest_goldens() {
  [[ -f "$MANIFEST" ]] || fail "missing test manifest: $MANIFEST"

  local kind name rest
  local failures=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue

    read -r kind name rest <<<"$line"
    case "$kind" in
      pass)
        if ! compare_golden_case "$name"; then
          failures=$((failures + 1))
        fi
        ;;
      fail) ;;
      *)    fail "unknown manifest entry kind: $kind (line: $line)" ;;
    esac
  done < "$MANIFEST"

  if (( failures != 0 )); then
    fail "$failures golden fixture(s) differed from generated LLVM IR"
  fi
}

main() {
  build_weavec0

  log "correctness phase"
  run_manifest_correctness

  log "golden comparison phase"
  run_manifest_goldens

  log "all bootstrap tests passed"
}

main "$@"
