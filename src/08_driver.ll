; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 08_driver.ll
;
; Pipeline orchestration for the Stage 0 bootstrap compiler.
;
; Responsibilities:
;   - read the input into an owned, null-terminated source buffer
;   - initialise source, token, AST, and output storage
;   - drive lex -> contract validation -> parse -> emit
;   - validate the fixed WIR core version and admitted extern signatures before
;     the parser discards extern signature syntax
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
;   ( core-module ( core-version 2 ) ...
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
  %version_ok = icmp eq i64 %version, 2
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

; Extern declarations carry an explicit WIR signature even though the LLVM
; declaration text is selected from a small name-keyed ABI table. Validate the
; written signature before parsing so source and emitted ABI cannot disagree.
;
; A signature is packed into one i64:
;   bits  0..7  parameter count
;   bits  8..15 parameter 0 token kind
;   bits 16..23 parameter 1 token kind
;   bits 24..31 parameter 2 token kind
;   bits 32..39 return type token kind
%weave.ExternAbi = type { ptr, i64, i64 }

@weave.validate.extern.puts = private unnamed_addr constant [5 x i8] c"puts\00"
@weave.validate.extern.malloc = private unnamed_addr constant [7 x i8] c"malloc\00"
@weave.validate.extern.free = private unnamed_addr constant [5 x i8] c"free\00"
@weave.validate.extern.realloc = private unnamed_addr constant [8 x i8] c"realloc\00"
@weave.validate.extern.memcpy = private unnamed_addr constant [7 x i8] c"memcpy\00"
@weave.validate.extern.strlen = private unnamed_addr constant [7 x i8] c"strlen\00"
@weave.validate.extern.strcmp = private unnamed_addr constant [7 x i8] c"strcmp\00"
@weave.validate.extern.strncmp = private unnamed_addr constant [8 x i8] c"strncmp\00"
@weave.validate.extern.atoi = private unnamed_addr constant [5 x i8] c"atoi\00"
@weave.validate.extern.putchar = private unnamed_addr constant [8 x i8] c"putchar\00"
@weave.validate.extern.read_file = private unnamed_addr constant [19 x i8] c"weave_rt_read_file\00"
@weave.validate.extern.write_file = private unnamed_addr constant [20 x i8] c"weave_rt_write_file\00"
@weave.validate.extern.fatal = private unnamed_addr constant [15 x i8] c"weave_rt_fatal\00"

@weave.validate.extern_abis = private constant [13 x %weave.ExternAbi] [
  %weave.ExternAbi { ptr @weave.validate.extern.puts, i64 4, i64 137438968321 },
  %weave.ExternAbi { ptr @weave.validate.extern.malloc, i64 6, i64 249108113153 },
  %weave.ExternAbi { ptr @weave.validate.extern.free, i64 4, i64 253403085313 },
  %weave.ExternAbi { ptr @weave.validate.extern.realloc, i64 7, i64 249110673922 },
  %weave.ExternAbi { ptr @weave.validate.extern.memcpy, i64 6, i64 249766230531 },
  %weave.ExternAbi { ptr @weave.validate.extern.strlen, i64 6, i64 167503739393 },
  %weave.ExternAbi { ptr @weave.validate.extern.strcmp, i64 6, i64 137442769410 },
  %weave.ExternAbi { ptr @weave.validate.extern.strncmp, i64 7, i64 138097080835 },
  %weave.ExternAbi { ptr @weave.validate.extern.atoi, i64 4, i64 137438968321 },
  %weave.ExternAbi { ptr @weave.validate.extern.putchar, i64 7, i64 137438961665 },
  %weave.ExternAbi { ptr @weave.validate.extern.read_file, i64 18, i64 249111919106 },
  %weave.ExternAbi { ptr @weave.validate.extern.write_file, i64 19, i64 138097080835 },
  %weave.ExternAbi { ptr @weave.validate.extern.fatal, i64 14, i64 253403085313 }
]

define i32 @weave_validate_admitted_extern_signature(
  ptr %source,
  ptr %tokens,
  i64 %name_index,
  i64 %signature
) {
entry:
  %source_data = call ptr @weave_source_data(ptr %source)
  %name_start = call i64 @weave_token_start(ptr %tokens, i64 %name_index)
  %name_length = call i64 @weave_token_length(ptr %tokens, i64 %name_index)
  %name = getelementptr inbounds i8, ptr %source_data, i64 %name_start
  br label %lookup

lookup:
  %table_index = phi i64 [0, %entry], [%next_index, %next]
  %done = icmp uge i64 %table_index, 13
  br i1 %done, label %unknown, label %compare_name

compare_name:
  %row = getelementptr inbounds [13 x %weave.ExternAbi],
    ptr @weave.validate.extern_abis, i64 0, i64 %table_index
  %expected_name_ptr = getelementptr inbounds %weave.ExternAbi,
    ptr %row, i32 0, i32 0
  %expected_length_ptr = getelementptr inbounds %weave.ExternAbi,
    ptr %row, i32 0, i32 1
  %expected_signature_ptr = getelementptr inbounds %weave.ExternAbi,
    ptr %row, i32 0, i32 2
  %expected_name = load ptr, ptr %expected_name_ptr
  %expected_length = load i64, ptr %expected_length_ptr
  %name_equal_status = call i32 @weave_bytes_equal(
    ptr %name, i64 %name_length, ptr %expected_name, i64 %expected_length)
  %name_equal = icmp ne i32 %name_equal_status, 0
  br i1 %name_equal, label %compare_signature, label %next

compare_signature:
  %expected_signature = load i64, ptr %expected_signature_ptr
  %signature_equal = icmp eq i64 %signature, %expected_signature
  %result = zext i1 %signature_equal to i32
  ret i32 %result

next:
  %next_index = add i64 %table_index, 1
  br label %lookup

unknown:
  ; Unknown extern names remain the emitter's responsibility. Their syntax must
  ; still be structurally valid, but there is no admitted ABI to compare here.
  ret i32 1
}

define i64 @weave_validate_one_extern(
  ptr %source,
  ptr %tokens,
  i64 %extern_index
) {
entry:
  %param_count_storage = alloca i64
  %param0_storage = alloca i32
  %param1_storage = alloca i32
  %param2_storage = alloca i32
  %cursor_storage = alloca i64
  store i64 0, ptr %param_count_storage
  store i32 0, ptr %param0_storage
  store i32 0, ptr %param1_storage
  store i32 0, ptr %param2_storage
  %at_start = icmp eq i64 %extern_index, 0
  br i1 %at_start, label %fail, label %check_open

check_open:
  %open_index = sub i64 %extern_index, 1
  %open_kind = call i32 @weave_token_kind(ptr %tokens, i64 %open_index)
  %open_ok = icmp eq i32 %open_kind, 1
  br i1 %open_ok, label %check_name, label %fail

check_name:
  %name_index = add i64 %extern_index, 1
  %name_kind = call i32 @weave_token_kind(ptr %tokens, i64 %name_index)
  %name_ok = icmp eq i32 %name_kind, 3
  br i1 %name_ok, label %check_params_open, label %fail

check_params_open:
  %params_open_index = add i64 %extern_index, 2
  %params_open_kind = call i32 @weave_token_kind(ptr %tokens, i64 %params_open_index)
  %params_open_ok = icmp eq i32 %params_open_kind, 1
  br i1 %params_open_ok, label %check_params_head, label %fail

check_params_head:
  %params_head_index = add i64 %extern_index, 3
  %params_head_kind = call i32 @weave_token_kind(ptr %tokens, i64 %params_head_index)
  %params_head_ok = icmp eq i32 %params_head_kind, 28
  br i1 %params_head_ok, label %init_param_loop, label %fail

init_param_loop:
  %first_param_index = add i64 %extern_index, 4
  store i64 %first_param_index, ptr %cursor_storage
  br label %param_loop

param_loop:
  %cursor = load i64, ptr %cursor_storage
  %kind = call i32 @weave_token_kind(ptr %tokens, i64 %cursor)
  %params_done = icmp eq i32 %kind, 2
  br i1 %params_done, label %check_returns_open, label %check_param_open

check_param_open:
  %param_open_ok = icmp eq i32 %kind, 1
  br i1 %param_open_ok, label %check_param_name, label %fail

check_param_name:
  %param_name_index = add i64 %cursor, 1
  %param_name_kind = call i32 @weave_token_kind(ptr %tokens, i64 %param_name_index)
  %param_name_ok = icmp eq i32 %param_name_kind, 3
  br i1 %param_name_ok, label %check_param_type, label %fail

check_param_type:
  %param_type_index = add i64 %cursor, 2
  %param_type = call i32 @weave_token_kind(ptr %tokens, i64 %param_type_index)
  %param_is_i32 = icmp eq i32 %param_type, 32
  %param_is_i64 = icmp eq i32 %param_type, 39
  %param_is_ptr = icmp eq i32 %param_type, 58
  %param_int_ok = or i1 %param_is_i32, %param_is_i64
  %param_type_ok = or i1 %param_int_ok, %param_is_ptr
  br i1 %param_type_ok, label %check_param_close, label %fail

check_param_close:
  %param_close_index = add i64 %cursor, 3
  %param_close_kind = call i32 @weave_token_kind(ptr %tokens, i64 %param_close_index)
  %param_close_ok = icmp eq i32 %param_close_kind, 2
  br i1 %param_close_ok, label %store_param, label %fail

store_param:
  %param_count = load i64, ptr %param_count_storage
  %too_many = icmp uge i64 %param_count, 3
  br i1 %too_many, label %fail, label %select_param_slot

select_param_slot:
  switch i64 %param_count, label %fail [
    i64 0, label %store_param0
    i64 1, label %store_param1
    i64 2, label %store_param2
  ]

store_param0:
  store i32 %param_type, ptr %param0_storage
  br label %advance_param

store_param1:
  store i32 %param_type, ptr %param1_storage
  br label %advance_param

store_param2:
  store i32 %param_type, ptr %param2_storage
  br label %advance_param

advance_param:
  %next_param_count = add i64 %param_count, 1
  %next_cursor = add i64 %cursor, 4
  store i64 %next_param_count, ptr %param_count_storage
  store i64 %next_cursor, ptr %cursor_storage
  br label %param_loop

check_returns_open:
  %returns_open_index = add i64 %cursor, 1
  %returns_open_kind = call i32 @weave_token_kind(ptr %tokens, i64 %returns_open_index)
  %returns_open_ok = icmp eq i32 %returns_open_kind, 1
  br i1 %returns_open_ok, label %check_returns_head, label %fail

check_returns_head:
  %returns_head_index = add i64 %cursor, 2
  %returns_head_kind = call i32 @weave_token_kind(ptr %tokens, i64 %returns_head_index)
  %returns_head_ok = icmp eq i32 %returns_head_kind, 29
  br i1 %returns_head_ok, label %check_return_type, label %fail

check_return_type:
  %return_type_index = add i64 %cursor, 3
  %return_type = call i32 @weave_token_kind(ptr %tokens, i64 %return_type_index)
  %return_is_i32 = icmp eq i32 %return_type, 32
  %return_is_i64 = icmp eq i32 %return_type, 39
  %return_is_ptr = icmp eq i32 %return_type, 58
  %return_is_void = icmp eq i32 %return_type, 59
  %return_int_ok = or i1 %return_is_i32, %return_is_i64
  %return_value_ok = or i1 %return_int_ok, %return_is_ptr
  %return_type_ok = or i1 %return_value_ok, %return_is_void
  br i1 %return_type_ok, label %check_returns_close, label %fail

check_returns_close:
  %returns_close_index = add i64 %cursor, 4
  %returns_close_kind = call i32 @weave_token_kind(ptr %tokens, i64 %returns_close_index)
  %returns_close_ok = icmp eq i32 %returns_close_kind, 2
  br i1 %returns_close_ok, label %check_extern_close, label %fail

check_extern_close:
  %extern_close_index = add i64 %cursor, 5
  %extern_close_kind = call i32 @weave_token_kind(ptr %tokens, i64 %extern_close_index)
  %extern_close_ok = icmp eq i32 %extern_close_kind, 2
  br i1 %extern_close_ok, label %check_signature, label %fail

check_signature:
  %final_param_count = load i64, ptr %param_count_storage
  %param0 = load i32, ptr %param0_storage
  %param1 = load i32, ptr %param1_storage
  %param2 = load i32, ptr %param2_storage
  %param0_wide = zext i32 %param0 to i64
  %param1_wide = zext i32 %param1 to i64
  %param2_wide = zext i32 %param2 to i64
  %return_type_wide = zext i32 %return_type to i64
  %param0_bits = shl i64 %param0_wide, 8
  %param1_bits = shl i64 %param1_wide, 16
  %param2_bits = shl i64 %param2_wide, 24
  %return_bits = shl i64 %return_type_wide, 32
  %signature0 = or i64 %final_param_count, %param0_bits
  %signature1 = or i64 %signature0, %param1_bits
  %signature2 = or i64 %signature1, %param2_bits
  %signature = or i64 %signature2, %return_bits
  %signature_ok_status = call i32 @weave_validate_admitted_extern_signature(
    ptr %source, ptr %tokens, i64 %name_index, i64 %signature
  )
  %signature_ok = icmp ne i32 %signature_ok_status, 0
  br i1 %signature_ok, label %success, label %fail

success:
  %next_index = add i64 %cursor, 6
  ret i64 %next_index

fail:
  ret i64 -1
}

define i32 @weave_validate_extern_signatures(ptr %source, ptr %tokens) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  br label %scan

scan:
  %index = phi i64 [0, %entry], [%plain_next, %advance], [%extern_next, %after_extern]
  %done = icmp uge i64 %index, %count
  br i1 %done, label %valid, label %classify

classify:
  %kind = call i32 @weave_token_kind(ptr %tokens, i64 %index)
  %is_extern = icmp eq i32 %kind, 57
  br i1 %is_extern, label %validate_extern, label %advance

advance:
  %plain_next = add i64 %index, 1
  br label %scan

validate_extern:
  %extern_next = call i64 @weave_validate_one_extern(
    ptr %source, ptr %tokens, i64 %index)
  %extern_failed = icmp slt i64 %extern_next, 0
  br i1 %extern_failed, label %invalid, label %after_extern

after_extern:
  br label %scan

valid:
  ret i32 1

invalid:
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
  br i1 %version_bad, label %version_error, label %validate_externs

version_error:
  %msg_version = call ptr @weave_cstr_err_parse()
  call void @weave_driver_print_error(ptr %msg_version)
  br label %cleanup_tokens_source_fail

validate_externs:
  %externs_ok_status = call i32 @weave_validate_extern_signatures(
    ptr %source, ptr %tokens)
  %externs_bad = icmp eq i32 %externs_ok_status, 0
  br i1 %externs_bad, label %extern_error, label %init_ast

extern_error:
  %msg_extern = call ptr @weave_cstr_err_parse()
  call void @weave_driver_print_error(ptr %msg_extern)
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
