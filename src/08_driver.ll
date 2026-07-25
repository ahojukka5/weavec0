; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 08_driver.ll
;
; Pipeline orchestration for the Stage 0 bootstrap compiler.
;
; Responsibilities:
;   - read the input into an owned, null-terminated source buffer
;   - initialise source, token, AST, and output storage
;   - drive lex -> version validation -> parse -> emit
;   - free every partially constructed stage on failure
; =============================================================================

; ----------------------------------------------------------------------------
; Source ownership
; ----------------------------------------------------------------------------

define void @weave_source_init(ptr %source, ptr %data, i64 %length) {
entry:
  %data_field = call ptr @weave_source_data_ptr(ptr %source)
  %length_field = call ptr @weave_source_length_ptr(ptr %source)
  store ptr %data, ptr %data_field
  store i64 %length, ptr %length_field
  ret void
}

define void @weave_source_free(ptr %source) {
entry:
  %data = call ptr @weave_source_data(ptr %source)
  %has_data = icmp ne ptr %data, null
  br i1 %has_data, label %free_data, label %reset

free_data:
  call void @free(ptr %data)
  br label %reset

reset:
  %data_field = call ptr @weave_source_data_ptr(ptr %source)
  %length_field = call ptr @weave_source_length_ptr(ptr %source)
  store ptr null, ptr %data_field
  store i64 0, ptr %length_field
  ret void
}

; ----------------------------------------------------------------------------
; Diagnostics
; ----------------------------------------------------------------------------

define void @weave_driver_print_error(ptr %message) {
entry:
  %stderr = call ptr @weave_rt_stderr()
  call i32 (ptr, ptr, ...) @fprintf(ptr %stderr, ptr %message)
  ret void
}

; ----------------------------------------------------------------------------
; Stable WIR contract validation
; ----------------------------------------------------------------------------

; Validate the fixed token prefix:
;   ( core-module ( core-version 1 ) ...
; This is a pipeline-contract check, not general parsing.
define i32 @weave_validate_core_version(ptr %tokens) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %has_prefix = icmp uge i64 %count, 6
  br i1 %has_prefix, label %read_prefix, label %unsupported

read_prefix:
  %kind0 = call i32 @weave_token_kind(ptr %tokens, i64 0)
  %kind1 = call i32 @weave_token_kind(ptr %tokens, i64 1)
  %kind2 = call i32 @weave_token_kind(ptr %tokens, i64 2)
  %kind3 = call i32 @weave_token_kind(ptr %tokens, i64 3)
  %kind4 = call i32 @weave_token_kind(ptr %tokens, i64 4)
  %kind5 = call i32 @weave_token_kind(ptr %tokens, i64 5)
  %version = call i64 @weave_token_value(ptr %tokens, i64 4)
  %ok0 = icmp eq i32 %kind0, 1
  %ok1 = icmp eq i32 %kind1, 25
  %ok2 = icmp eq i32 %kind2, 1
  %ok3 = icmp eq i32 %kind3, 26
  %ok4 = icmp eq i32 %kind4, 4
  %ok5 = icmp eq i32 %kind5, 2
  %version_ok = icmp eq i64 %version, 1
  %a = and i1 %ok0, %ok1
  %b = and i1 %ok2, %ok3
  %c = and i1 %ok4, %ok5
  %ab = and i1 %a, %b
  %abc = and i1 %ab, %c
  %all_ok = and i1 %abc, %version_ok
  br i1 %all_ok, label %supported, label %unsupported

supported:
  ret i32 1

unsupported:
  ret i32 0
}

; ----------------------------------------------------------------------------
; File-to-file compilation
; ----------------------------------------------------------------------------

define i32 @weave_compile_file(ptr %input_path, ptr %output_path) {
entry:
  %input_is_null = icmp eq ptr %input_path, null
  %output_is_null = icmp eq ptr %output_path, null
  %bad_args = or i1 %input_is_null, %output_is_null
  br i1 %bad_args, label %fail, label %read_source

read_source:
  %source_len_storage = alloca i64
  store i64 0, ptr %source_len_storage
  %source_data = call ptr @weave_rt_read_file(ptr %input_path, ptr %source_len_storage)
  %read_failed = icmp eq ptr %source_data, null
  br i1 %read_failed, label %read_error, label %init_source

read_error:
  %msg_read = call ptr @weave_cstr_err_read()
  call void @weave_driver_print_error(ptr %msg_read)
  br label %fail

init_source:
  %source_len = load i64, ptr %source_len_storage
  %source = alloca %weave.Source
  call void @weave_source_init(ptr %source, ptr %source_data, i64 %source_len)
  %tokens = alloca %weave.Tokens
  %tokens_status = call i32 @weave_tokens_init(ptr %tokens)
  %tokens_failed = icmp ne i32 %tokens_status, 0
  br i1 %tokens_failed, label %cleanup_source_fail, label %lex

lex:
  %lex_status = call i32 @weave_lex(ptr %source, ptr %tokens)
  %lex_failed = icmp ne i32 %lex_status, 0
  br i1 %lex_failed, label %lex_error, label %validate_version

lex_error:
  %msg_lex = call ptr @weave_cstr_err_lex()
  call void @weave_driver_print_error(ptr %msg_lex)
  br label %cleanup_tokens_source_fail

validate_version:
  %version_ok_status = call i32 @weave_validate_core_version(ptr %tokens)
  %version_bad = icmp eq i32 %version_ok_status, 0
  br i1 %version_bad, label %version_error, label %init_ast

version_error:
  %msg_version = call ptr @weave_cstr_err_parse()
  call void @weave_driver_print_error(ptr %msg_version)
  br label %cleanup_tokens_source_fail

init_ast:
  %ast = alloca %weave.Ast
  %ast_status = call i32 @weave_ast_init(ptr %ast)
  %ast_failed = icmp ne i32 %ast_status, 0
  br i1 %ast_failed, label %cleanup_tokens_source_fail, label %parse

parse:
  %program_node = call i64 @weave_parse(ptr %tokens, ptr %ast)
  %parse_failed = icmp slt i64 %program_node, 0
  br i1 %parse_failed, label %parse_error, label %init_output

parse_error:
  %parse_error_code = call i32 @weave_parse_error_get()
  %is_unknown_operator = icmp eq i32 %parse_error_code, 1
  br i1 %is_unknown_operator, label %parse_unknown_operator, label %check_parse_arity

check_parse_arity:
  %is_invalid_arity = icmp eq i32 %parse_error_code, 2
  br i1 %is_invalid_arity, label %parse_invalid_arity, label %parse_generic_error

parse_unknown_operator:
  %msg_unknown_operator = call ptr @weave_cstr_err_unknown_operator()
  call void @weave_driver_print_error(ptr %msg_unknown_operator)
  br label %cleanup_ast_tokens_source_fail

parse_invalid_arity:
  %msg_invalid_arity = call ptr @weave_cstr_err_invalid_arity()
  call void @weave_driver_print_error(ptr %msg_invalid_arity)
  br label %cleanup_ast_tokens_source_fail

parse_generic_error:
  %msg_parse = call ptr @weave_cstr_err_parse()
  call void @weave_driver_print_error(ptr %msg_parse)
  br label %cleanup_ast_tokens_source_fail

init_output:
  %output = alloca %weave.Buffer
  %output_status = call i32 @weave_buffer_init(ptr %output)
  %output_failed = icmp ne i32 %output_status, 0
  br i1 %output_failed, label %cleanup_ast_tokens_source_fail, label %emit

emit:
  %emit_status = call i32 @weave_emit_llvm(ptr %source, ptr %ast, i64 %program_node, ptr %output)
  %emit_failed = icmp ne i32 %emit_status, 0
  br i1 %emit_failed, label %emit_error, label %write_output

emit_error:
  %msg_emit = call ptr @weave_cstr_err_emit()
  call void @weave_driver_print_error(ptr %msg_emit)
  br label %cleanup_output_ast_tokens_source_fail

write_output:
  %out_data = call ptr @weave_buffer_data(ptr %output)
  %out_len = call i64 @weave_buffer_length(ptr %output)
  %write_status = call i32 @weave_rt_write_file(ptr %output_path, ptr %out_data, i64 %out_len)
  %write_failed = icmp ne i32 %write_status, 0
  br i1 %write_failed, label %write_error, label %cleanup_success

write_error:
  %msg_write = call ptr @weave_cstr_err_write()
  call void @weave_driver_print_error(ptr %msg_write)
  br label %cleanup_output_ast_tokens_source_fail

cleanup_success:
  call void @weave_buffer_free(ptr %output)
  call void @weave_ast_free(ptr %ast)
  call void @weave_tokens_free(ptr %tokens)
  call void @weave_source_free(ptr %source)
  ret i32 0

cleanup_output_ast_tokens_source_fail:
  call void @weave_buffer_free(ptr %output)
  br label %cleanup_ast_tokens_source_fail

cleanup_ast_tokens_source_fail:
  call void @weave_ast_free(ptr %ast)
  br label %cleanup_tokens_source_fail

cleanup_tokens_source_fail:
  call void @weave_tokens_free(ptr %tokens)
  br label %cleanup_source_fail

cleanup_source_fail:
  call void @weave_source_free(ptr %source)
  br label %fail

fail:
  ret i32 1
}
