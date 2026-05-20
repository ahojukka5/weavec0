#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Weave Stage 0 Bootstrap Test Ladder
# weave/src-bootstrap-llvm/build.sh
#
# This script builds the hand-written LLVM IR Stage 0 compiler and runs the
# curated bootstrap tests.
#
# The test ladder proves:
#
#     - weavec0 can compile tiny Weave programs into LLVM IR
#     - generated LLVM IR matches the checked-in golden fixtures
#     - llvm-as accepts the generated LLVM IR
#     - clang can build that IR
#     - the resulting executable behaves as expected
#     - selected invalid WIR inputs fail cleanly
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
  local expected_exit="$2"

  local src="$TEST_DIR/${name}.wir"
  local expected_ll="$TEST_DIR/${name}.expected.ll"
  local ll="$BUILD_DIR/${name}.ll"
  local generated_bc="$BUILD_DIR/${name}.generated.bc"
  local exe="$BUILD_DIR/${name}.out"

  [[ -f "$src" ]] || fail "missing test source: $src"

  log "compile $name"
  "$WEAVEC0" "$src" "$ll"

  log "llvm-as $name"
  llvm-as "$ll" -o "$generated_bc"

  log "clang $name"
  clang "$ll" -o "$exe"

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

  [[ -s "$ll" ]] || fail "compiler produced empty LLVM IR for $name"

  log "compare $name"
  [[ -f "$expected_ll" ]] || fail "missing expected LLVM IR: $expected_ll"
  if ! diff -u "$expected_ll" "$ll"; then
    fail "$name: generated LLVM IR differs from expected fixture"
  fi

  log "ok $name"
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

  log "ok $name"
}

main() {
  build_weavec0

  # Keep this ladder small. Add a new test only when the matching bootstrap
  # feature has been deliberately admitted.
  run_case "01_return_constant" 0
  run_case "02_return_42" 42
  run_case "03_add" 42
  run_case "04_one_arg_function" 42
  run_case "05_let_local" 42
  run_case "06_set_local" 42
  run_case "07_if" 42
  run_case "08_while" 42
  run_case "09_two_arg_function" 42
  run_case "10_string_literal" 42
  run_case "11_const_i64" 42
  run_case "12_i64_arithmetic" 42
  run_case "13_i64_comparisons" 42
  run_case "14_bool_ops" 42
  run_case "15_ptr_null" 42
  run_case "16_extern_malloc_free" 42
  run_case "17_ptr_add_store_load_i64" 42
  run_case "18_store_load_i8" 42
  run_case "19_call_void" 42
  run_case "20_call_i64" 42
  run_case "21_call_ptr" 42
  run_case "22_return_void" 42
  run_case "23_mod_i32" 2
  run_case "24_buffer_like_smoke" 42
  run_case "25_ptr_params_call_i32" 42
  run_case "26_bool_return" 42
  run_case "27_three_arg_function" 42
  run_case "28_i32_memory_and_cast" 42
  run_case "29_const_string_ptr" 42
  run_case "30_i64_sub_eq" 42
  run_case "31_not_bool" 42
  run_case "32_codegen_join_and_i64_arg" 42
  run_case "33_store_i8_temp" 42
  run_case "34_ge_i32" 42
  run_case "35_sub_i32" 42
  run_case "36_mul_i32" 42
  run_case "37_div_i32" 42
  run_case "38_i32_comparisons_full" 42
  run_case "39_i64_ge_gt" 42
  run_case "40_call_bool_direct" 42
  run_case "41_load_store_ptr" 42
  run_case "42_empty_do" 42
  run_case "43_if_fallthrough_join" 42
  run_case "44_while_zero_iterations" 42
  run_case "45_nested_while" 42
  run_case "46_forward_function_call" 42
  run_case "47_multiple_externs_used_subset" 42
  run_case "48_string_escape" 42
  run_case "49_negative_i32_literal" 42
  run_compile_fail_case "50_parse_error_smoke" "parsing failed"
  run_compile_fail_case "51_unknown_operator" "unknown operator"
  run_compile_fail_case "52_wrong_arity_add_i32_too_few" "arity"
  run_compile_fail_case "53_wrong_arity_add_i32_too_many" "arity"

  log "all bootstrap tests passed"
}

main "$@"
