; =============================================================================
; Weave Stage 0 Bootstrap Compiler
; 06_parser.ll
;
; Minimal recursive-descent parser for the Stage 0 bootstrap subset.
;
; Responsibility:
;
;     token stream -> AST
;
; The parser accepts the WIR/TIR bootstrap subset. It fails fast on unsupported
; input. There is no recovery, no diagnostics framework, and no type checking.
; =============================================================================

; ----------------------------------------------------------------------------
; Parser layout reminder
; ----------------------------------------------------------------------------
;
; %weave.Parser = type { ptr, i64 }
;
; field 0 : ptr to %weave.Tokens
; field 1 : current token index

; ----------------------------------------------------------------------------
; Parser field helpers
; ----------------------------------------------------------------------------

define ptr @weave_parser_tokens_ptr(ptr %parser) {
entry:
  %field = getelementptr inbounds %weave.Parser, ptr %parser, i32 0, i32 0
  ret ptr %field
}

define ptr @weave_parser_index_ptr(ptr %parser) {
entry:
  %field = getelementptr inbounds %weave.Parser, ptr %parser, i32 0, i32 1
  ret ptr %field
}

define ptr @weave_parser_tokens(ptr %parser) {
entry:
  %field = call ptr @weave_parser_tokens_ptr(ptr %parser)
  %tokens = load ptr, ptr %field
  ret ptr %tokens
}

define i64 @weave_parser_index(ptr %parser) {
entry:
  %field = call ptr @weave_parser_index_ptr(ptr %parser)
  %index = load i64, ptr %field
  ret i64 %index
}

define void @weave_parser_set_index(ptr %parser, i64 %index) {
entry:
  %field = call ptr @weave_parser_index_ptr(ptr %parser)
  store i64 %index, ptr %field
  ret void
}

; ----------------------------------------------------------------------------
; weave_parser_init
; ----------------------------------------------------------------------------

define void @weave_parser_init(ptr %parser, ptr %tokens) {
entry:
  %tokens_field = call ptr @weave_parser_tokens_ptr(ptr %parser)
  %index_field = call ptr @weave_parser_index_ptr(ptr %parser)
  store ptr %tokens, ptr %tokens_field
  store i64 0, ptr %index_field
  ret void
}

; ----------------------------------------------------------------------------
; Current token helpers
; ----------------------------------------------------------------------------

define i32 @weave_parser_current_kind(ptr %parser) {
entry:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %kind = call i32 @weave_token_kind(ptr %tokens, i64 %index)
  ret i32 %kind
}

define i64 @weave_parser_current_start(ptr %parser) {
entry:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %start = call i64 @weave_token_start(ptr %tokens, i64 %index)
  ret i64 %start
}

define i64 @weave_parser_current_length(ptr %parser) {
entry:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %length = call i64 @weave_token_length(ptr %tokens, i64 %index)
  ret i64 %length
}

define i32 @weave_parser_current_value(ptr %parser) {
entry:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %value = call i32 @weave_token_value(ptr %tokens, i64 %index)
  ret i32 %value
}

define void @weave_parser_advance(ptr %parser) {
entry:
  %index = call i64 @weave_parser_index(ptr %parser)
  %next = add i64 %index, 1
  call void @weave_parser_set_index(ptr %parser, i64 %next)
  ret void
}

; ----------------------------------------------------------------------------
; weave_parser_match
;
; If the current token has kind `expected`, consume it and return 1.
; Otherwise return 0.
; ----------------------------------------------------------------------------

define i32 @weave_parser_match(ptr %parser, i32 %expected) {
entry:
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %ok = icmp eq i32 %kind, %expected
  br i1 %ok, label %consume, label %no

consume:
  call void @weave_parser_advance(ptr %parser)
  ret i32 1

no:
  ret i32 0
}

; ----------------------------------------------------------------------------
; weave_parser_expect
;
; Consume `expected` or fail.
;
; Returns:
;   0 on success
;   1 on failure
; ----------------------------------------------------------------------------

define i32 @weave_parser_expect(ptr %parser, i32 %expected) {
entry:
  %matched = call i32 @weave_parser_match(ptr %parser, i32 %expected)
  %ok = icmp ne i32 %matched, 0
  br i1 %ok, label %success, label %fail

success:
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; Operator mapping
; ----------------------------------------------------------------------------
;
; Convert a token kind into a BIN_* operator id.
; Returns 0 if the token is not a binary operator.


define i32 @weave_parser_binary_operator(i32 %kind) {
entry:
  %is_add_i32 = icmp eq i32 %kind, 44
  br i1 %is_add_i32, label %add, label %check_lt

check_lt:
  %is_lt = icmp eq i32 %kind, 37
  br i1 %is_lt, label %lt, label %check_add_i64

check_add_i64:
  %is_add_i64 = icmp eq i32 %kind, 42
  br i1 %is_add_i64, label %add_i64, label %check_mul_i64

check_mul_i64:
  %is_mul_i64 = icmp eq i32 %kind, 43
  br i1 %is_mul_i64, label %mul_i64, label %check_sub_i64

check_sub_i64:
  %is_sub_i64 = icmp eq i32 %kind, 84
  br i1 %is_sub_i64, label %sub_i64, label %check_lt_i64

check_lt_i64:
  %is_lt_i64 = icmp eq i32 %kind, 46
  br i1 %is_lt_i64, label %lt_i64, label %check_le_i64

check_le_i64:
  %is_le_i64 = icmp eq i32 %kind, 47
  br i1 %is_le_i64, label %le_i64, label %check_ne_i64

check_ne_i64:
  %is_ne_i64 = icmp eq i32 %kind, 48
  br i1 %is_ne_i64, label %ne_i64, label %check_eq_i64

check_eq_i64:
  %is_eq_i64 = icmp eq i32 %kind, 85
  br i1 %is_eq_i64, label %eq_i64, label %check_and_bool

check_and_bool:
  %is_and_bool = icmp eq i32 %kind, 52
  br i1 %is_and_bool, label %and_bool, label %check_or_bool

check_or_bool:
  %is_or_bool = icmp eq i32 %kind, 53
  br i1 %is_or_bool, label %or_bool, label %check_eq_ptr

check_eq_ptr:
  %is_eq_ptr = icmp eq i32 %kind, 55
  br i1 %is_eq_ptr, label %eq_ptr, label %check_ne_ptr

check_ne_ptr:
  %is_ne_ptr = icmp eq i32 %kind, 56
  br i1 %is_ne_ptr, label %ne_ptr, label %check_mod_i32

check_mod_i32:
  %is_mod_i32 = icmp eq i32 %kind, 69
  br i1 %is_mod_i32, label %mod_i32, label %check_ne_i32

check_ne_i32:
  %is_ne_i32 = icmp eq i32 %kind, 74
  br i1 %is_ne_i32, label %ne_i32, label %check_eq_i32

check_eq_i32:
  %is_eq_i32 = icmp eq i32 %kind, 75
  br i1 %is_eq_i32, label %eq_i32, label %check_ge_i32

check_ge_i32:
  %is_ge_i32 = icmp eq i32 %kind, 76
  br i1 %is_ge_i32, label %ge_i32, label %check_le_i32

check_le_i32:
  %is_le_i32 = icmp eq i32 %kind, 77
  br i1 %is_le_i32, label %le_i32, label %check_mul_i32

check_mul_i32:
  %is_mul_i32 = icmp eq i32 %kind, 78
  br i1 %is_mul_i32, label %mul_i32, label %check_div_i32

check_div_i32:
  %is_div_i32 = icmp eq i32 %kind, 79
  br i1 %is_div_i32, label %div_i32, label %none

add:
  ret i32 1

lt:
  ret i32 7

add_i64:
  ret i32 11

mul_i64:
  ret i32 12

sub_i64:
  ret i32 27

lt_i64:
  ret i32 13

le_i64:
  ret i32 14

ne_i64:
  ret i32 15

eq_i64:
  ret i32 28

and_bool:
  ret i32 16

or_bool:
  ret i32 17

eq_ptr:
  ret i32 18

ne_ptr:
  ret i32 19

mod_i32:
  ret i32 20

ne_i32:
  ret i32 21

eq_i32:
  ret i32 22

ge_i32:
  ret i32 23

le_i32:
  ret i32 24

mul_i32:
  ret i32 25

div_i32:
  ret i32 26

none:
  ret i32 0
}

; ----------------------------------------------------------------------------
; Forward declarations for mutually recursive parser functions
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; weave_parse_atom
;
; Parse one atomic expression:
;
; WIR expressions are parenthesized forms. Bare atoms are accepted only by
; form-specific parsers after they consume a keyword such as `const_i32`.
;
; Returns AST node index or -1 on failure.
; ----------------------------------------------------------------------------

define i64 @weave_parse_atom(ptr %parser, ptr %ast) {
entry:
  ret i64 -1
}

define i64 @weave_parse_arg_list(ptr %parser, ptr %ast) {
entry:
  br label %loop

loop:
  %list_head = phi i64 [-1, %entry], [%list_node, %after_arg]
  %count = phi i64 [0, %entry], [%count_next, %after_arg]
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %done = icmp eq i32 %kind, 2
  br i1 %done, label %finish, label %parse_arg

parse_arg:
  %arg = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %arg_failed = icmp slt i64 %arg, 0
  br i1 %arg_failed, label %fail, label %make_list_node

make_list_node:
  %list_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %arg,
    i64 %list_head,
    i64 0,
    i64 0,
    i64 0
  )
  %list_failed = icmp slt i64 %list_node, 0
  br i1 %list_failed, label %fail, label %after_arg

after_arg:
  %count_next = add i64 %count, 1
  br label %loop

finish:
  %wrapper = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %list_head,
    i64 -1,
    i64 %count,
    i64 0,
    i64 0
  )
  ret i64 %wrapper

fail:
  ret i64 -1
}

define i64 @weave_parse_wir_param(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %read_name

read_name:
  %name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_ident = icmp eq i32 %name_kind, 3
  br i1 %is_ident, label %capture_name, label %fail

capture_name:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %type_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_i32 = icmp eq i32 %type_kind, 32
  %is_i64 = icmp eq i32 %type_kind, 39
  %is_ptr = icmp eq i32 %type_kind, 58
  %is_bool = icmp eq i32 %type_kind, 72
  %int_ok = or i1 %is_i32, %is_i64
  %ptr_ok = or i1 %int_ok, %is_ptr
  %type_ok = or i1 %ptr_ok, %is_bool
  br i1 %type_ok, label %consume_type, label %fail

consume_type:
  call void @weave_parser_advance(ptr %parser)
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %type_wide = sext i32 %type_kind to i64
  %param_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 30,
    i64 %type_wide,
    i64 0,
    i64 0,
    i64 %name_start,
    i64 %name_len
  )
  ret i64 %param_node

fail:
  ret i64 -1
}

define i64 @weave_parse_wir_params(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_params

expect_params:
  %params_status = call i32 @weave_parser_expect(ptr %parser, i32 28)
  %params_failed = icmp ne i32 %params_status, 0
  br i1 %params_failed, label %fail, label %loop

loop:
  %list_head = phi i64 [-1, %expect_params], [%list_node, %after_param]
  %count = phi i64 [0, %expect_params], [%count_next, %after_param]
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %done = icmp eq i32 %kind, 2
  br i1 %done, label %finish, label %parse_param

parse_param:
  %param = call i64 @weave_parse_wir_param(ptr %parser, ptr %ast)
  %param_failed = icmp slt i64 %param, 0
  br i1 %param_failed, label %fail, label %make_list_node

make_list_node:
  %list_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %param,
    i64 %list_head,
    i64 0,
    i64 0,
    i64 0
  )
  %list_failed = icmp slt i64 %list_node, 0
  br i1 %list_failed, label %fail, label %after_param

after_param:
  %count_next = add i64 %count, 1
  br label %loop

finish:
  call void @weave_parser_advance(ptr %parser)
  %wrapper = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %list_head,
    i64 -1,
    i64 %count,
    i64 0,
    i64 0
  )
  ret i64 %wrapper

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_call_or_binary
;
; Parse parenthesized WIR expression forms.
;
; Returns AST node index or -1 on failure.
; ----------------------------------------------------------------------------

define i64 @weave_parse_call_or_binary(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %read_head

read_head:
  %head_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %op = call i32 @weave_parser_binary_operator(i32 %head_kind)
  %is_operator = icmp ne i32 %op, 0
  br i1 %is_operator, label %parse_binary, label %check_const_i32

parse_binary:
  call void @weave_parser_advance(ptr %parser)
  %lhs = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %lhs_failed = icmp slt i64 %lhs, 0
  br i1 %lhs_failed, label %fail, label %binary_rhs

binary_rhs:
  %rhs = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %rhs_failed = icmp slt i64 %rhs, 0
  br i1 %rhs_failed, label %fail, label %binary_close

binary_close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_binary

make_binary:
  %op_wide = zext i32 %op to i64
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 10,
    i64 %op_wide,
    i64 %lhs,
    i64 %rhs,
    i64 0,
    i64 0
  )
  ret i64 %node

check_const_i32:
  %is_const_i32 = icmp eq i32 %head_kind, 31
  br i1 %is_const_i32, label %parse_const_i32, label %check_const_bool

check_const_bool:
  %is_const_bool = icmp eq i32 %head_kind, 49
  br i1 %is_const_bool, label %parse_const_bool, label %check_const_null

check_const_null:
  %is_const_null = icmp eq i32 %head_kind, 54
  br i1 %is_const_null, label %parse_const_null, label %check_const_i64

check_const_i64:
  %is_const_i64 = icmp eq i32 %head_kind, 38
  br i1 %is_const_i64, label %parse_const_i64, label %check_const_string

check_const_string:
  %is_plain_const_string = icmp eq i32 %head_kind, 41
  %is_const_string_ptr = icmp eq i32 %head_kind, 83
  %is_const_string = or i1 %is_plain_const_string, %is_const_string_ptr
  br i1 %is_const_string, label %parse_const_string, label %check_param_get

check_param_get:
  %is_param_get = icmp eq i32 %head_kind, 33
  br i1 %is_param_get, label %parse_param_get, label %check_call_i32

check_call_i32:
  %is_call_i32 = icmp eq i32 %head_kind, 34
  br i1 %is_call_i32, label %parse_call_i32, label %check_call_bool

check_call_bool:
  %is_call_bool = icmp eq i32 %head_kind, 73
  br i1 %is_call_bool, label %parse_call_bool, label %check_call_i64

check_call_i64:
  %is_call_i64 = icmp eq i32 %head_kind, 67
  br i1 %is_call_i64, label %parse_call_i64, label %check_call_ptr

check_call_ptr:
  %is_call_ptr = icmp eq i32 %head_kind, 60
  br i1 %is_call_ptr, label %parse_call_ptr, label %check_call_void

check_call_void:
  %is_call_void = icmp eq i32 %head_kind, 61
  br i1 %is_call_void, label %parse_call_void, label %check_ptr_add

check_ptr_add:
  %is_ptr_add = icmp eq i32 %head_kind, 62
  br i1 %is_ptr_add, label %parse_ptr_add, label %check_load_i64

check_load_i64:
  %is_load_i64 = icmp eq i32 %head_kind, 63
  br i1 %is_load_i64, label %parse_load_i64, label %check_load_i32

check_load_i32:
  %is_load_i32 = icmp eq i32 %head_kind, 80
  br i1 %is_load_i32, label %parse_load_i32, label %check_load_ptr

check_load_ptr:
  %is_load_ptr = icmp eq i32 %head_kind, 70
  br i1 %is_load_ptr, label %parse_load_ptr, label %check_load_u8

check_load_u8:
  %is_load_u8 = icmp eq i32 %head_kind, 65
  br i1 %is_load_u8, label %parse_load_u8, label %check_local_get

check_local_get:
  %is_local_get = icmp eq i32 %head_kind, 35
  br i1 %is_local_get, label %parse_local_get, label %check_then

check_then:
  %is_then = icmp eq i32 %head_kind, 36
  br i1 %is_then, label %parse_then, label %check_lt_i32

check_lt_i32:
  %is_lt_i32 = icmp eq i32 %head_kind, 37
  br i1 %is_lt_i32, label %parse_lt_i32, label %check_cast_i64_to_i32

check_cast_i64_to_i32:
  %is_cast_i64_to_i32 = icmp eq i32 %head_kind, 40
  br i1 %is_cast_i64_to_i32, label %parse_cast_i64_to_i32, label %check_cast_i32_to_i64

check_cast_i32_to_i64:
  %is_cast_i32_to_i64 = icmp eq i32 %head_kind, 82
  br i1 %is_cast_i32_to_i64, label %parse_cast_i32_to_i64, label %check_add_i64

check_add_i64:
  %is_add_i64 = icmp eq i32 %head_kind, 42
  br i1 %is_add_i64, label %parse_add_i64, label %check_mul_i64

check_mul_i64:
  %is_mul_i64 = icmp eq i32 %head_kind, 43
  br i1 %is_mul_i64, label %parse_mul_i64, label %check_lt_i64

check_lt_i64:
  %is_lt_i64 = icmp eq i32 %head_kind, 46
  br i1 %is_lt_i64, label %parse_lt_i64, label %check_le_i64

check_le_i64:
  %is_le_i64 = icmp eq i32 %head_kind, 47
  br i1 %is_le_i64, label %parse_le_i64, label %check_ne_i64

check_ne_i64:
  %is_ne_i64 = icmp eq i32 %head_kind, 48
  br i1 %is_ne_i64, label %parse_ne_i64, label %check_and_bool

check_and_bool:
  %is_and_bool = icmp eq i32 %head_kind, 52
  br i1 %is_and_bool, label %parse_and_bool, label %check_or_bool

check_or_bool:
  %is_or_bool = icmp eq i32 %head_kind, 53
  br i1 %is_or_bool, label %parse_or_bool, label %check_not_bool

check_not_bool:
  %is_not_bool = icmp eq i32 %head_kind, 86
  br i1 %is_not_bool, label %parse_not_bool, label %check_eq_ptr

check_eq_ptr:
  %is_eq_ptr = icmp eq i32 %head_kind, 55
  br i1 %is_eq_ptr, label %parse_eq_ptr, label %check_ne_ptr

check_ne_ptr:
  %is_ne_ptr = icmp eq i32 %head_kind, 56
  br i1 %is_ne_ptr, label %parse_ne_ptr, label %check_print

check_print:
  %is_print = icmp eq i32 %head_kind, 45
  br i1 %is_print, label %parse_print, label %fail

parse_const_i32:
  call void @weave_parser_advance(ptr %parser)
  %const_value_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %const_value_is_int = icmp eq i32 %const_value_kind, 4
  br i1 %const_value_is_int, label %capture_const_i32, label %fail

capture_const_i32:
  %const_value = call i32 @weave_parser_current_value(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %const_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %const_close_failed = icmp ne i32 %const_close_status, 0
  br i1 %const_close_failed, label %fail, label %make_const_i32

make_const_i32:
  %const_node = call i64 @weave_ast_make_integer_literal(ptr %ast, i32 %const_value)
  ret i64 %const_node

parse_const_bool:
  call void @weave_parser_advance(ptr %parser)
  %bool_value_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %bool_is_true = icmp eq i32 %bool_value_kind, 50
  br i1 %bool_is_true, label %capture_bool_true, label %check_bool_false

check_bool_false:
  %bool_is_false = icmp eq i32 %bool_value_kind, 51
  br i1 %bool_is_false, label %capture_bool_false, label %fail

capture_bool_true:
  call void @weave_parser_advance(ptr %parser)
  %true_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %true_close_failed = icmp ne i32 %true_close_status, 0
  br i1 %true_close_failed, label %fail, label %make_bool_true

make_bool_true:
  %true_node = call i64 @weave_ast_make_integer_literal(ptr %ast, i32 1)
  ret i64 %true_node

capture_bool_false:
  call void @weave_parser_advance(ptr %parser)
  %false_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %false_close_failed = icmp ne i32 %false_close_status, 0
  br i1 %false_close_failed, label %fail, label %make_bool_false

make_bool_false:
  %false_node = call i64 @weave_ast_make_integer_literal(ptr %ast, i32 0)
  ret i64 %false_node

parse_const_null:
  call void @weave_parser_advance(ptr %parser)
  %null_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %null_close_failed = icmp ne i32 %null_close_status, 0
  br i1 %null_close_failed, label %fail, label %make_null

make_null:
  %null_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 16,
    i64 0,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %null_node

parse_const_i64:
  call void @weave_parser_advance(ptr %parser)
  %const64_value_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %const64_value_is_int = icmp eq i32 %const64_value_kind, 4
  br i1 %const64_value_is_int, label %capture_const_i64, label %fail

capture_const_i64:
  %const64_value = call i32 @weave_parser_current_value(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %const64_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %const64_close_failed = icmp ne i32 %const64_close_status, 0
  br i1 %const64_close_failed, label %fail, label %make_const_i64

make_const_i64:
  %const64_node = call i64 @weave_ast_make_integer_literal(ptr %ast, i32 %const64_value)
  ret i64 %const64_node

parse_const_string:
  call void @weave_parser_advance(ptr %parser)
  %string_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %string_is_string = icmp eq i32 %string_kind, 5
  br i1 %string_is_string, label %capture_const_string, label %fail

capture_const_string:
  %string_start = call i64 @weave_parser_current_start(ptr %parser)
  %string_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %const_string_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %const_string_close_failed = icmp ne i32 %const_string_close_status, 0
  br i1 %const_string_close_failed, label %fail, label %make_const_string

make_const_string:
  %string_node = call i64 @weave_ast_make_string_literal(ptr %ast, i64 %string_start, i64 %string_len)
  ret i64 %string_node

parse_not_bool:
  call void @weave_parser_advance(ptr %parser)
  %not_expr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %not_expr_failed = icmp slt i64 %not_expr, 0
  br i1 %not_expr_failed, label %fail, label %not_close

not_close:
  %not_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %not_close_failed = icmp ne i32 %not_close_status, 0
  br i1 %not_close_failed, label %fail, label %make_not

make_not:
  %not_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 35,
    i64 %not_expr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %not_node

parse_param_get:
  call void @weave_parser_advance(ptr %parser)
  %param_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %param_name_is_ident = icmp eq i32 %param_name_kind, 3
  br i1 %param_name_is_ident, label %capture_param_get, label %fail

capture_param_get:
  %param_name_start = call i64 @weave_parser_current_start(ptr %parser)
  %param_name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %param_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %param_close_failed = icmp ne i32 %param_close_status, 0
  br i1 %param_close_failed, label %fail, label %make_param_get

make_param_get:
  %param_node = call i64 @weave_ast_make_name_expr(
    ptr %ast,
    i64 %param_name_start,
    i64 %param_name_len
  )
  ret i64 %param_node

parse_call_i32:
  call void @weave_parser_advance(ptr %parser)
  %call_i32_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %call_i32_name_is_ident = icmp eq i32 %call_i32_name_kind, 3
  br i1 %call_i32_name_is_ident, label %capture_call_i32_name, label %fail

capture_call_i32_name:
  %call_i32_name_start = call i64 @weave_parser_current_start(ptr %parser)
  %call_i32_name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %call_i32_args = call i64 @weave_parse_arg_list(ptr %parser, ptr %ast)
  %call_i32_args_failed = icmp slt i64 %call_i32_args, 0
  br i1 %call_i32_args_failed, label %fail, label %call_i32_close

call_i32_close:
  %call_i32_arg_count = call i64 @weave_ast_c(ptr %ast, i64 %call_i32_args)
  %call_i32_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_i32_close_failed = icmp ne i32 %call_i32_close_status, 0
  br i1 %call_i32_close_failed, label %fail, label %make_call_i32

make_call_i32:
  %call_i32_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 9,
    i64 %call_i32_args,
    i64 -1,
    i64 %call_i32_arg_count,
    i64 %call_i32_name_start,
    i64 %call_i32_name_len
  )
  ret i64 %call_i32_node

parse_call_bool:
  call void @weave_parser_advance(ptr %parser)
  %call_bool_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %call_bool_name_is_ident = icmp eq i32 %call_bool_name_kind, 3
  br i1 %call_bool_name_is_ident, label %capture_call_bool_name, label %fail

capture_call_bool_name:
  %call_bool_name_start = call i64 @weave_parser_current_start(ptr %parser)
  %call_bool_name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %call_bool_args = call i64 @weave_parse_arg_list(ptr %parser, ptr %ast)
  %call_bool_args_failed = icmp slt i64 %call_bool_args, 0
  br i1 %call_bool_args_failed, label %fail, label %call_bool_close

call_bool_close:
  %call_bool_arg_count = call i64 @weave_ast_c(ptr %ast, i64 %call_bool_args)
  %call_bool_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_bool_close_failed = icmp ne i32 %call_bool_close_status, 0
  br i1 %call_bool_close_failed, label %fail, label %make_call_bool

make_call_bool:
  %call_bool_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 31,
    i64 %call_bool_args,
    i64 -1,
    i64 %call_bool_arg_count,
    i64 %call_bool_name_start,
    i64 %call_bool_name_len
  )
  ret i64 %call_bool_node

parse_call_i64:
  call void @weave_parser_advance(ptr %parser)
  %call_i64_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %call_i64_name_is_ident = icmp eq i32 %call_i64_name_kind, 3
  br i1 %call_i64_name_is_ident, label %capture_call_i64_name, label %fail

capture_call_i64_name:
  %call_i64_name_start = call i64 @weave_parser_current_start(ptr %parser)
  %call_i64_name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %call_i64_args = call i64 @weave_parse_arg_list(ptr %parser, ptr %ast)
  %call_i64_args_failed = icmp slt i64 %call_i64_args, 0
  br i1 %call_i64_args_failed, label %fail, label %call_i64_close

call_i64_close:
  %call_i64_arg_count = call i64 @weave_ast_c(ptr %ast, i64 %call_i64_args)
  %call_i64_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_i64_close_failed = icmp ne i32 %call_i64_close_status, 0
  br i1 %call_i64_close_failed, label %fail, label %make_call_i64

make_call_i64:
  %call_i64_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 26,
    i64 %call_i64_args,
    i64 -1,
    i64 %call_i64_arg_count,
    i64 %call_i64_name_start,
    i64 %call_i64_name_len
  )
  ret i64 %call_i64_node

parse_call_ptr:
  call void @weave_parser_advance(ptr %parser)
  %call_ptr_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %call_ptr_name_is_ident = icmp eq i32 %call_ptr_name_kind, 3
  br i1 %call_ptr_name_is_ident, label %capture_call_ptr_name, label %fail

capture_call_ptr_name:
  %call_ptr_name_start = call i64 @weave_parser_current_start(ptr %parser)
  %call_ptr_name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %call_ptr_args = call i64 @weave_parse_arg_list(ptr %parser, ptr %ast)
  %call_ptr_args_failed = icmp slt i64 %call_ptr_args, 0
  br i1 %call_ptr_args_failed, label %fail, label %call_ptr_close

call_ptr_close:
  %call_ptr_arg_count = call i64 @weave_ast_c(ptr %ast, i64 %call_ptr_args)
  %call_ptr_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_ptr_close_failed = icmp ne i32 %call_ptr_close_status, 0
  br i1 %call_ptr_close_failed, label %fail, label %make_call_ptr

make_call_ptr:
  %call_ptr_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 18,
    i64 %call_ptr_args,
    i64 -1,
    i64 %call_ptr_arg_count,
    i64 %call_ptr_name_start,
    i64 %call_ptr_name_len
  )
  ret i64 %call_ptr_node

parse_call_void:
  call void @weave_parser_advance(ptr %parser)
  %call_void_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %call_void_name_is_ident = icmp eq i32 %call_void_name_kind, 3
  br i1 %call_void_name_is_ident, label %capture_call_void_name, label %fail

capture_call_void_name:
  %call_void_name_start = call i64 @weave_parser_current_start(ptr %parser)
  %call_void_name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %call_void_args = call i64 @weave_parse_arg_list(ptr %parser, ptr %ast)
  %call_void_args_failed = icmp slt i64 %call_void_args, 0
  br i1 %call_void_args_failed, label %fail, label %call_void_close

call_void_close:
  %call_void_arg_count = call i64 @weave_ast_c(ptr %ast, i64 %call_void_args)
  %call_void_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_void_close_failed = icmp ne i32 %call_void_close_status, 0
  br i1 %call_void_close_failed, label %fail, label %make_call_void

make_call_void:
  %call_void_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 19,
    i64 %call_void_args,
    i64 -1,
    i64 %call_void_arg_count,
    i64 %call_void_name_start,
    i64 %call_void_name_len
  )
  ret i64 %call_void_node

parse_ptr_add:
  call void @weave_parser_advance(ptr %parser)
  %ptr_add_base = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %ptr_add_base_failed = icmp slt i64 %ptr_add_base, 0
  br i1 %ptr_add_base_failed, label %fail, label %ptr_add_offset

ptr_add_offset:
  %ptr_add_offset_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %ptr_add_offset_failed = icmp slt i64 %ptr_add_offset_node, 0
  br i1 %ptr_add_offset_failed, label %fail, label %ptr_add_close

ptr_add_close:
  %ptr_add_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %ptr_add_close_failed = icmp ne i32 %ptr_add_close_status, 0
  br i1 %ptr_add_close_failed, label %fail, label %make_ptr_add

make_ptr_add:
  %ptr_add_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 21,
    i64 %ptr_add_base,
    i64 %ptr_add_offset_node,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %ptr_add_node

parse_load_i64:
  call void @weave_parser_advance(ptr %parser)
  %load_i64_ptr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %load_i64_ptr_failed = icmp slt i64 %load_i64_ptr, 0
  br i1 %load_i64_ptr_failed, label %fail, label %load_i64_close

load_i64_close:
  %load_i64_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %load_i64_close_failed = icmp ne i32 %load_i64_close_status, 0
  br i1 %load_i64_close_failed, label %fail, label %make_load_i64

make_load_i64:
  %load_i64_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 22,
    i64 %load_i64_ptr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %load_i64_node

parse_load_i32:
  call void @weave_parser_advance(ptr %parser)
  %load_i32_ptr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %load_i32_ptr_failed = icmp slt i64 %load_i32_ptr, 0
  br i1 %load_i32_ptr_failed, label %fail, label %load_i32_close

load_i32_close:
  %load_i32_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %load_i32_close_failed = icmp ne i32 %load_i32_close_status, 0
  br i1 %load_i32_close_failed, label %fail, label %make_load_i32

make_load_i32:
  %load_i32_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 32,
    i64 %load_i32_ptr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %load_i32_node

parse_load_ptr:
  call void @weave_parser_advance(ptr %parser)
  %load_ptr_ptr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %load_ptr_ptr_failed = icmp slt i64 %load_ptr_ptr, 0
  br i1 %load_ptr_ptr_failed, label %fail, label %load_ptr_close

load_ptr_close:
  %load_ptr_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %load_ptr_close_failed = icmp ne i32 %load_ptr_close_status, 0
  br i1 %load_ptr_close_failed, label %fail, label %make_load_ptr

make_load_ptr:
  %load_ptr_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 28,
    i64 %load_ptr_ptr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %load_ptr_node

parse_load_u8:
  call void @weave_parser_advance(ptr %parser)
  %load_u8_ptr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %load_u8_ptr_failed = icmp slt i64 %load_u8_ptr, 0
  br i1 %load_u8_ptr_failed, label %fail, label %load_u8_close

load_u8_close:
  %load_u8_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %load_u8_close_failed = icmp ne i32 %load_u8_close_status, 0
  br i1 %load_u8_close_failed, label %fail, label %make_load_u8

make_load_u8:
  %load_u8_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 24,
    i64 %load_u8_ptr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %load_u8_node

parse_local_get:
  call void @weave_parser_advance(ptr %parser)
  %local_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %local_name_is_ident = icmp eq i32 %local_name_kind, 3
  br i1 %local_name_is_ident, label %capture_local_get, label %fail

capture_local_get:
  %local_name_start = call i64 @weave_parser_current_start(ptr %parser)
  %local_name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %local_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %local_close_failed = icmp ne i32 %local_close_status, 0
  br i1 %local_close_failed, label %fail, label %make_local_get

make_local_get:
  %local_node = call i64 @weave_ast_make_name_expr(
    ptr %ast,
    i64 %local_name_start,
    i64 %local_name_len
  )
  ret i64 %local_node

parse_then:
  call void @weave_parser_advance(ptr %parser)
  %then_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %then_open_failed = icmp ne i32 %then_open_status, 0
  br i1 %then_open_failed, label %fail, label %then_stmt

then_stmt:
  %then_stmt_node = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %then_stmt_failed = icmp slt i64 %then_stmt_node, 0
  br i1 %then_stmt_failed, label %fail, label %then_close

then_close:
  %then_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %then_close_failed = icmp ne i32 %then_close_status, 0
  br i1 %then_close_failed, label %fail, label %make_then

make_then:
  ret i64 %then_stmt_node

parse_lt_i32:
  call void @weave_parser_advance(ptr %parser)
  %lt_lhs = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %lt_lhs_failed = icmp slt i64 %lt_lhs, 0
  br i1 %lt_lhs_failed, label %fail, label %lt_rhs

lt_rhs:
  %lt_rhs_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %lt_rhs_failed = icmp slt i64 %lt_rhs_node, 0
  br i1 %lt_rhs_failed, label %fail, label %lt_close

lt_close:
  %lt_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %lt_close_failed = icmp ne i32 %lt_close_status, 0
  br i1 %lt_close_failed, label %fail, label %make_lt

make_lt:
  %lt_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 10,
    i64 7,
    i64 %lt_lhs,
    i64 %lt_rhs_node,
    i64 0,
    i64 0
  )
  ret i64 %lt_node

parse_cast_i64_to_i32:
  call void @weave_parser_advance(ptr %parser)
  %cast_expr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %cast_expr_failed = icmp slt i64 %cast_expr, 0
  br i1 %cast_expr_failed, label %fail, label %cast_close

cast_close:
  %cast_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %cast_close_failed = icmp ne i32 %cast_close_status, 0
  br i1 %cast_close_failed, label %fail, label %cast_return

cast_return:
  %cast_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 15,
    i64 %cast_expr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %cast_node

parse_cast_i32_to_i64:
  call void @weave_parser_advance(ptr %parser)
  %cast32_expr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %cast32_expr_failed = icmp slt i64 %cast32_expr, 0
  br i1 %cast32_expr_failed, label %fail, label %cast32_close

cast32_close:
  %cast32_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %cast32_close_failed = icmp ne i32 %cast32_close_status, 0
  br i1 %cast32_close_failed, label %fail, label %cast32_return

cast32_return:
  %cast32_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 34,
    i64 %cast32_expr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %cast32_node

parse_add_i64:
  call void @weave_parser_advance(ptr %parser)
  %add64_lhs = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %add64_lhs_failed = icmp slt i64 %add64_lhs, 0
  br i1 %add64_lhs_failed, label %fail, label %add64_rhs

add64_rhs:
  %add64_rhs_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %add64_rhs_failed = icmp slt i64 %add64_rhs_node, 0
  br i1 %add64_rhs_failed, label %fail, label %add64_close

add64_close:
  %add64_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %add64_close_failed = icmp ne i32 %add64_close_status, 0
  br i1 %add64_close_failed, label %fail, label %make_add64

make_add64:
  %add64_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 10,
    i64 11,
    i64 %add64_lhs,
    i64 %add64_rhs_node,
    i64 0,
    i64 0
  )
  ret i64 %add64_node

parse_mul_i64:
  call void @weave_parser_advance(ptr %parser)
  %mul64_lhs = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %mul64_lhs_failed = icmp slt i64 %mul64_lhs, 0
  br i1 %mul64_lhs_failed, label %fail, label %mul64_rhs

mul64_rhs:
  %mul64_rhs_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %mul64_rhs_failed = icmp slt i64 %mul64_rhs_node, 0
  br i1 %mul64_rhs_failed, label %fail, label %mul64_close

mul64_close:
  %mul64_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %mul64_close_failed = icmp ne i32 %mul64_close_status, 0
  br i1 %mul64_close_failed, label %fail, label %make_mul64

make_mul64:
  %mul64_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 10,
    i64 12,
    i64 %mul64_lhs,
    i64 %mul64_rhs_node,
    i64 0,
    i64 0
  )
  ret i64 %mul64_node

parse_lt_i64:
  br label %parse_binary

parse_le_i64:
  br label %parse_binary

parse_ne_i64:
  br label %parse_binary

parse_and_bool:
  br label %parse_binary

parse_or_bool:
  br label %parse_binary

parse_eq_ptr:
  br label %parse_binary

parse_ne_ptr:
  br label %parse_binary

parse_print:
  %print_start = call i64 @weave_parser_current_start(ptr %parser)
  %print_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)

  %print_arg = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %print_arg_failed = icmp slt i64 %print_arg, 0
  br i1 %print_arg_failed, label %fail, label %print_close

print_close:
  %print_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %print_close_failed = icmp ne i32 %print_close_status, 0
  br i1 %print_close_failed, label %fail, label %make_print

make_print:
  %print_list = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %print_arg,
    i64 -1,
    i64 0,
    i64 0,
    i64 0
  )
  %print_wrapper = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %print_list,
    i64 -1,
    i64 1,
    i64 0,
    i64 0
  )
  %print_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 9,
    i64 %print_wrapper,
    i64 -1,
    i64 1,
    i64 %print_start,
    i64 %print_len
  )
  ret i64 %print_node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_expr
;
; Parse an expression.
; ----------------------------------------------------------------------------

define i64 @weave_parse_expr(ptr %parser, ptr %ast) {
entry:
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_lparen = icmp eq i32 %kind, 1
  br i1 %is_lparen, label %compound, label %atom

compound:
  %compound_node = call i64 @weave_parse_call_or_binary(ptr %parser, ptr %ast)
  ret i64 %compound_node

atom:
  %atom_node = call i64 @weave_parse_atom(ptr %parser, ptr %ast)
  ret i64 %atom_node
}

; ----------------------------------------------------------------------------
; weave_parse_return_stmt
;
; Parse:
;   (return expr)
; ----------------------------------------------------------------------------

define i64 @weave_parse_return_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_return

expect_return:
  %return_status = call i32 @weave_parser_expect(ptr %parser, i32 7)
  %return_failed = icmp ne i32 %return_status, 0
  br i1 %return_failed, label %fail, label %parse_value

parse_value:
  %expr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %expr_failed = icmp slt i64 %expr, 0
  br i1 %expr_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 4,
    i64 %expr,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_return_void_stmt
;
; Parse:
;   (return_void)
; ----------------------------------------------------------------------------

define i64 @weave_parse_return_void_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_return_void

expect_return_void:
  %return_status = call i32 @weave_parser_expect(ptr %parser, i32 68)
  %return_failed = icmp ne i32 %return_status, 0
  br i1 %return_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 27,
    i64 0,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_let_stmt
;
; Parse:
;   (let name i32 expr)
;
; The AST records the initializer expression, the local type token kind, and
; the local name.
; ----------------------------------------------------------------------------

define i64 @weave_parse_let_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_let

expect_let:
  %let_status = call i32 @weave_parser_expect(ptr %parser, i32 11)
  %let_failed = icmp ne i32 %let_status, 0
  br i1 %let_failed, label %fail, label %read_name

read_name:
  %name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_ident = icmp eq i32 %name_kind, 3
  br i1 %is_ident, label %capture_name, label %fail

capture_name:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %type_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_i32 = icmp eq i32 %type_kind, 32
  %is_i64 = icmp eq i32 %type_kind, 39
  %is_ptr = icmp eq i32 %type_kind, 58
  %is_bool = icmp eq i32 %type_kind, 72
  %valid_int_type = or i1 %is_i32, %is_i64
  %valid_ptr_type = or i1 %valid_int_type, %is_ptr
  %valid_type = or i1 %valid_ptr_type, %is_bool
  br i1 %valid_type, label %consume_type, label %fail

consume_type:
  call void @weave_parser_advance(ptr %parser)
  br label %parse_expr

parse_expr:
  %let_type_kind = sext i32 %type_kind to i64
  %expr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %expr_failed = icmp slt i64 %expr, 0
  br i1 %expr_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 7,
    i64 %expr,
    i64 %let_type_kind,
    i64 0,
    i64 %name_start,
    i64 %name_len
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_set_stmt
;
; Parse:
;   (set name expr)
; ----------------------------------------------------------------------------

define i64 @weave_parse_set_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_set

expect_set:
  %set_status = call i32 @weave_parser_expect(ptr %parser, i32 12)
  %set_failed = icmp ne i32 %set_status, 0
  br i1 %set_failed, label %fail, label %read_name

read_name:
  %name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_ident = icmp eq i32 %name_kind, 3
  br i1 %is_ident, label %capture_name, label %fail

capture_name:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %expr = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %expr_failed = icmp slt i64 %expr, 0
  br i1 %expr_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 8,
    i64 %expr,
    i64 0,
    i64 0,
    i64 %name_start,
    i64 %name_len
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_store_i64_stmt
;
; Parse:
;   (store_i64 ptr-expr value-expr)
; ----------------------------------------------------------------------------

define i64 @weave_parse_store_i64_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_store

expect_store:
  %store_status = call i32 @weave_parser_expect(ptr %parser, i32 64)
  %store_failed = icmp ne i32 %store_status, 0
  br i1 %store_failed, label %fail, label %parse_ptr

parse_ptr:
  %ptr_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %ptr_failed = icmp slt i64 %ptr_node, 0
  br i1 %ptr_failed, label %fail, label %parse_value

parse_value:
  %value_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %value_failed = icmp slt i64 %value_node, 0
  br i1 %value_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 23,
    i64 %ptr_node,
    i64 %value_node,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

define i64 @weave_parse_store_i32_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_store

expect_store:
  %store_status = call i32 @weave_parser_expect(ptr %parser, i32 81)
  %store_failed = icmp ne i32 %store_status, 0
  br i1 %store_failed, label %fail, label %parse_ptr

parse_ptr:
  %ptr_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %ptr_failed = icmp slt i64 %ptr_node, 0
  br i1 %ptr_failed, label %fail, label %parse_value

parse_value:
  %value_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %value_failed = icmp slt i64 %value_node, 0
  br i1 %value_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 33,
    i64 %ptr_node,
    i64 %value_node,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_store_i8_stmt
;
; Parse:
;   (store_i8 ptr-expr value-expr)
; ----------------------------------------------------------------------------

define i64 @weave_parse_store_i8_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_store

expect_store:
  %store_status = call i32 @weave_parser_expect(ptr %parser, i32 66)
  %store_failed = icmp ne i32 %store_status, 0
  br i1 %store_failed, label %fail, label %parse_ptr

parse_ptr:
  %ptr_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %ptr_failed = icmp slt i64 %ptr_node, 0
  br i1 %ptr_failed, label %fail, label %parse_value

parse_value:
  %value_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %value_failed = icmp slt i64 %value_node, 0
  br i1 %value_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 25,
    i64 %ptr_node,
    i64 %value_node,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_store_ptr_stmt
;
; Parse:
;   (store_ptr ptr-expr value-expr)
; ----------------------------------------------------------------------------

define i64 @weave_parse_store_ptr_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_store

expect_store:
  %store_status = call i32 @weave_parser_expect(ptr %parser, i32 71)
  %store_failed = icmp ne i32 %store_status, 0
  br i1 %store_failed, label %fail, label %parse_ptr

parse_ptr:
  %ptr_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %ptr_failed = icmp slt i64 %ptr_node, 0
  br i1 %ptr_failed, label %fail, label %parse_value

parse_value:
  %value_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %value_failed = icmp slt i64 %value_node, 0
  br i1 %value_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 29,
    i64 %ptr_node,
    i64 %value_node,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_if_stmt
;
; Parse:
;   (if cond (then stmt) (else stmt))
;
; Both branches are single statements in Stage 0.
; ----------------------------------------------------------------------------

define i64 @weave_parse_if_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_if

expect_if:
  %if_status = call i32 @weave_parser_expect(ptr %parser, i32 8)
  %if_failed = icmp ne i32 %if_status, 0
  br i1 %if_failed, label %fail, label %condition

condition:
  %cond = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %cond_failed = icmp slt i64 %cond, 0
  br i1 %cond_failed, label %fail, label %then_branch

then_branch:
  %then_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %then_is_lparen = icmp eq i32 %then_kind, 1
  br i1 %then_is_lparen, label %then_wrapper, label %then_direct

then_wrapper:
  %then_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %then_open_failed = icmp ne i32 %then_open_status, 0
  br i1 %then_open_failed, label %fail, label %then_head

then_head:
  %then_head_status = call i32 @weave_parser_expect(ptr %parser, i32 36)
  %then_head_failed = icmp ne i32 %then_head_status, 0
  br i1 %then_head_failed, label %fail, label %then_stmt_wrapped

then_stmt_wrapped:
  %then_stmt_node = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %then_stmt_failed = icmp slt i64 %then_stmt_node, 0
  br i1 %then_stmt_failed, label %fail, label %then_close

then_close:
  %then_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %then_close_failed = icmp ne i32 %then_close_status, 0
  br i1 %then_close_failed, label %fail, label %then_merge

then_direct:
  %then_stmt_direct = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %then_direct_failed = icmp slt i64 %then_stmt_direct, 0
  br i1 %then_direct_failed, label %fail, label %then_merge

then_merge:
  %then_node_merged = phi i64 [%then_stmt_node, %then_close], [%then_stmt_direct, %then_direct]
  %else_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %else_is_lparen = icmp eq i32 %else_kind, 1
  br i1 %else_is_lparen, label %else_wrapper, label %else_direct

else_wrapper:
  %else_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %else_open_failed = icmp ne i32 %else_open_status, 0
  br i1 %else_open_failed, label %fail, label %else_head

else_head:
  %else_head_status = call i32 @weave_parser_expect(ptr %parser, i32 9)
  %else_head_failed = icmp ne i32 %else_head_status, 0
  br i1 %else_head_failed, label %fail, label %else_stmt_wrapped

else_stmt_wrapped:
  %else_stmt_node = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %else_stmt_failed = icmp slt i64 %else_stmt_node, 0
  br i1 %else_stmt_failed, label %fail, label %else_close

else_close:
  %else_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %else_close_failed = icmp ne i32 %else_close_status, 0
  br i1 %else_close_failed, label %fail, label %close

else_direct:
  %else_stmt_direct = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %else_direct_failed = icmp slt i64 %else_stmt_direct, 0
  br i1 %else_direct_failed, label %fail, label %close

close:
  %else_node_merged = phi i64 [%else_stmt_node, %else_close], [%else_stmt_direct, %else_direct]
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 5,
    i64 %cond,
    i64 %then_node_merged,
    i64 %else_node_merged,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_while_stmt
;
; Parse:
;   (while cond (body stmt))
;
; Body is one statement in Stage 0. Use a block when multiple statements are
; needed.
; ----------------------------------------------------------------------------

define i64 @weave_parse_while_stmt(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_while

expect_while:
  %while_status = call i32 @weave_parser_expect(ptr %parser, i32 10)
  %while_failed = icmp ne i32 %while_status, 0
  br i1 %while_failed, label %fail, label %condition

condition:
  %cond = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %cond_failed = icmp slt i64 %cond, 0
  br i1 %cond_failed, label %fail, label %body_branch

body_branch:
  %body_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %body_is_lparen = icmp eq i32 %body_kind, 1
  br i1 %body_is_lparen, label %body_wrapper, label %body_direct

body_wrapper:
  %body_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %body_open_failed = icmp ne i32 %body_open_status, 0
  br i1 %body_open_failed, label %fail, label %body_head

body_head:
  %body_head_status = call i32 @weave_parser_expect(ptr %parser, i32 30)
  %body_head_failed = icmp ne i32 %body_head_status, 0
  br i1 %body_head_failed, label %fail, label %body_stmt_wrapped

body_stmt_wrapped:
  %body_node_wrapped = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %body_wrapped_failed = icmp slt i64 %body_node_wrapped, 0
  br i1 %body_wrapped_failed, label %fail, label %body_close

body_close:
  %body_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %body_close_failed = icmp ne i32 %body_close_status, 0
  br i1 %body_close_failed, label %fail, label %body_merge

body_direct:
  %body_node_direct = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %body_direct_failed = icmp slt i64 %body_node_direct, 0
  br i1 %body_direct_failed, label %fail, label %body_merge

body_merge:
  %body_node = phi i64 [%body_node_wrapped, %body_close], [%body_node_direct, %body_direct]
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 6,
    i64 %cond,
    i64 %body_node,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_stmt
;
; Dispatch a parenthesized statement.
; ----------------------------------------------------------------------------

define i64 @weave_parse_stmt(ptr %parser, ptr %ast) {
entry:
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_lparen = icmp eq i32 %kind, 1
  br i1 %is_lparen, label %lookahead, label %fail

lookahead:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %head_index = add i64 %index, 1
  %head_kind = call i32 @weave_token_kind(ptr %tokens, i64 %head_index)

  %is_return = icmp eq i32 %head_kind, 7
  br i1 %is_return, label %return_stmt, label %check_if

check_if:
  %is_if = icmp eq i32 %head_kind, 8
  br i1 %is_if, label %if_stmt, label %check_return_void

check_return_void:
  %is_return_void = icmp eq i32 %head_kind, 68
  br i1 %is_return_void, label %return_void_stmt, label %check_while

check_while:
  %is_while = icmp eq i32 %head_kind, 10
  br i1 %is_while, label %while_stmt, label %check_let

check_let:
  %is_let = icmp eq i32 %head_kind, 11
  br i1 %is_let, label %let_stmt, label %check_set

check_set:
  %is_set = icmp eq i32 %head_kind, 12
  br i1 %is_set, label %set_stmt, label %check_store_i64

check_store_i64:
  %is_store_i64 = icmp eq i32 %head_kind, 64
  br i1 %is_store_i64, label %store_i64_stmt, label %check_store_i32

check_store_i32:
  %is_store_i32 = icmp eq i32 %head_kind, 81
  br i1 %is_store_i32, label %store_i32_stmt, label %check_store_ptr

check_store_ptr:
  %is_store_ptr = icmp eq i32 %head_kind, 71
  br i1 %is_store_ptr, label %store_ptr_stmt, label %check_store_i8

check_store_i8:
  %is_store_i8 = icmp eq i32 %head_kind, 66
  br i1 %is_store_i8, label %store_i8_stmt, label %check_block

check_block:
  %is_block = icmp eq i32 %head_kind, 24
  br i1 %is_block, label %block_stmt, label %expr_stmt

return_stmt:
  %return_node = call i64 @weave_parse_return_stmt(ptr %parser, ptr %ast)
  ret i64 %return_node

return_void_stmt:
  %return_void_node = call i64 @weave_parse_return_void_stmt(ptr %parser, ptr %ast)
  ret i64 %return_void_node

if_stmt:
  %if_node = call i64 @weave_parse_if_stmt(ptr %parser, ptr %ast)
  ret i64 %if_node

while_stmt:
  %while_node = call i64 @weave_parse_while_stmt(ptr %parser, ptr %ast)
  ret i64 %while_node

let_stmt:
  %let_node = call i64 @weave_parse_let_stmt(ptr %parser, ptr %ast)
  ret i64 %let_node

set_stmt:
  %set_node = call i64 @weave_parse_set_stmt(ptr %parser, ptr %ast)
  ret i64 %set_node

store_i64_stmt:
  %store_i64_node = call i64 @weave_parse_store_i64_stmt(ptr %parser, ptr %ast)
  ret i64 %store_i64_node

store_i32_stmt:
  %store_i32_node = call i64 @weave_parse_store_i32_stmt(ptr %parser, ptr %ast)
  ret i64 %store_i32_node

store_ptr_stmt:
  %store_ptr_node = call i64 @weave_parse_store_ptr_stmt(ptr %parser, ptr %ast)
  ret i64 %store_ptr_node

store_i8_stmt:
  %store_i8_node = call i64 @weave_parse_store_i8_stmt(ptr %parser, ptr %ast)
  ret i64 %store_i8_node

block_stmt:
  %block_node = call i64 @weave_parse_block(ptr %parser, ptr %ast)
  ret i64 %block_node

expr_stmt:
  %expr_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %expr_failed = icmp slt i64 %expr_node, 0
  br i1 %expr_failed, label %fail, label %make_expr_stmt

make_expr_stmt:
  %stmt_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 14,
    i64 %expr_node,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )
  ret i64 %stmt_node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_block
;
; Parse:
;   (block stmt stmt ...)
;
; The compact AST representation stores a reversed statement-list chain.
; Nested expressions and statements are also appended during parse, so numeric
; AST ranges cannot represent sibling statements.
;
; AST_BLOCK:
;   a = statement-list head
;   b = -1
;   c = statement count during parse, then function return type for a body block
;
; AST_STMT_LIST:
;   a = statement node
;   b = previous statement-list node, or -1
; ----------------------------------------------------------------------------

define i64 @weave_parse_block(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %read_head

read_head:
  %head_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_block = icmp eq i32 %head_kind, 24
  br i1 %is_block, label %consume_head, label %fail

consume_head:
  call void @weave_parser_advance(ptr %parser)
  br label %loop

loop:
  %list_head = phi i64 [-1, %consume_head], [%list_node, %after_stmt]
  %count = phi i64 [0, %consume_head], [%count_next, %after_stmt]

  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_rparen = icmp eq i32 %kind, 2
  br i1 %is_rparen, label %finish, label %parse_stmt

parse_stmt:
  %stmt = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %stmt_failed = icmp slt i64 %stmt, 0
  br i1 %stmt_failed, label %fail, label %make_list_node

make_list_node:
  %list_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %stmt,
    i64 %list_head,
    i64 0,
    i64 0,
    i64 0
  )
  %list_failed = icmp slt i64 %list_node, 0
  br i1 %list_failed, label %fail, label %after_stmt

after_stmt:
  %count_next = add i64 %count, 1
  br label %loop

finish:
  call void @weave_parser_advance(ptr %parser)
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 3,
    i64 %list_head,
    i64 -1,
    i64 %count,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_wir_body
;
; Parse:
;   (body stmt stmt ...)
;
; WIR uses an explicit body wrapper. Internally Stage 0 still uses AST_BLOCK so
; the existing LLVM emitter can stay focused on one compact AST shape.
; ----------------------------------------------------------------------------

define i64 @weave_parse_wir_body(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_body

expect_body:
  %body_status = call i32 @weave_parser_expect(ptr %parser, i32 30)
  %body_failed = icmp ne i32 %body_status, 0
  br i1 %body_failed, label %fail, label %loop

loop:
  %list_head = phi i64 [-1, %expect_body], [%list_node, %after_stmt]
  %count = phi i64 [0, %expect_body], [%count_next, %after_stmt]

  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_rparen = icmp eq i32 %kind, 2
  br i1 %is_rparen, label %finish, label %parse_stmt

parse_stmt:
  %stmt = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %stmt_failed = icmp slt i64 %stmt, 0
  br i1 %stmt_failed, label %fail, label %make_list_node

make_list_node:
  %list_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 20,
    i64 %stmt,
    i64 %list_head,
    i64 0,
    i64 0,
    i64 0
  )
  %list_failed = icmp slt i64 %list_node, 0
  br i1 %list_failed, label %fail, label %after_stmt

after_stmt:
  %count_next = add i64 %count, 1
  br label %loop

finish:
  %empty = icmp eq i64 %count, 0
  br i1 %empty, label %fail, label %consume_close

consume_close:
  call void @weave_parser_advance(ptr %parser)
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 3,
    i64 %list_head,
    i64 -1,
    i64 %count,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_wir_extern
;
; Parse:
;   (extern name
;     (params (arg type))
;     (returns type))
;
; The current emitter declares the admitted C runtime functions in the module
; header, but keeping externs in the AST lets the WIR declaration list stay
; honest.
; ----------------------------------------------------------------------------

define i64 @weave_parse_wir_extern(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_extern

expect_extern:
  %extern_status = call i32 @weave_parser_expect(ptr %parser, i32 57)
  %extern_failed = icmp ne i32 %extern_status, 0
  br i1 %extern_failed, label %fail, label %read_name

read_name:
  %name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_ident = icmp eq i32 %name_kind, 3
  br i1 %is_ident, label %capture_name, label %fail

capture_name:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  br label %skip_tail

skip_tail:
  %depth = phi i64 [1, %capture_name], [%depth_next, %after_token]
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_eof = icmp eq i32 %kind, 0
  br i1 %is_eof, label %fail, label %classify_token

classify_token:
  %is_open = icmp eq i32 %kind, 1
  br i1 %is_open, label %open_token, label %check_close_token

check_close_token:
  %is_close = icmp eq i32 %kind, 2
  br i1 %is_close, label %close_token, label %plain_token

open_token:
  %depth_open = add i64 %depth, 1
  call void @weave_parser_advance(ptr %parser)
  br label %after_token

close_token:
  %depth_close = sub i64 %depth, 1
  call void @weave_parser_advance(ptr %parser)
  %done = icmp eq i64 %depth_close, 0
  br i1 %done, label %make_node, label %after_token

plain_token:
  call void @weave_parser_advance(ptr %parser)
  br label %after_token

after_token:
  %depth_next = phi i64 [%depth_open, %open_token], [%depth_close, %close_token], [%depth, %plain_token]
  br label %skip_tail

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 17,
    i64 0,
    i64 0,
    i64 0,
    i64 %name_start,
    i64 %name_len
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_wir_function
;
; Parse the WIR function shape admitted by the bootstrap ladder:
;
;   (fn name
;     (params)
;     (params (x i32))
;     (params (x i32) (y i32))
;     (returns i32)
;     (body ...))
; ----------------------------------------------------------------------------

define i64 @weave_parse_wir_function(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_fn

expect_fn:
  %fn_status = call i32 @weave_parser_expect(ptr %parser, i32 6)
  %fn_failed = icmp ne i32 %fn_status, 0
  br i1 %fn_failed, label %fail, label %read_name

read_name:
  %name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_ident = icmp eq i32 %name_kind, 3
  br i1 %is_ident, label %capture_name, label %fail

capture_name:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %param_wrapper = call i64 @weave_parse_wir_params(ptr %parser, ptr %ast)
  %params_failed = icmp slt i64 %param_wrapper, 0
  br i1 %params_failed, label %fail, label %returns_open

returns_open:
  %returns_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %returns_open_failed = icmp ne i32 %returns_open_status, 0
  br i1 %returns_open_failed, label %fail, label %returns_head

returns_head:
  %returns_status = call i32 @weave_parser_expect(ptr %parser, i32 29)
  %returns_failed = icmp ne i32 %returns_status, 0
  br i1 %returns_failed, label %fail, label %returns_type

returns_type:
  %return_type_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %return_is_i32 = icmp eq i32 %return_type_kind, 32
  %return_is_i64 = icmp eq i32 %return_type_kind, 39
  %return_is_ptr = icmp eq i32 %return_type_kind, 58
  %return_is_void = icmp eq i32 %return_type_kind, 59
  %return_is_bool = icmp eq i32 %return_type_kind, 72
  %return_int_ok = or i1 %return_is_i32, %return_is_i64
  %return_value_ok = or i1 %return_int_ok, %return_is_ptr
  %return_value_bool_ok = or i1 %return_value_ok, %return_is_bool
  %return_type_ok = or i1 %return_value_bool_ok, %return_is_void
  br i1 %return_type_ok, label %consume_return_type, label %fail

consume_return_type:
  call void @weave_parser_advance(ptr %parser)
  br label %returns_close

returns_close:
  %returns_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %returns_close_failed = icmp ne i32 %returns_close_status, 0
  br i1 %returns_close_failed, label %fail, label %parse_body

parse_body:
  %body = call i64 @weave_parse_wir_body(ptr %parser, ptr %ast)
  %body_failed = icmp slt i64 %body, 0
  br i1 %body_failed, label %fail, label %apply_body_params

apply_body_params:
  %body_node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %body)
  %body_return_type_ptr = call ptr @weave_ast_node_c_ptr(ptr %body_node)
  %return_type_wide = sext i32 %return_type_kind to i64
  store i64 %return_type_wide, ptr %body_return_type_ptr
  br label %close_function

close_function:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %param_count = call i64 @weave_ast_c(ptr %ast, i64 %param_wrapper)
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 2,
    i64 %body,
    i64 %param_wrapper,
    i64 %param_count,
    i64 %name_start,
    i64 %name_len
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_wir_module
;
; Parse:
;   (core-module
;     (core-version 1)
;     (decls ...))
; ----------------------------------------------------------------------------

define i64 @weave_parse_wir_module(ptr %parser, ptr %ast) {
entry:
  %open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %open_failed = icmp ne i32 %open_status, 0
  br i1 %open_failed, label %fail, label %expect_module

expect_module:
  %module_status = call i32 @weave_parser_expect(ptr %parser, i32 25)
  %module_failed = icmp ne i32 %module_status, 0
  br i1 %module_failed, label %fail, label %version_open

version_open:
  %version_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %version_open_failed = icmp ne i32 %version_open_status, 0
  br i1 %version_open_failed, label %fail, label %version_head

version_head:
  %version_head_status = call i32 @weave_parser_expect(ptr %parser, i32 26)
  %version_head_failed = icmp ne i32 %version_head_status, 0
  br i1 %version_head_failed, label %fail, label %version_number

version_number:
  %version_number_status = call i32 @weave_parser_expect(ptr %parser, i32 4)
  %version_number_failed = icmp ne i32 %version_number_status, 0
  br i1 %version_number_failed, label %fail, label %version_close

version_close:
  %version_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %version_close_failed = icmp ne i32 %version_close_status, 0
  br i1 %version_close_failed, label %fail, label %decls_open

decls_open:
  %decls_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %decls_open_failed = icmp ne i32 %decls_open_status, 0
  br i1 %decls_open_failed, label %fail, label %decls_head

decls_head:
  %decls_head_status = call i32 @weave_parser_expect(ptr %parser, i32 27)
  %decls_head_failed = icmp ne i32 %decls_head_status, 0
  br i1 %decls_head_failed, label %fail, label %decls_loop

decls_loop:
  %first = phi i64 [-1, %decls_head], [%first_next, %after_decl]
  %last = phi i64 [-1, %decls_head], [%decl_node, %after_decl]
  %count = phi i64 [0, %decls_head], [%count_next, %after_decl]

  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %decls_done = icmp eq i32 %kind, 2
  br i1 %decls_done, label %decls_close, label %decl_lookahead

decl_lookahead:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %head_index = add i64 %index, 1
  %head_kind = call i32 @weave_token_kind(ptr %tokens, i64 %head_index)
  %is_extern = icmp eq i32 %head_kind, 57
  br i1 %is_extern, label %parse_extern, label %parse_function

parse_extern:
  %extern_node = call i64 @weave_parse_wir_extern(ptr %parser, ptr %ast)
  %extern_failed = icmp slt i64 %extern_node, 0
  br i1 %extern_failed, label %fail, label %after_decl

parse_function:
  %function_node = call i64 @weave_parse_wir_function(ptr %parser, ptr %ast)
  %function_failed = icmp slt i64 %function_node, 0
  br i1 %function_failed, label %fail, label %after_decl

after_decl:
  %decl_node = phi i64 [%extern_node, %parse_extern], [%function_node, %parse_function]
  %count_was_zero = icmp eq i64 %count, 0
  %first_next = select i1 %count_was_zero, i64 %decl_node, i64 %first
  %count_next = add i64 %count, 1
  br label %decls_loop

decls_close:
  %empty_decls = icmp eq i64 %count, 0
  br i1 %empty_decls, label %fail, label %consume_decls_close

consume_decls_close:
  call void @weave_parser_advance(ptr %parser)
  %module_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %module_close_failed = icmp ne i32 %module_close_status, 0
  br i1 %module_close_failed, label %fail, label %expect_eof

expect_eof:
  %eof_status = call i32 @weave_parser_expect(ptr %parser, i32 0)
  %eof_failed = icmp ne i32 %eof_status, 0
  br i1 %eof_failed, label %fail, label %make_node

make_node:
  %program_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 1,
    i64 %first,
    i64 %last,
    i64 %count,
    i64 0,
    i64 0
  )
  ret i64 %program_node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_program
;
; Parse one top-level WIR module.
;
; AST_PROGRAM:
;   a = first function node index
;   b = last function node index
;   c = function count
; ----------------------------------------------------------------------------

define i64 @weave_parse_program(ptr %parser, ptr %ast) {
entry:
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_lparen = icmp eq i32 %kind, 1
  br i1 %is_lparen, label %lookahead, label %fail


lookahead:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %head_index = add i64 %index, 1
  %head_kind = call i32 @weave_token_kind(ptr %tokens, i64 %head_index)
  %is_wir_module = icmp eq i32 %head_kind, 25
  br i1 %is_wir_module, label %parse_wir_module, label %fail

parse_wir_module:
  %wir_module_node = call i64 @weave_parse_wir_module(ptr %parser, ptr %ast)
  ret i64 %wir_module_node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse
;
; Public parser entry point.
;
; Returns:
;   >= 0 : AST_PROGRAM node index
;   -1   : parse failure
; ----------------------------------------------------------------------------

define i64 @weave_parse(ptr %tokens, ptr %ast) {
entry:
  %parser_storage = alloca %weave.Parser
  call void @weave_parser_init(ptr %parser_storage, ptr %tokens)
  %program = call i64 @weave_parse_program(ptr %parser_storage, ptr %ast)
  ret i64 %program
}
