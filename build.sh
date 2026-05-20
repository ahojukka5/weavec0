#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Weave Stage 0 Bootstrap Test Ladder
# weave/src-bootstrap-llvm/build.sh
#
# This script builds the hand-written LLVM IR Stage 0 compiler and runs the
# curated bootstrap tests.
#
# The test ladder proves only one thing:
#
#     weavec0 can compile tiny Weave programs into LLVM IR,
#     and the generated LLVM IR matches the checked-in golden fixtures.
#
# It does not prove that the production compiler is ready.
# It does not prove self-hosting yet.
# =============================================================================

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$BOOTSTRAP_DIR/tests"
BUILD_DIR="$BOOTSTRAP_DIR/build/bootstrap-tests"
BC_DIR="$BUILD_DIR/bc"
GEN_LL_DIR="$BUILD_DIR/ll"

WEAVEC0="$BOOTSTRAP_DIR/weavec0"
WEAVEC0_BC="$BUILD_DIR/weavec0.bc"
PRELUDE_LL="$BUILD_DIR/module_prelude.ll"
DECLS_LL="$BUILD_DIR/module_declarations.ll"

MODULES=(
  "$BOOTSTRAP_DIR/ll/01_runtime_bindings.ll"
  "$BOOTSTRAP_DIR/ll/02_strings.ll"
  "$BOOTSTRAP_DIR/ll/03_tokens.ll"
  "$BOOTSTRAP_DIR/ll/04_lexer.ll"
  "$BOOTSTRAP_DIR/ll/05_ast.ll"
  "$BOOTSTRAP_DIR/ll/06_parser.ll"
  "$BOOTSTRAP_DIR/ll/07_emit_llvm.ll"
  "$BOOTSTRAP_DIR/ll/08_driver.ll"
  "$BOOTSTRAP_DIR/ll/09_main.ll"
)

mkdir -p "$BUILD_DIR" "$BC_DIR" "$GEN_LL_DIR"

log() {
  printf '[bootstrap] %s\n' "$*"
}

fail() {
  printf '[bootstrap] error: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

build_weavec0() {
  log "building weavec0"

  require_tool llvm-as
  require_tool llvm-link
  require_tool clang

  sed '/^; Token kind constants/,$d' "$BOOTSTRAP_DIR/ll/00_prelude.ll" > "$PRELUDE_LL"

  awk '
    function emit_signature() {
      gsub(/\n/, " ", signature)
      sub(/[[:space:]]*\{[[:space:]]*$/, "", signature)
      sub(/^define /, "declare ", signature)
      print signature
      signature = ""
      in_define = 0
    }

    /^declare / {
      print
      next
    }

    /^define / {
      signature = $0
      if ($0 ~ /\{[[:space:]]*$/) {
        emit_signature()
      } else {
        in_define = 1
      }
      next
    }

    in_define {
      signature = signature "\n" $0
      if ($0 ~ /\{[[:space:]]*$/) {
        emit_signature()
      }
    }
  ' "${MODULES[@]}" > "$DECLS_LL"

  local bitcodes=()
  for module in "${MODULES[@]}"; do
    local base
    local module_ll
    local module_bc
    local module_names
    local module_decls

    base="$(basename "$module" .ll)"
    module_ll="$GEN_LL_DIR/$base.ll"
    module_bc="$BC_DIR/$base.bc"
    module_names="$BUILD_DIR/$base.names"
    module_decls="$BUILD_DIR/$base.decls.ll"

    awk '/^(define|declare) / {
      if (match($0, /@[A-Za-z0-9_.$-]+/)) {
        print substr($0, RSTART, RLENGTH)
      }
    }' "$module" > "$module_names"

    awk 'NR == FNR {
      skip[$1] = 1
      next
    }
    {
      if (match($0, /@[A-Za-z0-9_.$-]+/)) {
        name = substr($0, RSTART, RLENGTH)
        if (name in skip) {
          next
        }
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
    bitcodes+=("$module_bc")
  done

  log "link bitcode"
  llvm-link "${bitcodes[@]}" -o "$WEAVEC0_BC"

  log "link executable"
  clang "$WEAVEC0_BC" "$BOOTSTRAP_DIR/runtime.c" -o "$WEAVEC0"
}

run_case() {
  local name="$1"

  local src="$TEST_DIR/${name}.wir"
  local expected_ll="$TEST_DIR/${name}.expected.ll"
  local ll="$BUILD_DIR/${name}.ll"

  [[ -f "$src" ]] || fail "missing test source: $src"
  [[ -f "$expected_ll" ]] || fail "missing expected LLVM IR: $expected_ll"

  log "compile $name"
  "$WEAVEC0" "$src" "$ll"

  [[ -s "$ll" ]] || fail "compiler produced empty LLVM IR for $name"

  log "compare $name"
  if ! diff -u "$expected_ll" "$ll"; then
    fail "$name: generated LLVM IR differs from expected fixture"
  fi

  log "ok $name"
}

main() {
  build_weavec0

  # Keep this ladder small. Add a new test only when the matching bootstrap
  # feature has been deliberately admitted.
  run_case "01_return_constant"
  run_case "02_return_42"
  run_case "03_add"
  run_case "04_one_arg_function"
  run_case "05_let_local"
  run_case "06_set_local"
  run_case "07_if"
  run_case "08_while"
  run_case "09_two_arg_function"
  run_case "10_string_literal"
  run_case "11_const_i64"
  run_case "12_i64_arithmetic"
  run_case "13_i64_comparisons"
  run_case "14_bool_ops"
  run_case "15_ptr_null"
  run_case "16_extern_malloc_free"
  run_case "17_ptr_add_store_load_i64"
  run_case "18_store_load_i8"
  run_case "19_call_void"
  run_case "20_call_i64"
  run_case "21_call_ptr"
  run_case "22_return_void"
  run_case "23_mod_i32"
  run_case "24_buffer_like_smoke"
  run_case "25_ptr_params_call_i32"
  run_case "26_bool_return"
  run_case "27_three_arg_function"
  run_case "28_i32_memory_and_cast"
  run_case "29_const_string_ptr"
  run_case "30_i64_sub_eq"
  run_case "31_not_bool"
  run_case "32_codegen_join_and_i64_arg"
  run_case "33_store_i8_temp"
  run_case "34_ge_i32"

  log "all bootstrap tests passed"
}

main "$@"
