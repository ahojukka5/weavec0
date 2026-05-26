; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 09_main.ll
;
; Command-line entry point for the hand-written LLVM IR Stage 0 compiler.
;
; Responsibilities:
;   - validate the argv shape (`weavec0 input.wir output.ll`)
;   - print a usage line to stderr on bad arguments
;   - hand off to weave_compile_file (08_driver.ll) for the real work
;   - translate the i32 status code from the driver into a process exit code
;
; Boundary:
;   Stage 0 emits LLVM IR text only. It does not assemble, link, optimize,
;   or run the generated program. Driving llvm-as / llvm-link / clang on the
;   output is the responsibility of the build script (../build.sh).
; =============================================================================

; ----------------------------------------------------------------------------
; main
;
; C ABI:
;   int main(int argc, char **argv)
;
; argv[0] : executable name
; argv[1] : input Weave source path
; argv[2] : output LLVM IR path
;
; Returns:
;   0 on success
;   1 on failure
; ----------------------------------------------------------------------------

define i32 @main(i32 %argc, ptr %argv) {
entry:
  %has_expected_argc = icmp eq i32 %argc, 3
  br i1 %has_expected_argc, label %load_args, label %usage

usage:
  %stderr = call ptr @weave_rt_stderr()
  %usage_msg = call ptr @weave_cstr_usage()
  call i32 (ptr, ptr, ...) @fprintf(ptr %stderr, ptr %usage_msg)
  ret i32 1

load_args:
  %input_slot = getelementptr inbounds ptr, ptr %argv, i64 1
  %output_slot = getelementptr inbounds ptr, ptr %argv, i64 2

  %input_path = load ptr, ptr %input_slot
  %output_path = load ptr, ptr %output_slot

  %input_is_null = icmp eq ptr %input_path, null
  %output_is_null = icmp eq ptr %output_path, null
  %bad_paths = or i1 %input_is_null, %output_is_null

  br i1 %bad_paths, label %usage, label %compile

compile:
  %status = call i32 @weave_compile_file(ptr %input_path, ptr %output_path)
  %ok = icmp eq i32 %status, 0
  br i1 %ok, label %success, label %failure

success:
  ret i32 0

failure:
  ret i32 1
}
