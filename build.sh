#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# weavec0 — Stage 0 bootstrap compiler build and semantic/golden ladder.
#
# The ordinary handwritten modules are linked first. 07_scope_override.ll is
# then linked with llvm-link --override so a small, auditable fix module can
# replace selected emitter entry points without copying the 4,000-line emitter.

REGEN_GOLDENS=0
for arg in "$@"; do
  case "$arg" in
    --regen-goldens) REGEN_GOLDENS=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: ./build.sh [--regen-goldens]

Build weavec0, run every semantic test in test/manifest.txt, and compare every
positive result with its checked-in LLVM golden. --regen-goldens updates stale
or missing positive goldens after correctness succeeds.
USAGE
      exit 0
      ;;
    *) printf 'unknown flag: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT/src"
TEST_DIR="$ROOT/test"
BUILD_DIR="$ROOT/build/bootstrap-tests"
BC_DIR="$BUILD_DIR/bc"
GEN_LL_DIR="$BUILD_DIR/ll"
MANIFEST="$TEST_DIR/manifest.txt"

WEAVEC0="$ROOT/weavec0"
WEAVEC0_BASE_BC="$BUILD_DIR/weavec0-base.bc"
WEAVEC0_BC="$BUILD_DIR/weavec0.bc"
PRELUDE_LL="$BUILD_DIR/module_prelude.ll"
DECLS_LL="$BUILD_DIR/module_declarations.ll"
SCOPE_OVERRIDE="$SRC_DIR/07_scope_override.ll"

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

extract_module_prelude() {
  sed -e '/^; SPDX-License-Identifier:/d' \
      -e '/^; Token kind constants/,$d' \
      "$SRC_DIR/00_prelude.ll" > "$PRELUDE_LL"
}

# Build declarations only from the ordinary modules. The override module has
# duplicate replacement definitions by design; assemble_module filters their
# ordinary declarations when assembling that module.
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

assemble_module() {
  local module="$1"
  local base module_ll module_bc module_names module_decls

  base="$(basename "$module" .ll)"
  module_ll="$GEN_LL_DIR/$base.ll"
  module_bc="$BC_DIR/$base.bc"
  module_names="$BUILD_DIR/$base.names"
  module_decls="$BUILD_DIR/$base.decls.ll"

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

link_compiler() {
  local override_bc="$1"
  shift
  local base_bitcodes=("$@")

  log "link ordinary bitcode"
  llvm-link "${base_bitcodes[@]}" -o "$WEAVEC0_BASE_BC"

  log "apply function-scope override"
  llvm-link "$WEAVEC0_BASE_BC" --override "$override_bc" -o "$WEAVEC0_BC"

  log "link executable"
  clang -Wno-override-module "$WEAVEC0_BC" "$ROOT/runtime.c" -o "$WEAVEC0"
}

build_weavec0() {
  log "building weavec0"
  require_tool llvm-as
  require_tool llvm-link
  require_tool clang

  llvm-link --help 2>&1 | grep -q -- '--override' || \
    fail 'llvm-link does not support --override'
  [[ -f "$SCOPE_OVERRIDE" ]] || fail "missing scope override: $SCOPE_OVERRIDE"

  extract_module_prelude
  extract_module_decls

  local base_bitcodes=()
  local module
  for module in "${MODULES[@]}"; do
    base_bitcodes+=("$(assemble_module "$module")")
  done
  local override_bc
  override_bc="$(assemble_module "$SCOPE_OVERRIDE")"
  link_compiler "$override_bc" "${base_bitcodes[@]}"
}

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
  local status=$?
  set -e

  [[ "$status" != 0 ]] || fail "$name: expected compiler failure, got success"
  [[ ! -s "$ll" ]] || fail "$name: compiler failure produced non-empty LLVM IR"
  if ! grep -q "$expected_message" "$stderr"; then
    printf '\n--- compiler stderr: %s ---\n' "$stderr" >&2
    sed -n '1,120p' "$stderr" >&2 || true
    printf '\n' >&2
    fail "$name: expected diagnostic containing: $expected_message"
  fi
  log "ok correctness $name"
}

run_manifest_correctness() {
  [[ -f "$MANIFEST" ]] || fail "missing test manifest: $MANIFEST"
  local line kind name rest
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    read -r kind name rest <<<"$line"
    case "$kind" in
      pass) run_correctness_case "$name" "$rest" ;;
      fail) run_compile_fail_case "$name" "$rest" ;;
      *) fail "unknown manifest entry kind: $kind (line: $line)" ;;
    esac
  done < "$MANIFEST"
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
    printf '[bootstrap] error: missing expected LLVM IR: %s (rerun with --regen-goldens to create)\n' "$expected_ll" >&2
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
  printf '[bootstrap] error: %s: generated LLVM IR differs from expected fixture (rerun with --regen-goldens to accept)\n' "$name" >&2
  return 1
}

run_manifest_goldens() {
  local line kind name rest failures=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    read -r kind name rest <<<"$line"
    case "$kind" in
      pass) compare_golden_case "$name" || failures=$((failures + 1)) ;;
      fail) ;;
      *) fail "unknown manifest entry kind: $kind (line: $line)" ;;
    esac
  done < "$MANIFEST"
  (( failures == 0 )) || fail "$failures golden fixture(s) differed from generated LLVM IR"
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
