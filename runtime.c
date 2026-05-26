/* SPDX-License-Identifier: Apache-2.0 */
/* =============================================================================
 * Weave Stage 0 Bootstrap Compiler
 * runtime.c
 *
 * Tiny C runtime implementation used by the hand-written LLVM IR bootstrap
 * compiler.
 *
 * This file deliberately contains no compiler logic. It only provides small,
 * predictable platform services for the LLVM IR code.
 * =============================================================================
 */

#include "runtime.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void weave_rt_fatal(const char *message)
{
    if (message != NULL) {
        fputs(message, stderr);
    } else {
        fputs("fatal error\n", stderr);
    }

    exit(1);
}

char *weave_rt_read_file(const char *path, uint64_t *out_len)
{
    if (out_len != NULL) {
        *out_len = 0;
    }

    if (path == NULL || out_len == NULL) {
        return NULL;
    }

    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }

    long end_position = ftell(file);
    if (end_position < 0) {
        fclose(file);
        return NULL;
    }

    if (fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }

    uint64_t length = (uint64_t)end_position;

    if (length > UINT64_MAX - 1) {
        fclose(file);
        return NULL;
    }

    char *buffer = (char *)malloc(length + 1);
    if (buffer == NULL) {
        fclose(file);
        return NULL;
    }

    size_t bytes_read = fread(buffer, 1, (size_t)length, file);
    if (bytes_read != (size_t)length) {
        free(buffer);
        fclose(file);
        return NULL;
    }

    if (fclose(file) != 0) {
        free(buffer);
        return NULL;
    }

    buffer[length] = '\0';
    *out_len = length;

    return buffer;
}

int32_t weave_rt_write_file(const char *path, const char *data, uint64_t length)
{
    if (path == NULL) {
        return 1;
    }

    if (data == NULL && length != 0) {
        return 1;
    }

    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        return 1;
    }

    size_t bytes_written = 0;

    if (length != 0) {
        bytes_written = fwrite(data, 1, (size_t)length, file);
    }

    int flush_failed = fflush(file) != 0;
    int close_failed = fclose(file) != 0;

    if (bytes_written != (size_t)length || flush_failed || close_failed) {
        return 1;
    }

    return 0;
}

FILE *weave_rt_stdout(void)
{
    return stdout;
}

FILE *weave_rt_stderr(void)
{
    return stderr;
}
