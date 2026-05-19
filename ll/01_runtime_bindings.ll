; =============================================================================
; Weave Stage 0 Bootstrap Compiler
; 01_runtime_bindings.ll
;
; External declarations for the tiny C runtime and the small subset of libc used
; by the hand-written Stage 0 compiler.
;
; This file contains declarations only. Compiler logic belongs in later files.
; =============================================================================

; ----------------------------------------------------------------------------
; C ABI conventions
; ----------------------------------------------------------------------------
;
; Stage 0 targets a 64-bit environment.
;
; Use i64 for C ABI sizes and byte counts.
; Use ptr directly for pointers.
; Compare pointers against null directly.
;
; Correct:
;
;   %is_null = icmp eq ptr %p, null
;
; Incorrect:
;
;   %tmp = ptrtoint ptr %p to i32
;   %is_null = icmp eq i32 %tmp, 0
;
; The second form truncates pointers on 64-bit systems and must not be used.

; ----------------------------------------------------------------------------
; Memory
; ----------------------------------------------------------------------------

; Allocate `size` bytes.
declare ptr @malloc(i64 %size)

; Resize an allocation.
declare ptr @realloc(ptr %old, i64 %size)

; Free an allocation.
declare void @free(ptr %p)

; Copy `n` bytes from `src` to `dst`.
declare ptr @memcpy(ptr %dst, ptr %src, i64 %n)

; Set `n` bytes of `dst` to byte value `value`.
declare ptr @memset(ptr %dst, i32 %value, i64 %n)

; ----------------------------------------------------------------------------
; String and byte operations
; ----------------------------------------------------------------------------

; Return the length of a null-terminated byte string.
declare i64 @strlen(ptr %s)

; Compare two null-terminated byte strings.
declare i32 @strcmp(ptr %a, ptr %b)

; Compare the first `n` bytes of two byte strings.
declare i32 @strncmp(ptr %a, ptr %b, i64 %n)

; Find the first occurrence of byte `ch` in `s`.
declare ptr @strchr(ptr %s, i32 %ch)

; Convert a decimal byte string to an integer.
; Used only for bootstrap input parsing where the syntax is intentionally tiny.
declare i32 @atoi(ptr %s)

; ----------------------------------------------------------------------------
; File IO
; ----------------------------------------------------------------------------

; Open a file.
declare ptr @fopen(ptr %path, ptr %mode)

; Close a file.
declare i32 @fclose(ptr %file)

; Read from a file.
declare i64 @fread(ptr %dst, i64 %size, i64 %count, ptr %file)

; Write to a file.
declare i64 @fwrite(ptr %src, i64 %size, i64 %count, ptr %file)

; Seek inside a file.
declare i32 @fseek(ptr %file, i64 %offset, i32 %origin)

; Return current file position.
declare i64 @ftell(ptr %file)

; Rewind a file to the beginning.
declare void @rewind(ptr %file)

; Flush a file stream.
declare i32 @fflush(ptr %file)

; Standard output and error are provided by the tiny runtime rather than by
; relying on platform-specific global `stdout` / `stderr` declarations here.

; ----------------------------------------------------------------------------
; Minimal formatted and byte output
; ----------------------------------------------------------------------------

; printf is used sparingly for blunt bootstrap diagnostics.
; Most generated LLVM text should be written through explicit buffer helpers.
declare i32 @printf(ptr %format, ...)

declare i32 @fprintf(ptr %stream, ptr %format, ...)

declare i32 @putchar(i32 %ch)

; ----------------------------------------------------------------------------
; Process
; ----------------------------------------------------------------------------

; Terminate the process immediately.
; Prefer returning failure codes inside compiler logic when possible.
declare void @exit(i32 %status) noreturn

; ----------------------------------------------------------------------------
; Tiny runtime supplied by bootstrap/runtime.c
; ----------------------------------------------------------------------------
;
; The runtime is deliberately small. It handles boring platform tasks so the
; hand-written LLVM IR can stay readable.
;
; Runtime functions must not understand Weave syntax.
; If a function knows about tokens, AST nodes, or parsing, it belongs in LLVM IR,
; not in runtime.c.

; Print a fatal error message and exit with status 1.
declare void @weave_rt_fatal(ptr %message) noreturn

; Read the whole file at `path` into a null-terminated byte buffer.
;
; Returns null on failure.
; On success:
;   - returns pointer to allocated bytes
;   - stores byte length, excluding null terminator, into `out_len`
;   - caller owns the returned buffer and must free it

declare ptr @weave_rt_read_file(ptr %path, ptr %out_len)

; Write exactly `length` bytes from `data` into file `path`.
;
; Returns:
;   0 on success
;   1 on failure

declare i32 @weave_rt_write_file(ptr %path, ptr %data, i64 %length)

; Return stderr as an opaque FILE* pointer.
declare ptr @weave_rt_stderr()

; Return stdout as an opaque FILE* pointer.
declare ptr @weave_rt_stdout()

; ----------------------------------------------------------------------------
; Constant strings used by the driver and main
; ----------------------------------------------------------------------------
;
; These are low-level runtime strings, not Weave source string literals.

@weave.str.read_mode = private unnamed_addr constant [3 x i8] c"rb\00"
@weave.str.write_mode = private unnamed_addr constant [3 x i8] c"wb\00"

@weave.str.usage = private unnamed_addr constant [38 x i8] c"usage: weavec0 input.weave output.ll\0A\00"

@weave.str.err_read = private unnamed_addr constant [28 x i8] c"error: could not read file\0A\00"
@weave.str.err_write = private unnamed_addr constant [29 x i8] c"error: could not write file\0A\00"
@weave.str.err_lex = private unnamed_addr constant [22 x i8] c"error: lexing failed\0A\00"
@weave.str.err_parse = private unnamed_addr constant [23 x i8] c"error: parsing failed\0A\00"
@weave.str.err_emit = private unnamed_addr constant [25 x i8] c"error: LLVM emit failed\0A\00"

; ----------------------------------------------------------------------------
; Helper accessors for constant strings
; ----------------------------------------------------------------------------
;
; These tiny functions keep later files readable. They also avoid repeating
; getelementptr forms everywhere.

define ptr @weave_cstr_usage() {
entry:
  ret ptr @weave.str.usage
}

define ptr @weave_cstr_err_read() {
entry:
  ret ptr @weave.str.err_read
}

define ptr @weave_cstr_err_write() {
entry:
  ret ptr @weave.str.err_write
}

define ptr @weave_cstr_err_lex() {
entry:
  ret ptr @weave.str.err_lex
}

define ptr @weave_cstr_err_parse() {
entry:
  ret ptr @weave.str.err_parse
}

define ptr @weave_cstr_err_emit() {
entry:
  ret ptr @weave.str.err_emit
}
