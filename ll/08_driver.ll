; =============================================================================
; Weave Stage 0 Bootstrap Compiler
; 08_driver.ll
;
; The driver connects the Stage 0 compiler pipeline.
;
; Responsibility:
;
;     input path -> source -> tokens -> AST -> LLVM buffer -> output path
;
; This file contains orchestration only. Lexer, parser, AST, and emitter logic
; belong in their own files.
; =============================================================================

; ----------------------------------------------------------------------------
; Source initialization
; ----------------------------------------------------------------------------
;
; The source owns the buffer returned by weave_rt_read_file.
; The caller must eventually call weave_source_free.


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
  br i1 %has_data, label %free_data, label %done

free_data:
  call void @free(ptr %data)
  br label %done

done:
  %data_field = call ptr @weave_source_data_ptr(ptr %source)
  %length_field = call ptr @weave_source_length_ptr(ptr %source)

  store ptr null, ptr %data_field
  store i64 0, ptr %length_field

  ret void
}

; ----------------------------------------------------------------------------
; Diagnostic helpers
; ----------------------------------------------------------------------------
;
; Diagnostics are intentionally blunt in Stage 0. Beautiful diagnostics belong
; later. The bridge must first be crossable.


define void @weave_driver_print_error(ptr %message) {
entry:
  %stderr = call ptr @weave_rt_stderr()
  call i32 (ptr, ptr, ...) @fprintf(ptr %stderr, ptr %message)
  ret void
}

; ----------------------------------------------------------------------------
; weave_compile_file
;
; Compile one Weave source file into one LLVM IR output file.
;
; Interface:
;
;     weavec0 input.weave output.ll
;
; Returns:
;   0 on success
;   1 on failure
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
  br i1 %lex_failed, label %lex_error, label %init_ast

lex_error:
  %msg_lex = call ptr @weave_cstr_err_lex()
  call void @weave_driver_print_error(ptr %msg_lex)
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

; ----------------------------------------------------------------------------
; weave_compile_buffer_to_buffer
;
; In-memory compilation entry point used later by tests and self-host smoke
; checks.
;
; The caller provides a source buffer and receives emitted LLVM text in `output`.
;
; This avoids file IO when testing the internal compiler pipeline.
;
; Returns:
;   0 on success
;   1 on failure
; ----------------------------------------------------------------------------


define i32 @weave_compile_buffer_to_buffer(
  ptr %source_data,
  i64 %source_len,
  ptr %output
) {
entry:
  %data_null = icmp eq ptr %source_data, null
  %output_null = icmp eq ptr %output, null
  %bad = or i1 %data_null, %output_null
  br i1 %bad, label %fail, label %init_source

init_source:
  %source = alloca %weave.Source
  call void @weave_source_init(ptr %source, ptr %source_data, i64 %source_len)

  %tokens = alloca %weave.Tokens
  %tokens_status = call i32 @weave_tokens_init(ptr %tokens)
  %tokens_failed = icmp ne i32 %tokens_status, 0
  br i1 %tokens_failed, label %fail, label %lex

lex:
  %lex_status = call i32 @weave_lex(ptr %source, ptr %tokens)
  %lex_failed = icmp ne i32 %lex_status, 0
  br i1 %lex_failed, label %cleanup_tokens_fail, label %init_ast

init_ast:
  %ast = alloca %weave.Ast
  %ast_status = call i32 @weave_ast_init(ptr %ast)
  %ast_failed = icmp ne i32 %ast_status, 0
  br i1 %ast_failed, label %cleanup_tokens_fail, label %parse

parse:
  %program_node = call i64 @weave_parse(ptr %tokens, ptr %ast)
  %parse_failed = icmp slt i64 %program_node, 0
  br i1 %parse_failed, label %cleanup_ast_tokens_fail, label %emit

emit:
  %emit_status = call i32 @weave_emit_llvm(ptr %source, ptr %ast, i64 %program_node, ptr %output)
  %emit_failed = icmp ne i32 %emit_status, 0
  br i1 %emit_failed, label %cleanup_ast_tokens_fail, label %cleanup_success

cleanup_success:
  call void @weave_ast_free(ptr %ast)
  call void @weave_tokens_free(ptr %tokens)
  ret i32 0

cleanup_ast_tokens_fail:
  call void @weave_ast_free(ptr %ast)
  br label %cleanup_tokens_fail

cleanup_tokens_fail:
  call void @weave_tokens_free(ptr %tokens)
  br label %fail

fail:
  ret i32 1
}
