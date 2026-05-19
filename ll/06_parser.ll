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
; The parser accepts a deliberately small S-expression-like subset. It fails
; fast on unsupported input. There is no recovery, no diagnostics framework,
; no type checking, and no module system here.
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
  %is_plus = icmp eq i32 %kind, 13
  br i1 %is_plus, label %add, label %check_minus

check_minus:
  %is_minus = icmp eq i32 %kind, 14
  br i1 %is_minus, label %sub, label %check_star

check_star:
  %is_star = icmp eq i32 %kind, 15
  br i1 %is_star, label %mul, label %check_slash

check_slash:
  %is_slash = icmp eq i32 %kind, 16
  br i1 %is_slash, label %div, label %check_eqeq

check_eqeq:
  %is_eqeq = icmp eq i32 %kind, 18
  br i1 %is_eqeq, label %eq, label %check_ne

check_ne:
  %is_ne = icmp eq i32 %kind, 19
  br i1 %is_ne, label %ne, label %check_lt

check_lt:
  %is_lt = icmp eq i32 %kind, 20
  br i1 %is_lt, label %lt, label %check_le

check_le:
  %is_le = icmp eq i32 %kind, 21
  br i1 %is_le, label %le, label %check_gt

check_gt:
  %is_gt = icmp eq i32 %kind, 22
  br i1 %is_gt, label %gt, label %check_ge

check_ge:
  %is_ge = icmp eq i32 %kind, 23
  br i1 %is_ge, label %ge, label %none

add:
  ret i32 1

sub:
  ret i32 2

mul:
  ret i32 3

div:
  ret i32 4

eq:
  ret i32 5

ne:
  ret i32 6

lt:
  ret i32 7

le:
  ret i32 8

gt:
  ret i32 9

ge:
  ret i32 10

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
;   INT
;   STRING
;   IDENT
;
; Returns AST node index or -1 on failure.
; ----------------------------------------------------------------------------

define i64 @weave_parse_atom(ptr %parser, ptr %ast) {
entry:
  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_int = icmp eq i32 %kind, 4
  br i1 %is_int, label %parse_int, label %check_string

check_string:
  %is_string = icmp eq i32 %kind, 5
  br i1 %is_string, label %parse_string, label %check_ident

check_ident:
  %is_ident = icmp eq i32 %kind, 3
  br i1 %is_ident, label %parse_ident, label %fail

parse_int:
  %value = call i32 @weave_parser_current_value(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %int_node = call i64 @weave_ast_make_integer_literal(ptr %ast, i32 %value)
  ret i64 %int_node

parse_string:
  %string_start = call i64 @weave_parser_current_start(ptr %parser)
  %string_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %string_node = call i64 @weave_ast_make_string_literal(ptr %ast, i64 %string_start, i64 %string_len)
  ret i64 %string_node

parse_ident:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %name_node = call i64 @weave_ast_make_name_expr(ptr %ast, i64 %name_start, i64 %name_len)
  ret i64 %name_node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_call_or_binary
;
; Parse parenthesized expressions:
;
;   (+ a b)
;   (- a b)
;   (* a b)
;   (/ a b)
;   (== a b)
;   (!= a b)
;   (< a b)
;   (<= a b)
;   (> a b)
;   (>= a b)
;   (name arg)
;   (name arg arg)
;
; Stage 0 calls are deliberately limited to two arguments for now. This is
; enough for the curated bootstrap ladder without adding a full argument list
; representation too early.
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
  br i1 %is_const_i32, label %parse_const_i32, label %check_const_string

check_const_string:
  %is_const_string = icmp eq i32 %head_kind, 38
  br i1 %is_const_string, label %parse_const_string, label %check_param_get

check_param_get:
  %is_param_get = icmp eq i32 %head_kind, 33
  br i1 %is_param_get, label %parse_param_get, label %check_call_i32

check_call_i32:
  %is_call_i32 = icmp eq i32 %head_kind, 34
  br i1 %is_call_i32, label %parse_call_i32, label %check_local_get

check_local_get:
  %is_local_get = icmp eq i32 %head_kind, 35
  br i1 %is_local_get, label %parse_local_get, label %check_then

check_then:
  %is_then = icmp eq i32 %head_kind, 36
  br i1 %is_then, label %parse_then, label %check_lt_i32

check_lt_i32:
  %is_lt_i32 = icmp eq i32 %head_kind, 37
  br i1 %is_lt_i32, label %parse_lt_i32, label %parse_call_head

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

  %call_i32_arg = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %call_i32_arg_failed = icmp slt i64 %call_i32_arg, 0
  br i1 %call_i32_arg_failed, label %fail, label %call_i32_maybe_second_arg

call_i32_maybe_second_arg:
  %call_i32_after_arg_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %call_i32_has_second_arg = icmp ne i32 %call_i32_after_arg_kind, 2
  br i1 %call_i32_has_second_arg, label %call_i32_parse_second_arg, label %call_i32_close

call_i32_parse_second_arg:
  %call_i32_arg2 = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %call_i32_arg2_failed = icmp slt i64 %call_i32_arg2, 0
  br i1 %call_i32_arg2_failed, label %fail, label %call_i32_close

call_i32_close:
  %call_i32_arg2_value = phi i64 [-1, %call_i32_maybe_second_arg], [%call_i32_arg2, %call_i32_parse_second_arg]
  %call_i32_arg_count = phi i64 [1, %call_i32_maybe_second_arg], [2, %call_i32_parse_second_arg]
  %call_i32_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_i32_close_failed = icmp ne i32 %call_i32_close_status, 0
  br i1 %call_i32_close_failed, label %fail, label %make_call_i32

make_call_i32:
  %call_i32_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 9,
    i64 %call_i32_arg,
    i64 %call_i32_arg2_value,
    i64 %call_i32_arg_count,
    i64 %call_i32_name_start,
    i64 %call_i32_name_len
  )
  ret i64 %call_i32_node

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

parse_call_head:
  %is_ident = icmp eq i32 %head_kind, 3
  br i1 %is_ident, label %parse_call, label %fail

parse_call:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)

  %arg = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %arg_failed = icmp slt i64 %arg, 0
  br i1 %arg_failed, label %fail, label %maybe_second_arg

maybe_second_arg:
  %after_arg_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %call_has_second_arg = icmp ne i32 %after_arg_kind, 2
  br i1 %call_has_second_arg, label %parse_second_arg, label %call_close

parse_second_arg:
  %arg2 = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %arg2_failed = icmp slt i64 %arg2, 0
  br i1 %arg2_failed, label %fail, label %call_close

call_close:
  %call_arg2 = phi i64 [-1, %maybe_second_arg], [%arg2, %parse_second_arg]
  %call_arg_count = phi i64 [1, %maybe_second_arg], [2, %parse_second_arg]
  %call_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_close_failed = icmp ne i32 %call_close_status, 0
  br i1 %call_close_failed, label %fail, label %make_call

make_call:
  %call_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 9,
    i64 %arg,
    i64 %call_arg2,
    i64 %call_arg_count,
    i64 %name_start,
    i64 %name_len
  )
  ret i64 %call_node

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
; weave_parse_let_stmt
;
; Parse:
;   (let name expr)
;   (let name i32 expr)
;
; The explicit i32 annotation is accepted for WIR fixtures, but the AST still
; only records the initializer expression and the local name.
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
  %has_type = icmp eq i32 %type_kind, 32
  br i1 %has_type, label %consume_type, label %parse_expr

consume_type:
  call void @weave_parser_advance(ptr %parser)
  br label %parse_expr

parse_expr:
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
; weave_parse_if_stmt
;
; Parse:
;   (if cond then-stmt else-stmt)
;   (if cond (then stmt) (else stmt))
;
; Both branches are single statements in Stage 0. The WIR form wraps each
; branch in an explicit `then`/`else` form, which this parser accepts too.
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
;   (while cond body-stmt)
;   (while cond (body stmt))
;
; Body is one statement in Stage 0. The WIR form wraps it in an explicit
; `body` list.
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
  br i1 %is_if, label %if_stmt, label %check_while

check_while:
  %is_while = icmp eq i32 %head_kind, 10
  br i1 %is_while, label %while_stmt, label %check_let

check_let:
  %is_let = icmp eq i32 %head_kind, 11
  br i1 %is_let, label %let_stmt, label %check_set

check_set:
  %is_set = icmp eq i32 %head_kind, 12
  br i1 %is_set, label %set_stmt, label %check_block

check_block:
  %is_block = icmp eq i32 %head_kind, 24
  br i1 %is_block, label %block_stmt, label %expr_stmt

return_stmt:
  %return_node = call i64 @weave_parse_return_stmt(ptr %parser, ptr %ast)
  ret i64 %return_node

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
; The compact AST representation stores only the first and last statement node
; index. This works because Stage 0 appends nodes in parse order.
;
; AST_BLOCK:
;   a = first statement index
;   b = last statement index
;   c = statement count
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
  %first = phi i64 [-1, %consume_head], [%first_next, %after_stmt]
  %last = phi i64 [-1, %consume_head], [%stmt, %after_stmt]
  %count = phi i64 [0, %consume_head], [%count_next, %after_stmt]

  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_rparen = icmp eq i32 %kind, 2
  br i1 %is_rparen, label %finish, label %parse_stmt

parse_stmt:
  %stmt = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %stmt_failed = icmp slt i64 %stmt, 0
  br i1 %stmt_failed, label %fail, label %after_stmt

after_stmt:
  %count_was_zero = icmp eq i64 %count, 0
  %first_next = select i1 %count_was_zero, i64 %stmt, i64 %first
  %count_next = add i64 %count, 1
  br label %loop

finish:
  call void @weave_parser_advance(ptr %parser)
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 3,
    i64 %first,
    i64 %last,
    i64 %count,
    i64 0,
    i64 0
  )
  ret i64 %node

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_parse_function
;
; Parse:
;   (fn name body...)
;   (fn name param body...)
;   (fn name param param body...)
;
; Stage 0 supports up to two bare parameter names. Explicit
; return types and parameter lists are intentionally omitted for now.
;
; AST_FUNCTION:
;   a = body block node index
;   b = parameter name source start, or 0
;   c = parameter name source length, or 0
;   body block text_start/text_len = second parameter name, or 0
;   text_start/text_len = function name
; ----------------------------------------------------------------------------

define i64 @weave_parse_function(ptr %parser, ptr %ast) {
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
  %after_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %has_param = icmp eq i32 %after_name_kind, 3
  br i1 %has_param, label %capture_param, label %parse_body

capture_param:
  %param_start = call i64 @weave_parser_current_start(ptr %parser)
  %param_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %after_param_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %has_second_param = icmp eq i32 %after_param_kind, 3
  br i1 %has_second_param, label %capture_second_param, label %parse_body

capture_second_param:
  %param2_start = call i64 @weave_parser_current_start(ptr %parser)
  %param2_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  br label %parse_body

parse_body:
  %body_param_start = phi i64 [0, %capture_name], [%param_start, %capture_param], [%param_start, %capture_second_param]
  %body_param_len = phi i64 [0, %capture_name], [%param_len, %capture_param], [%param_len, %capture_second_param]
  %body_param2_start = phi i64 [0, %capture_name], [0, %capture_param], [%param2_start, %capture_second_param]
  %body_param2_len = phi i64 [0, %capture_name], [0, %capture_param], [%param2_len, %capture_second_param]
  br label %body_loop

body_loop:
  %body_first = phi i64 [-1, %parse_body], [%body_first_next, %after_body_stmt]
  %body_last = phi i64 [-1, %parse_body], [%body_stmt, %after_body_stmt]
  %body_count = phi i64 [0, %parse_body], [%body_count_next, %after_body_stmt]

  %body_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %body_done = icmp eq i32 %body_kind, 2
  br i1 %body_done, label %finish_body, label %parse_body_stmt

parse_body_stmt:
  %body_stmt = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %body_stmt_failed = icmp slt i64 %body_stmt, 0
  br i1 %body_stmt_failed, label %fail, label %after_body_stmt

after_body_stmt:
  %body_count_was_zero = icmp eq i64 %body_count, 0
  %body_first_next = select i1 %body_count_was_zero, i64 %body_stmt, i64 %body_first
  %body_count_next = add i64 %body_count, 1
  br label %body_loop

finish_body:
  %empty_body = icmp eq i64 %body_count, 0
  br i1 %empty_body, label %fail, label %consume_close

consume_close:
  call void @weave_parser_advance(ptr %parser)
  %body = call i64 @weave_ast_push(
    ptr %ast,
    i32 3,
    i64 %body_first,
    i64 %body_last,
    i64 %body_count,
    i64 %body_param2_start,
    i64 %body_param2_len
  )
  %body_failed = icmp slt i64 %body, 0
  br i1 %body_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 2,
    i64 %body,
    i64 %body_param_start,
    i64 %body_param_len,
    i64 %name_start,
    i64 %name_len
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
  %first = phi i64 [-1, %expect_body], [%first_next, %after_stmt]
  %last = phi i64 [-1, %expect_body], [%stmt, %after_stmt]
  %count = phi i64 [0, %expect_body], [%count_next, %after_stmt]

  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_rparen = icmp eq i32 %kind, 2
  br i1 %is_rparen, label %finish, label %parse_stmt

parse_stmt:
  %stmt = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %stmt_failed = icmp slt i64 %stmt, 0
  br i1 %stmt_failed, label %fail, label %after_stmt

after_stmt:
  %count_was_zero = icmp eq i64 %count, 0
  %first_next = select i1 %count_was_zero, i64 %stmt, i64 %first
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
    i64 %first,
    i64 %last,
    i64 %count,
    i64 0,
    i64 0
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
  br label %params_open

params_open:
  %params_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %params_open_failed = icmp ne i32 %params_open_status, 0
  br i1 %params_open_failed, label %fail, label %params_head

params_head:
  %params_status = call i32 @weave_parser_expect(ptr %parser, i32 28)
  %params_failed = icmp ne i32 %params_status, 0
  br i1 %params_failed, label %fail, label %params_empty_or_param1

params_empty_or_param1:
  %params_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %params_empty = icmp eq i32 %params_kind, 2
  br i1 %params_empty, label %params_close, label %parse_param1

parse_param1:
  %param1_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %param1_open_failed = icmp ne i32 %param1_open_status, 0
  br i1 %param1_open_failed, label %fail, label %param1_name

param1_name:
  %param1_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %param1_is_ident = icmp eq i32 %param1_name_kind, 3
  br i1 %param1_is_ident, label %capture_param1_name, label %fail

capture_param1_name:
  %param1_start_val = call i64 @weave_parser_current_start(ptr %parser)
  %param1_len_val = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %param1_type_status = call i32 @weave_parser_expect(ptr %parser, i32 32)
  %param1_type_failed = icmp ne i32 %param1_type_status, 0
  br i1 %param1_type_failed, label %fail, label %param1_close

param1_close:
  %param1_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %param1_close_failed = icmp ne i32 %param1_close_status, 0
  br i1 %param1_close_failed, label %fail, label %after_param1

after_param1:
  %after_param1_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %has_param2 = icmp eq i32 %after_param1_kind, 1
  br i1 %has_param2, label %parse_param2, label %params_close

parse_param2:
  %param2_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %param2_open_failed = icmp ne i32 %param2_open_status, 0
  br i1 %param2_open_failed, label %fail, label %param2_name

param2_name:
  %param2_name_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %param2_is_ident = icmp eq i32 %param2_name_kind, 3
  br i1 %param2_is_ident, label %capture_param2_name, label %fail

capture_param2_name:
  %param2_start_val = call i64 @weave_parser_current_start(ptr %parser)
  %param2_len_val = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)
  %param2_type_status = call i32 @weave_parser_expect(ptr %parser, i32 32)
  %param2_type_failed = icmp ne i32 %param2_type_status, 0
  br i1 %param2_type_failed, label %fail, label %param2_close

param2_close:
  %param2_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %param2_close_failed = icmp ne i32 %param2_close_status, 0
  br i1 %param2_close_failed, label %fail, label %params_close

params_close:
  %param1_start = phi i64 [0, %params_empty_or_param1], [%param1_start_val, %after_param1], [%param1_start_val, %param2_close]
  %param1_len = phi i64 [0, %params_empty_or_param1], [%param1_len_val, %after_param1], [%param1_len_val, %param2_close]
  %param2_start = phi i64 [0, %params_empty_or_param1], [0, %after_param1], [%param2_start_val, %param2_close]
  %param2_len = phi i64 [0, %params_empty_or_param1], [0, %after_param1], [%param2_len_val, %param2_close]
  %params_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %params_close_failed = icmp ne i32 %params_close_status, 0
  br i1 %params_close_failed, label %fail, label %returns_open

returns_open:
  %returns_open_status = call i32 @weave_parser_expect(ptr %parser, i32 1)
  %returns_open_failed = icmp ne i32 %returns_open_status, 0
  br i1 %returns_open_failed, label %fail, label %returns_head

returns_head:
  %returns_status = call i32 @weave_parser_expect(ptr %parser, i32 29)
  %returns_failed = icmp ne i32 %returns_status, 0
  br i1 %returns_failed, label %fail, label %returns_type

returns_type:
  %returns_type_status = call i32 @weave_parser_expect(ptr %parser, i32 32)
  %returns_type_failed = icmp ne i32 %returns_type_status, 0
  br i1 %returns_type_failed, label %fail, label %returns_close

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
  %body_text_start_ptr = call ptr @weave_ast_node_text_start_ptr(ptr %body_node)
  %body_text_len_ptr = call ptr @weave_ast_node_text_len_ptr(ptr %body_node)
  store i64 %param2_start, ptr %body_text_start_ptr
  store i64 %param2_len, ptr %body_text_len_ptr
  br label %close_function

close_function:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 2,
    i64 %body,
    i64 %param1_start,
    i64 %param1_len,
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
  %first = phi i64 [-1, %decls_head], [%first_next, %after_function]
  %last = phi i64 [-1, %decls_head], [%function_node, %after_function]
  %count = phi i64 [0, %decls_head], [%count_next, %after_function]

  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %decls_done = icmp eq i32 %kind, 2
  br i1 %decls_done, label %decls_close, label %parse_function

parse_function:
  %function_node = call i64 @weave_parse_wir_function(ptr %parser, ptr %ast)
  %function_failed = icmp slt i64 %function_node, 0
  br i1 %function_failed, label %fail, label %after_function

after_function:
  %count_was_zero = icmp eq i64 %count, 0
  %first_next = select i1 %count_was_zero, i64 %function_node, i64 %first
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
; Parse zero or more top-level function definitions until EOF.
;
; AST_PROGRAM:
;   a = first function node index
;   b = last function node index
;   c = function count
; ----------------------------------------------------------------------------

define i64 @weave_parse_program(ptr %parser, ptr %ast) {
entry:
  br label %loop

loop:
  %first = phi i64 [-1, %entry], [%first_next, %after_function]
  %last = phi i64 [-1, %entry], [%function_node, %after_function]
  %count = phi i64 [0, %entry], [%count_next, %after_function]

  %kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_eof = icmp eq i32 %kind, 0
  br i1 %is_eof, label %finish, label %expect_top_lparen

expect_top_lparen:
  %is_lparen = icmp eq i32 %kind, 1
  br i1 %is_lparen, label %lookahead, label %fail

lookahead:
  %tokens = call ptr @weave_parser_tokens(ptr %parser)
  %index = call i64 @weave_parser_index(ptr %parser)
  %head_index = add i64 %index, 1
  %head_kind = call i32 @weave_token_kind(ptr %tokens, i64 %head_index)
  %is_fn = icmp eq i32 %head_kind, 6
  br i1 %is_fn, label %parse_function, label %check_wir_module

check_wir_module:
  %is_wir_module = icmp eq i32 %head_kind, 25
  br i1 %is_wir_module, label %parse_wir_module, label %fail

parse_wir_module:
  %wir_module_node = call i64 @weave_parse_wir_module(ptr %parser, ptr %ast)
  ret i64 %wir_module_node

parse_function:
  %function_node = call i64 @weave_parse_function(ptr %parser, ptr %ast)
  %function_failed = icmp slt i64 %function_node, 0
  br i1 %function_failed, label %fail, label %after_function

after_function:
  %count_was_zero = icmp eq i64 %count, 0
  %first_next = select i1 %count_was_zero, i64 %function_node, i64 %first
  %count_next = add i64 %count, 1
  br label %loop

finish:
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
