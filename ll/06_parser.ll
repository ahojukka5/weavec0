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
;
; Stage 0 calls are deliberately limited to one argument for now. This is enough
; to build early compiler-shaped tests without designing a full argument list
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
  br i1 %is_operator, label %parse_binary, label %parse_call_head

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

parse_call_head:
  %is_ident = icmp eq i32 %head_kind, 3
  br i1 %is_ident, label %parse_call, label %fail

parse_call:
  %name_start = call i64 @weave_parser_current_start(ptr %parser)
  %name_len = call i64 @weave_parser_current_length(ptr %parser)
  call void @weave_parser_advance(ptr %parser)

  %arg = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  %arg_failed = icmp slt i64 %arg, 0
  br i1 %arg_failed, label %fail, label %call_close

call_close:
  %call_close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %call_close_failed = icmp ne i32 %call_close_status, 0
  br i1 %call_close_failed, label %fail, label %make_call

make_call:
  %call_node = call i64 @weave_ast_push(
    ptr %ast,
    i32 9,
    i64 %arg,
    i64 0,
    i64 0,
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
;
; The variable type is intentionally omitted in Stage 0. The emitter treats all
; locals as i32 for now. This keeps the bridge small.
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
  %then_node = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %then_failed = icmp slt i64 %then_node, 0
  br i1 %then_failed, label %fail, label %else_branch

else_branch:
  %else_node = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %else_failed = icmp slt i64 %else_node, 0
  br i1 %else_failed, label %fail, label %close

close:
  %close_status = call i32 @weave_parser_expect(ptr %parser, i32 2)
  %close_failed = icmp ne i32 %close_status, 0
  br i1 %close_failed, label %fail, label %make_node

make_node:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 5,
    i64 %cond,
    i64 %then_node,
    i64 %else_node,
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
  br i1 %cond_failed, label %fail, label %body

body:
  %body_node = call i64 @weave_parse_stmt(ptr %parser, ptr %ast)
  %body_failed = icmp slt i64 %body_node, 0
  br i1 %body_failed, label %fail, label %close

close:
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
  br i1 %is_set, label %set_stmt, label %expr_stmt

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

expr_stmt:
  %expr_node = call i64 @weave_parse_expr(ptr %parser, ptr %ast)
  ret i64 %expr_node

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
  %is_block_ident = icmp eq i32 %head_kind, 3
  br i1 %is_block_ident, label %consume_head, label %fail

consume_head:
  ; The lexer does not reserve `block` as a keyword. Stage 0 accepts any IDENT
  ; here and relies on tests to use `block`. This avoids adding a token too early.
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
;
; Stage 0 supports either zero parameters or one bare parameter name. Explicit
; return types and parameter lists are intentionally omitted for now.
;
; AST_FUNCTION:
;   a = body block node index
;   b = parameter name source start, or 0
;   c = parameter name source length, or 0
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
  br label %parse_body

parse_body:
  %body_param_start = phi i64 [0, %capture_name], [%param_start, %capture_param]
  %body_param_len = phi i64 [0, %capture_name], [%param_len, %capture_param]
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
    i64 0,
    i64 0
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
  br i1 %is_fn, label %parse_function, label %fail

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
