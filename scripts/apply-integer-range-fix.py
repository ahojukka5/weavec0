#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
from __future__ import annotations

import os
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement target, found {count}")
    target.write_text(text.replace(old, new, 1))


old_integer = r'''; ----------------------------------------------------------------------------
; Integer scanning
; ----------------------------------------------------------------------------
;
; Scan a non-negative decimal integer starting at `start`.
;
; On success, appends TOKEN_INT and returns the index just after the literal.
; On failure, returns -1.


define i64 @weave_lex_integer(ptr %source, ptr %tokens, i64 %start) {
entry:
  %length = call i64 @weave_source_length(ptr %source)
  %first_ch = call i32 @weave_source_byte_at(ptr %source, i64 %start)
  %is_minus = icmp eq i32 %first_ch, 45
  %signed_start = add i64 %start, 1
  %scan_start = select i1 %is_minus, i64 %signed_start, i64 %start
  br label %loop

loop:
  %index = phi i64 [%scan_start, %entry], [%next, %advance]
  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %finish, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)
  %is_digit = call i32 @weave_is_digit(i32 %ch)
  %yes = icmp ne i32 %is_digit, 0
  br i1 %yes, label %advance, label %finish

advance:
  %next = add i64 %index, 1
  br label %loop

finish:
  %token_length = sub i64 %index, %start
  %empty = icmp eq i64 %token_length, 0
  br i1 %empty, label %fail, label %parse_value

parse_value:
  %data = call ptr @weave_source_data(ptr %source)
  %text = getelementptr inbounds i8, ptr %data, i64 %start
  ; atoll, not atoi: const_i64 values (up to INT64_MAX) must survive.
  %value = call i64 @atoll(ptr %text)
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 4, i64 %start, i64 %token_length, i64 %value)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %success

success:
  ret i64 %index

fail:
  ret i64 -1
}
'''

new_integer = r'''; ----------------------------------------------------------------------------
; Integer scanning
; ----------------------------------------------------------------------------
;
; Scan one signed decimal integer starting at `start`.
;
; The magnitude is accumulated with explicit bounds. Positive values admit at
; most INT64_MAX; negative values admit the one larger INT64_MIN magnitude.
; When the preceding token is const_i32, the final signed value must also fit
; exactly in i32. This keeps every integer token authoritative and avoids libc
; conversion, saturation, truncation, and dependence on a trailing NUL byte.
;
; On success, appends TOKEN_INT and returns the index just after the literal.
; On failure, returns -1.


define i64 @weave_lex_integer(ptr %source, ptr %tokens, i64 %start) {
entry:
  %length = call i64 @weave_source_length(ptr %source)
  %first_ch = call i32 @weave_source_byte_at(ptr %source, i64 %start)
  %is_minus = icmp eq i32 %first_ch, 45
  %signed_start = add i64 %start, 1
  %scan_start = select i1 %is_minus, i64 %signed_start, i64 %start
  %token_count = call i64 @weave_tokens_count(ptr %tokens)
  %has_previous = icmp ugt i64 %token_count, 0
  br i1 %has_previous, label %read_previous, label %init

read_previous:
  %previous_index = sub i64 %token_count, 1
  %previous_kind = call i32 @weave_token_kind(ptr %tokens, i64 %previous_index)
  %previous_is_const_i32 = icmp eq i32 %previous_kind, 31
  br label %init

init:
  %requires_i32 = phi i1 [false, %entry], [%previous_is_const_i32, %read_previous]
  %last_digit_limit = select i1 %is_minus, i64 8, i64 7
  br label %loop

loop:
  %index = phi i64 [%scan_start, %init], [%next, %accumulate]
  %magnitude = phi i64 [0, %init], [%next_magnitude, %accumulate]
  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %finish, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)
  %is_digit_status = call i32 @weave_is_digit(i32 %ch)
  %is_digit = icmp ne i32 %is_digit_status, 0
  br i1 %is_digit, label %check_overflow, label %finish

check_overflow:
  %digit_i32 = sub i32 %ch, 48
  %digit = zext i32 %digit_i32 to i64
  %prefix_too_large = icmp ugt i64 %magnitude, 922337203685477580
  %prefix_at_limit = icmp eq i64 %magnitude, 922337203685477580
  %last_digit_too_large = icmp ugt i64 %digit, %last_digit_limit
  %overflow_at_limit = and i1 %prefix_at_limit, %last_digit_too_large
  %overflow = or i1 %prefix_too_large, %overflow_at_limit
  br i1 %overflow, label %fail, label %accumulate

accumulate:
  %scaled = mul i64 %magnitude, 10
  %next_magnitude = add i64 %scaled, %digit
  %next = add i64 %index, 1
  br label %loop

finish:
  %digit_count = sub i64 %index, %scan_start
  %empty = icmp eq i64 %digit_count, 0
  br i1 %empty, label %fail, label %apply_sign

apply_sign:
  ; Plain LLVM integer arithmetic wraps modulo 2^64 without nsw/nuw flags, so
  ; subtracting the admitted 2^63 magnitude yields the exact INT64_MIN bits.
  %negative_value = sub i64 0, %magnitude
  %value = select i1 %is_minus, i64 %negative_value, i64 %magnitude
  br i1 %requires_i32, label %check_i32_range, label %push

check_i32_range:
  %below_i32 = icmp slt i64 %value, -2147483648
  %above_i32 = icmp sgt i64 %value, 2147483647
  %outside_i32 = or i1 %below_i32, %above_i32
  br i1 %outside_i32, label %fail, label %push

push:
  %token_length = sub i64 %index, %start
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 4, i64 %start, i64 %token_length, i64 %value)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %success

success:
  ret i64 %index

fail:
  ret i64 -1
}
'''

replace_once("src/04_lexer.ll", old_integer, new_integer)

replace_once(
    "src/01_runtime_bindings.ll",
    '''; Wider conversion. Used by the lexer for const_i64 literal values so the i64
; surface (constants up to INT64_MAX) survives without silent truncation.
declare i64 @atoll(ptr %s)

''',
    "",
)

replace_once(
    "test/manifest.txt",
    "fail 104_unsupported_core_version       parsing failed\n",
    "fail 104_unsupported_core_version       parsing failed\n"
    "pass 105_const_i32_max                  255\n",
)

(ROOT / "test/105_const_i32_max.wir").write_text(
    '''; 105_const_i32_max.wir
; purpose: covers the highest exactly representable i32 literal.
; verifies bounded integer parsing accepts INT32_MAX without truncation.
; expected runtime behavior: process exits with code 255 (the low exit byte).

(core-module
  (core-version 1)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return
          (const_i32 2147483647)
        ) ;; return
      ) ;; do
    ) ;; fn
  ) ;; decls
) ;; core-module
'''
)

(ROOT / "test/105_const_i32_max.expected.ll").write_text(
    '''; generated by weavec0, the Weave Stage 0 compiler

define i32 @main() {
entry:
  ret i32 2147483647
}
'''
)

negative_script = ROOT / "scripts/run-integer-range-negative-matrix.sh"
negative_script.write_text(
    r'''#!/usr/bin/env bash
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
'''
)
os.chmod(negative_script, 0o755)

replace_once(
    "scripts/run-tests.sh",
    '''bash "$ROOT/scripts/run-extern-signature-negative-matrix.sh" \\
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/extern-signature-negative-matrix"

''',
    '''bash "$ROOT/scripts/run-extern-signature-negative-matrix.sh" \\
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/extern-signature-negative-matrix"
bash "$ROOT/scripts/run-integer-range-negative-matrix.sh" \\
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/integer-range-negative-matrix"

''',
)

replace_once(
    "scripts/extend-coverage-with-cli.sh",
    '''printf '[coverage] regenerate aggregate report\\n' >&2
''',
    '''printf '[coverage] extend workload with integer-range matrix\\n' >&2
WEAVEC0_COVERAGE_OUT="$RAW_TSV" \\
  bash "$ROOT/scripts/run-integer-range-negative-matrix.sh" \\
    "$INSTRUMENTED_BIN" "$BUILD_DIR/integer-range-negative-matrix"

printf '[coverage] regenerate aggregate report\\n' >&2
''',
)

release_notes = '''## [0.3.2] — 2026-07-25

### Added

- An exact `INT32_MAX` regression and a generated six-case integer-range
  negative matrix covering both adjacent boundary failures and arbitrarily
  large positive and negative decimal sequences.
- Integer-range failures are included in both the normal test ladder and the
  instrumented LLVM coverage workload.

### Changed

- Decimal integer tokens are parsed by a bounded manual accumulator over the
  explicit source slice. Stage 0 no longer depends on libc `atoll`, a trailing
  NUL byte, implementation-defined saturation, or later narrowing truncation.

### Fixed

- `const_i32` now rejects values outside `[-2147483648, 2147483647]`.
- All integer tokens now reject values outside
  `[-9223372036854775808, 9223372036854775807]` while preserving both exact
  signed minima.

'''
replace_once(
    "CHANGELOG.md",
    "## [Unreleased]\n\n## [0.3.1] — 2026-07-25\n",
    "## [Unreleased]\n\n" + release_notes + "## [0.3.1] — 2026-07-25\n",
)

(ROOT / "VERSION").write_text("0.3.2\n")

subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", str(negative_script)], cwd=ROOT, check=True)
subprocess.run(["bash", "scripts/run-tests.sh"], cwd=ROOT, check=True)

# The bootstrap workflow and this one-shot patch script must not remain in the
# repository. Squash-merging the resulting PR leaves one normal source commit.
(ROOT / ".github/workflows/apply-integer-range-fix.yml").unlink()
pathlib.Path(__file__).unlink()

subprocess.run(["git", "add", "-A"], cwd=ROOT, check=True)
subprocess.run(
    ["git", "-c", "user.name=github-actions[bot]", "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com", "commit", "-m", "fix: reject out-of-range integer literals"],
    cwd=ROOT,
    check=True,
)
subprocess.run(["git", "push", "origin", "HEAD:agent/reject-out-of-range-integers"], cwd=ROOT, check=True)
