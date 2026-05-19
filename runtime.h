/* =============================================================================
 * Weave Stage 0 Bootstrap Compiler
 * runtime.h
 *
 * Tiny C runtime interface used by the hand-written LLVM IR bootstrap compiler.
 *
 * The runtime handles boring platform tasks: files, streams, fatal errors.
 * It must not contain compiler logic. If a function understands Weave syntax,
 * tokens, AST nodes, or LLVM emission, it does not belong here.
 * =============================================================================
 */

#ifndef WEAVE_STAGE0_RUNTIME_H
#define WEAVE_STAGE0_RUNTIME_H

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Print a fatal error message and terminate the process with exit code 1. */
void weave_rt_fatal(const char *message) __attribute__((noreturn));

/*
 * Read an entire file into a null-terminated byte buffer.
 *
 * Returns NULL on failure.
 *
 * On success:
 *   - returns an allocated buffer owned by the caller
 *   - stores the byte length, excluding the final null terminator, into out_len
 *   - guarantees buffer[out_len] == '\0'
 */
char *weave_rt_read_file(const char *path, uint64_t *out_len);

/*
 * Write exactly length bytes to path.
 *
 * Returns:
 *   0 on success
 *   1 on failure
 */
int32_t weave_rt_write_file(const char *path, const char *data, uint64_t length);

/* Return standard streams as opaque FILE* values for LLVM IR callers. */
FILE *weave_rt_stdout(void);
FILE *weave_rt_stderr(void);

#ifdef __cplusplus
}
#endif

#endif /* WEAVE_STAGE0_RUNTIME_H */
