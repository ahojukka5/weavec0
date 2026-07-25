; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 04_lexer.ll
;
; Source -> token stream for the Stage 0 bootstrap compiler.
;
; Responsibilities:
;   - skip whitespace and `;` line comments
;   - recognise parens, identifiers, integer literals (incl. negative), and
;     double-quoted string literals with the escape vocabulary the bootstrap
;     subset admits (\\, \", \n, ...)
;   - classify a small set of reserved keywords (fn, return, if, else, while,
;     let, set, do, condition, ...) plus all WIR operator names (add_i32,
;     const_i64, lt_ptr, cast_*, ...) by matching the identifier byte slice
;     against a fixed table
;   - push the recognised tokens onto a %weave.Tokens stream
;
; Boundary:
;   No grammar / no AST. The lexer is intentionally a flat dispatch chain —
;   compactness is sacrificed for auditability. New keywords or operators
;   are admitted by adding one comparison to the chain below, never by
;   rewriting it.
; =============================================================================

; ----------------------------------------------------------------------------
; Source layout reminder
; ----------------------------------------------------------------------------
;
; %weave.Source = type { ptr, i64 }
;
; field 0 : data pointer, null-terminated
; field 1 : length in bytes, excluding final null terminator

; ----------------------------------------------------------------------------
; Source field helpers
; ----------------------------------------------------------------------------

define ptr @weave_source_data_ptr(ptr %source) {
entry:
  %field = getelementptr inbounds %weave.Source, ptr %source, i32 0, i32 0
  ret ptr %field
}

define ptr @weave_source_length_ptr(ptr %source) {
entry:
  %field = getelementptr inbounds %weave.Source, ptr %source, i32 0, i32 1
  ret ptr %field
}

define ptr @weave_source_data(ptr %source) {
entry:
  %field = call ptr @weave_source_data_ptr(ptr %source)
  %data = load ptr, ptr %field
  ret ptr %data
}

define i64 @weave_source_length(ptr %source) {
entry:
  %field = call ptr @weave_source_length_ptr(ptr %source)
  %length = load i64, ptr %field
  ret i64 %length
}

; ----------------------------------------------------------------------------
; Character classes
; ----------------------------------------------------------------------------

define i32 @weave_is_whitespace(i32 %ch) {
entry:
  %is_space = icmp eq i32 %ch, 32
  %is_tab = icmp eq i32 %ch, 9
  %is_lf = icmp eq i32 %ch, 10
  %is_cr = icmp eq i32 %ch, 13

  %a = or i1 %is_space, %is_tab
  %b = or i1 %is_lf, %is_cr
  %yes = or i1 %a, %b

  br i1 %yes, label %true, label %false

true:
  ret i32 1

false:
  ret i32 0
}

define i32 @weave_is_digit(i32 %ch) {
entry:
  %ge_zero = icmp sge i32 %ch, 48
  %le_nine = icmp sle i32 %ch, 57
  %yes = and i1 %ge_zero, %le_nine
  br i1 %yes, label %true, label %false

true:
  ret i32 1

false:
  ret i32 0
}

define i32 @weave_is_alpha(i32 %ch) {
entry:
  %ge_a = icmp sge i32 %ch, 97
  %le_z = icmp sle i32 %ch, 122
  %lower = and i1 %ge_a, %le_z

  %ge_A = icmp sge i32 %ch, 65
  %le_Z = icmp sle i32 %ch, 90
  %upper = and i1 %ge_A, %le_Z

  %yes = or i1 %lower, %upper
  br i1 %yes, label %true, label %false

true:
  ret i32 1

false:
  ret i32 0
}

define i32 @weave_is_ident_start(i32 %ch) {
entry:
  %alpha = call i32 @weave_is_alpha(i32 %ch)
  %is_alpha = icmp ne i32 %alpha, 0
  %underscore = icmp eq i32 %ch, 95
  %yes = or i1 %is_alpha, %underscore
  br i1 %yes, label %true, label %false

true:
  ret i32 1

false:
  ret i32 0
}

define i32 @weave_is_ident_continue(i32 %ch) {
entry:
  %start = call i32 @weave_is_ident_start(i32 %ch)
  %is_start = icmp ne i32 %start, 0
  %digit = call i32 @weave_is_digit(i32 %ch)
  %is_digit = icmp ne i32 %digit, 0
  %dash = icmp eq i32 %ch, 45
  %yes1 = or i1 %is_start, %is_digit
  %yes = or i1 %yes1, %dash
  br i1 %yes, label %true, label %false

true:
  ret i32 1

false:
  ret i32 0
}

; ----------------------------------------------------------------------------
; Byte access
; ----------------------------------------------------------------------------

define i32 @weave_source_byte_at(ptr %source, i64 %index) {
entry:
  %data = call ptr @weave_source_data(ptr %source)
  %slot = getelementptr inbounds i8, ptr %data, i64 %index
  %byte = load i8, ptr %slot
  %wide = zext i8 %byte to i32
  ret i32 %wide
}

; ----------------------------------------------------------------------------
; Keyword recognition
; ----------------------------------------------------------------------------
;
; Return token kind for identifier slice.
; If the slice is not a keyword, return TOKEN_IDENT = 3.

@weave.kw.fn = private unnamed_addr constant [3 x i8] c"fn\00"
@weave.kw.return = private unnamed_addr constant [7 x i8] c"return\00"
@weave.kw.if = private unnamed_addr constant [3 x i8] c"if\00"
@weave.kw.else = private unnamed_addr constant [5 x i8] c"else\00"
@weave.kw.while = private unnamed_addr constant [6 x i8] c"while\00"
@weave.kw.let = private unnamed_addr constant [4 x i8] c"let\00"
@weave.kw.set = private unnamed_addr constant [4 x i8] c"set\00"
@weave.kw.core_module = private unnamed_addr constant [12 x i8] c"core-module\00"
@weave.kw.core_version = private unnamed_addr constant [13 x i8] c"core-version\00"
@weave.kw.decls = private unnamed_addr constant [6 x i8] c"decls\00"
@weave.kw.params = private unnamed_addr constant [7 x i8] c"params\00"
@weave.kw.returns = private unnamed_addr constant [8 x i8] c"returns\00"
@weave.kw.do = private unnamed_addr constant [3 x i8] c"do\00"
@weave.kw.condition = private unnamed_addr constant [10 x i8] c"condition\00"
@weave.kw.const_i32 = private unnamed_addr constant [10 x i8] c"const_i32\00"
@weave.kw.i32 = private unnamed_addr constant [4 x i8] c"i32\00"
@weave.kw.param_get = private unnamed_addr constant [10 x i8] c"param_get\00"
@weave.kw.call_i32 = private unnamed_addr constant [9 x i8] c"call_i32\00"
@weave.kw.local_get = private unnamed_addr constant [10 x i8] c"local_get\00"
@weave.kw.then = private unnamed_addr constant [5 x i8] c"then\00"
@weave.kw.lt_i32 = private unnamed_addr constant [7 x i8] c"lt_i32\00"
@weave.kw.const_i64 = private unnamed_addr constant [10 x i8] c"const_i64\00"
@weave.kw.i64 = private unnamed_addr constant [4 x i8] c"i64\00"
@weave.kw.cast_i64_to_i32 = private unnamed_addr constant [16 x i8] c"cast_i64_to_i32\00"
@weave.kw.const_string_ptr = private unnamed_addr constant [17 x i8] c"const_string_ptr\00"
@weave.kw.add_i64 = private unnamed_addr constant [8 x i8] c"add_i64\00"
@weave.kw.mul_i64 = private unnamed_addr constant [8 x i8] c"mul_i64\00"
@weave.kw.sub_i64 = private unnamed_addr constant [8 x i8] c"sub_i64\00"
@weave.kw.add_i32 = private unnamed_addr constant [8 x i8] c"add_i32\00"
@weave.kw.lt_i64 = private unnamed_addr constant [7 x i8] c"lt_i64\00"
@weave.kw.le_i64 = private unnamed_addr constant [7 x i8] c"le_i64\00"
@weave.kw.ne_i64 = private unnamed_addr constant [7 x i8] c"ne_i64\00"
@weave.kw.eq_i64 = private unnamed_addr constant [7 x i8] c"eq_i64\00"
@weave.kw.const_bool = private unnamed_addr constant [11 x i8] c"const_bool\00"
@weave.kw.true = private unnamed_addr constant [5 x i8] c"true\00"
@weave.kw.false = private unnamed_addr constant [6 x i8] c"false\00"
@weave.kw.and_bool = private unnamed_addr constant [9 x i8] c"and_bool\00"
@weave.kw.or_bool = private unnamed_addr constant [8 x i8] c"or_bool\00"
@weave.kw.not_bool = private unnamed_addr constant [9 x i8] c"not_bool\00"
@weave.kw.const_null = private unnamed_addr constant [11 x i8] c"const_null\00"
@weave.kw.eq_ptr = private unnamed_addr constant [7 x i8] c"eq_ptr\00"
@weave.kw.ne_ptr = private unnamed_addr constant [7 x i8] c"ne_ptr\00"
@weave.kw.extern = private unnamed_addr constant [7 x i8] c"extern\00"
@weave.kw.ptr = private unnamed_addr constant [4 x i8] c"ptr\00"
@weave.kw.void = private unnamed_addr constant [5 x i8] c"void\00"
@weave.kw.call_ptr = private unnamed_addr constant [9 x i8] c"call_ptr\00"
@weave.kw.call_void = private unnamed_addr constant [10 x i8] c"call_void\00"
@weave.kw.ptr_add = private unnamed_addr constant [8 x i8] c"ptr_add\00"
@weave.kw.load_i64 = private unnamed_addr constant [9 x i8] c"load_i64\00"
@weave.kw.store_i64 = private unnamed_addr constant [10 x i8] c"store_i64\00"
@weave.kw.load_u8 = private unnamed_addr constant [8 x i8] c"load_u8\00"
@weave.kw.store_i8 = private unnamed_addr constant [9 x i8] c"store_i8\00"
@weave.kw.call_i64 = private unnamed_addr constant [9 x i8] c"call_i64\00"
@weave.kw.return_void = private unnamed_addr constant [12 x i8] c"return_void\00"
@weave.kw.mod_i32 = private unnamed_addr constant [8 x i8] c"mod_i32\00"
@weave.kw.load_ptr = private unnamed_addr constant [9 x i8] c"load_ptr\00"
@weave.kw.store_ptr = private unnamed_addr constant [10 x i8] c"store_ptr\00"
@weave.kw.bool = private unnamed_addr constant [5 x i8] c"bool\00"
@weave.kw.call_bool = private unnamed_addr constant [10 x i8] c"call_bool\00"
@weave.kw.ne_i32 = private unnamed_addr constant [7 x i8] c"ne_i32\00"
@weave.kw.eq_i32 = private unnamed_addr constant [7 x i8] c"eq_i32\00"
@weave.kw.ge_i32 = private unnamed_addr constant [7 x i8] c"ge_i32\00"
@weave.kw.le_i32 = private unnamed_addr constant [7 x i8] c"le_i32\00"
@weave.kw.gt_i32 = private unnamed_addr constant [7 x i8] c"gt_i32\00"
@weave.kw.sub_i32 = private unnamed_addr constant [8 x i8] c"sub_i32\00"
@weave.kw.mul_i32 = private unnamed_addr constant [8 x i8] c"mul_i32\00"
@weave.kw.div_i32 = private unnamed_addr constant [8 x i8] c"div_i32\00"
@weave.kw.load_i32 = private unnamed_addr constant [9 x i8] c"load_i32\00"
@weave.kw.store_i32 = private unnamed_addr constant [10 x i8] c"store_i32\00"
@weave.kw.cast_i32_to_i64 = private unnamed_addr constant [16 x i8] c"cast_i32_to_i64\00"

define i32 @weave_keyword_kind(ptr %text, i64 %length) {
entry:
  %is_fn = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.fn, i64 2)
  %fn_yes = icmp ne i32 %is_fn, 0
  br i1 %fn_yes, label %return_fn, label %check_return

check_return:
  %is_return = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.return, i64 6)
  %return_yes = icmp ne i32 %is_return, 0
  br i1 %return_yes, label %return_return, label %check_if

check_if:
  %is_if = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.if, i64 2)
  %if_yes = icmp ne i32 %is_if, 0
  br i1 %if_yes, label %return_if, label %check_else

check_else:
  %is_else = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.else, i64 4)
  %else_yes = icmp ne i32 %is_else, 0
  br i1 %else_yes, label %return_else, label %check_while

check_while:
  %is_while = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.while, i64 5)
  %while_yes = icmp ne i32 %is_while, 0
  br i1 %while_yes, label %return_while, label %check_let

check_let:
  %is_let = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.let, i64 3)
  %let_yes = icmp ne i32 %is_let, 0
  br i1 %let_yes, label %return_let, label %check_set

check_set:
  %is_set = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.set, i64 3)
  %set_yes = icmp ne i32 %is_set, 0
  br i1 %set_yes, label %return_set, label %check_core_module

check_core_module:
  %is_core_module = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.core_module, i64 11)
  %core_module_yes = icmp ne i32 %is_core_module, 0
  br i1 %core_module_yes, label %return_core_module, label %check_core_version

check_core_version:
  %is_core_version = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.core_version, i64 12)
  %core_version_yes = icmp ne i32 %is_core_version, 0
  br i1 %core_version_yes, label %return_core_version, label %check_decls

check_decls:
  %is_decls = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.decls, i64 5)
  %decls_yes = icmp ne i32 %is_decls, 0
  br i1 %decls_yes, label %return_decls, label %check_params

check_params:
  %is_params = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.params, i64 6)
  %params_yes = icmp ne i32 %is_params, 0
  br i1 %params_yes, label %return_params, label %check_returns

check_returns:
  %is_returns = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.returns, i64 7)
  %returns_yes = icmp ne i32 %is_returns, 0
  br i1 %returns_yes, label %return_returns, label %check_do

check_do:
  %is_do = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.do, i64 2)
  %do_yes = icmp ne i32 %is_do, 0
  br i1 %do_yes, label %return_do, label %check_condition

check_condition:
  %is_condition = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.condition, i64 9)
  %condition_yes = icmp ne i32 %is_condition, 0
  br i1 %condition_yes, label %return_condition, label %check_const_i32

check_const_i32:
  %is_const_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.const_i32, i64 9)
  %const_i32_yes = icmp ne i32 %is_const_i32, 0
  br i1 %const_i32_yes, label %return_const_i32, label %check_i32

check_i32:
  %is_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.i32, i64 3)
  %i32_yes = icmp ne i32 %is_i32, 0
  br i1 %i32_yes, label %return_i32, label %check_param_get

check_param_get:
  %is_param_get = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.param_get, i64 9)
  %param_get_yes = icmp ne i32 %is_param_get, 0
  br i1 %param_get_yes, label %return_param_get, label %check_call_i32

check_call_i32:
  %is_call_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.call_i32, i64 8)
  %call_i32_yes = icmp ne i32 %is_call_i32, 0
  br i1 %call_i32_yes, label %return_call_i32, label %check_local_get

check_local_get:
  %is_local_get = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.local_get, i64 9)
  %local_get_yes = icmp ne i32 %is_local_get, 0
  br i1 %local_get_yes, label %return_local_get, label %check_then

check_then:
  %is_then = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.then, i64 4)
  %then_yes = icmp ne i32 %is_then, 0
  br i1 %then_yes, label %return_then, label %check_lt_i32

check_lt_i32:
  %is_lt_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.lt_i32, i64 6)
  %lt_i32_yes = icmp ne i32 %is_lt_i32, 0
  br i1 %lt_i32_yes, label %return_lt_i32, label %check_const_i64

check_const_i64:
  %is_const_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.const_i64, i64 9)
  %const_i64_yes = icmp ne i32 %is_const_i64, 0
  br i1 %const_i64_yes, label %return_const_i64, label %check_i64

check_i64:
  %is_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.i64, i64 3)
  %i64_yes = icmp ne i32 %is_i64, 0
  br i1 %i64_yes, label %return_i64, label %check_cast_i64_to_i32

check_cast_i64_to_i32:
  %is_cast_i64_to_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.cast_i64_to_i32, i64 15)
  %cast_i64_to_i32_yes = icmp ne i32 %is_cast_i64_to_i32, 0
  br i1 %cast_i64_to_i32_yes, label %return_cast_i64_to_i32, label %check_const_string_ptr

check_const_string_ptr:
  %is_const_string_ptr = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.const_string_ptr, i64 16)
  %const_string_ptr_yes = icmp ne i32 %is_const_string_ptr, 0
  br i1 %const_string_ptr_yes, label %return_const_string_ptr, label %check_add_i64

check_add_i64:
  %is_add_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.add_i64, i64 7)
  %add_i64_yes = icmp ne i32 %is_add_i64, 0
  br i1 %add_i64_yes, label %return_add_i64, label %check_mul_i64

check_mul_i64:
  %is_mul_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.mul_i64, i64 7)
  %mul_i64_yes = icmp ne i32 %is_mul_i64, 0
  br i1 %mul_i64_yes, label %return_mul_i64, label %check_sub_i64

check_sub_i64:
  %is_sub_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.sub_i64, i64 7)
  %sub_i64_yes = icmp ne i32 %is_sub_i64, 0
  br i1 %sub_i64_yes, label %return_sub_i64, label %check_add_i32

check_add_i32:
  %is_add_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.add_i32, i64 7)
  %add_i32_yes = icmp ne i32 %is_add_i32, 0
  br i1 %add_i32_yes, label %return_add_i32, label %check_lt_i64

check_lt_i64:
  %is_lt_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.lt_i64, i64 6)
  %lt_i64_yes = icmp ne i32 %is_lt_i64, 0
  br i1 %lt_i64_yes, label %return_lt_i64, label %check_le_i64

check_le_i64:
  %is_le_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.le_i64, i64 6)
  %le_i64_yes = icmp ne i32 %is_le_i64, 0
  br i1 %le_i64_yes, label %return_le_i64, label %check_ne_i64

check_ne_i64:
  %is_ne_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.ne_i64, i64 6)
  %ne_i64_yes = icmp ne i32 %is_ne_i64, 0
  br i1 %ne_i64_yes, label %return_ne_i64, label %check_eq_i64

check_eq_i64:
  %is_eq_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.eq_i64, i64 6)
  %eq_i64_yes = icmp ne i32 %is_eq_i64, 0
  br i1 %eq_i64_yes, label %return_eq_i64, label %check_const_bool

check_const_bool:
  %is_const_bool = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.const_bool, i64 10)
  %const_bool_yes = icmp ne i32 %is_const_bool, 0
  br i1 %const_bool_yes, label %return_const_bool, label %check_true

check_true:
  %is_true = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.true, i64 4)
  %true_yes = icmp ne i32 %is_true, 0
  br i1 %true_yes, label %return_true, label %check_false

check_false:
  %is_false = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.false, i64 5)
  %false_yes = icmp ne i32 %is_false, 0
  br i1 %false_yes, label %return_false, label %check_and_bool

check_and_bool:
  %is_and_bool = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.and_bool, i64 8)
  %and_bool_yes = icmp ne i32 %is_and_bool, 0
  br i1 %and_bool_yes, label %return_and_bool, label %check_or_bool

check_or_bool:
  %is_or_bool = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.or_bool, i64 7)
  %or_bool_yes = icmp ne i32 %is_or_bool, 0
  br i1 %or_bool_yes, label %return_or_bool, label %check_not_bool

check_not_bool:
  %is_not_bool = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.not_bool, i64 8)
  %not_bool_yes = icmp ne i32 %is_not_bool, 0
  br i1 %not_bool_yes, label %return_not_bool, label %check_const_null

check_const_null:
  %is_const_null = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.const_null, i64 10)
  %const_null_yes = icmp ne i32 %is_const_null, 0
  br i1 %const_null_yes, label %return_const_null, label %check_eq_ptr

check_eq_ptr:
  %is_eq_ptr = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.eq_ptr, i64 6)
  %eq_ptr_yes = icmp ne i32 %is_eq_ptr, 0
  br i1 %eq_ptr_yes, label %return_eq_ptr, label %check_ne_ptr

check_ne_ptr:
  %is_ne_ptr = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.ne_ptr, i64 6)
  %ne_ptr_yes = icmp ne i32 %is_ne_ptr, 0
  br i1 %ne_ptr_yes, label %return_ne_ptr, label %check_extern

check_extern:
  %is_extern = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.extern, i64 6)
  %extern_yes = icmp ne i32 %is_extern, 0
  br i1 %extern_yes, label %return_extern, label %check_ptr

check_ptr:
  %is_ptr = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.ptr, i64 3)
  %ptr_yes = icmp ne i32 %is_ptr, 0
  br i1 %ptr_yes, label %return_ptr, label %check_void

check_void:
  %is_void = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.void, i64 4)
  %void_yes = icmp ne i32 %is_void, 0
  br i1 %void_yes, label %return_void, label %check_call_ptr

check_call_ptr:
  %is_call_ptr = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.call_ptr, i64 8)
  %call_ptr_yes = icmp ne i32 %is_call_ptr, 0
  br i1 %call_ptr_yes, label %return_call_ptr, label %check_call_void

check_call_void:
  %is_call_void = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.call_void, i64 9)
  %call_void_yes = icmp ne i32 %is_call_void, 0
  br i1 %call_void_yes, label %return_call_void, label %check_ptr_add

check_ptr_add:
  %is_ptr_add = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.ptr_add, i64 7)
  %ptr_add_yes = icmp ne i32 %is_ptr_add, 0
  br i1 %ptr_add_yes, label %return_ptr_add, label %check_load_i64

check_load_i64:
  %is_load_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.load_i64, i64 8)
  %load_i64_yes = icmp ne i32 %is_load_i64, 0
  br i1 %load_i64_yes, label %return_load_i64, label %check_store_i64

check_store_i64:
  %is_store_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.store_i64, i64 9)
  %store_i64_yes = icmp ne i32 %is_store_i64, 0
  br i1 %store_i64_yes, label %return_store_i64, label %check_load_u8

check_load_u8:
  %is_load_u8 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.load_u8, i64 7)
  %load_u8_yes = icmp ne i32 %is_load_u8, 0
  br i1 %load_u8_yes, label %return_load_u8, label %check_store_i8

check_store_i8:
  %is_store_i8 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.store_i8, i64 8)
  %store_i8_yes = icmp ne i32 %is_store_i8, 0
  br i1 %store_i8_yes, label %return_store_i8, label %check_call_i64

check_call_i64:
  %is_call_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.call_i64, i64 8)
  %call_i64_yes = icmp ne i32 %is_call_i64, 0
  br i1 %call_i64_yes, label %return_call_i64, label %check_return_void

check_return_void:
  %is_return_void = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.return_void, i64 11)
  %return_void_yes = icmp ne i32 %is_return_void, 0
  br i1 %return_void_yes, label %return_return_void, label %check_mod_i32

check_mod_i32:
  %is_mod_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.mod_i32, i64 7)
  %mod_i32_yes = icmp ne i32 %is_mod_i32, 0
  br i1 %mod_i32_yes, label %return_mod_i32, label %check_load_ptr

check_load_ptr:
  %is_load_ptr = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.load_ptr, i64 8)
  %load_ptr_yes = icmp ne i32 %is_load_ptr, 0
  br i1 %load_ptr_yes, label %return_load_ptr, label %check_store_ptr

check_store_ptr:
  %is_store_ptr = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.store_ptr, i64 9)
  %store_ptr_yes = icmp ne i32 %is_store_ptr, 0
  br i1 %store_ptr_yes, label %return_store_ptr, label %check_bool_type

check_bool_type:
  %is_bool_type = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.bool, i64 4)
  %bool_type_yes = icmp ne i32 %is_bool_type, 0
  br i1 %bool_type_yes, label %return_bool_type, label %check_call_bool

check_call_bool:
  %is_call_bool = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.call_bool, i64 9)
  %call_bool_yes = icmp ne i32 %is_call_bool, 0
  br i1 %call_bool_yes, label %return_call_bool, label %check_ne_i32

check_ne_i32:
  %is_ne_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.ne_i32, i64 6)
  %ne_i32_yes = icmp ne i32 %is_ne_i32, 0
  br i1 %ne_i32_yes, label %return_ne_i32, label %check_eq_i32

check_eq_i32:
  %is_eq_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.eq_i32, i64 6)
  %eq_i32_yes = icmp ne i32 %is_eq_i32, 0
  br i1 %eq_i32_yes, label %return_eq_i32, label %check_ge_i32

check_ge_i32:
  %is_ge_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.ge_i32, i64 6)
  %ge_i32_yes = icmp ne i32 %is_ge_i32, 0
  br i1 %ge_i32_yes, label %return_ge_i32, label %check_le_i32

check_le_i32:
  %is_le_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.le_i32, i64 6)
  %le_i32_yes = icmp ne i32 %is_le_i32, 0
  br i1 %le_i32_yes, label %return_le_i32, label %check_gt_i32

check_gt_i32:
  %is_gt_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.gt_i32, i64 6)
  %gt_i32_yes = icmp ne i32 %is_gt_i32, 0
  br i1 %gt_i32_yes, label %return_gt_i32, label %check_sub_i32

check_sub_i32:
  %is_sub_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.sub_i32, i64 7)
  %sub_i32_yes = icmp ne i32 %is_sub_i32, 0
  br i1 %sub_i32_yes, label %return_sub_i32, label %check_mul_i32

check_mul_i32:
  %is_mul_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.mul_i32, i64 7)
  %mul_i32_yes = icmp ne i32 %is_mul_i32, 0
  br i1 %mul_i32_yes, label %return_mul_i32, label %check_div_i32

check_div_i32:
  %is_div_i32 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.div_i32, i64 7)
  %div_i32_yes = icmp ne i32 %is_div_i32, 0
  br i1 %div_i32_yes, label %return_div_i32, label %check_load_i32_kw

check_load_i32_kw:
  %is_load_i32_kw = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.load_i32, i64 8)
  %load_i32_kw_yes = icmp ne i32 %is_load_i32_kw, 0
  br i1 %load_i32_kw_yes, label %return_load_i32_kw, label %check_store_i32_kw

check_store_i32_kw:
  %is_store_i32_kw = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.store_i32, i64 9)
  %store_i32_kw_yes = icmp ne i32 %is_store_i32_kw, 0
  br i1 %store_i32_kw_yes, label %return_store_i32_kw, label %check_cast_i32_to_i64

check_cast_i32_to_i64:
  %is_cast_i32_to_i64 = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.cast_i32_to_i64, i64 15)
  %cast_i32_to_i64_yes = icmp ne i32 %is_cast_i32_to_i64, 0
  br i1 %cast_i32_to_i64_yes, label %return_cast_i32_to_i64, label %return_ident

return_fn:
  ret i32 6

return_return:
  ret i32 7

return_if:
  ret i32 8

return_else:
  ret i32 9

return_while:
  ret i32 10

return_let:
  ret i32 11

return_set:
  ret i32 12

return_core_module:
  ret i32 25

return_core_version:
  ret i32 26

return_decls:
  ret i32 27

return_params:
  ret i32 28

return_returns:
  ret i32 29

return_const_i32:
  ret i32 31

return_i32:
  ret i32 32

return_param_get:
  ret i32 33

return_call_i32:
  ret i32 34

return_local_get:
  ret i32 35

return_then:
  ret i32 36

return_lt_i32:
  ret i32 37

return_const_i64:
  ret i32 38

return_i64:
  ret i32 39

return_cast_i64_to_i32:
  ret i32 40

return_add_i64:
  ret i32 42

return_mul_i64:
  ret i32 43

return_add_i32:
  ret i32 44

return_lt_i64:
  ret i32 46

return_le_i64:
  ret i32 47

return_ne_i64:
  ret i32 48

return_const_bool:
  ret i32 49

return_true:
  ret i32 50

return_false:
  ret i32 51

return_and_bool:
  ret i32 52

return_or_bool:
  ret i32 53

return_const_null:
  ret i32 54

return_eq_ptr:
  ret i32 55

return_ne_ptr:
  ret i32 56

return_extern:
  ret i32 57

return_ptr:
  ret i32 58

return_void:
  ret i32 59

return_call_ptr:
  ret i32 60

return_call_void:
  ret i32 61

return_ptr_add:
  ret i32 62

return_load_i64:
  ret i32 63

return_store_i64:
  ret i32 64

return_load_u8:
  ret i32 65

return_store_i8:
  ret i32 66

return_call_i64:
  ret i32 67

return_return_void:
  ret i32 68

return_mod_i32:
  ret i32 69

return_load_ptr:
  ret i32 70

return_store_ptr:
  ret i32 71

return_bool_type:
  ret i32 72

return_call_bool:
  ret i32 73

return_ne_i32:
  ret i32 74

return_eq_i32:
  ret i32 75

return_ge_i32:
  ret i32 76

return_le_i32:
  ret i32 77

return_gt_i32:
  ret i32 90

return_sub_i32:
  ret i32 89

return_mul_i32:
  ret i32 78

return_div_i32:
  ret i32 79

return_load_i32_kw:
  ret i32 80

return_store_i32_kw:
  ret i32 81

return_cast_i32_to_i64:
  ret i32 82

return_const_string_ptr:
  ret i32 83

return_sub_i64:
  ret i32 84

return_eq_i64:
  ret i32 85

return_not_bool:
  ret i32 86

return_do:
  ret i32 87

return_condition:
  ret i32 88

return_ident:
  ret i32 3
}

; ----------------------------------------------------------------------------
; Integer scanning
; ----------------------------------------------------------------------------
;
; Scan one signed decimal integer starting at `start`.
;
; The magnitude is accumulated with explicit bounds. Positive values admit at
; most INT64_MAX; negative values admit the one larger INT64_MIN magnitude.
; When the preceding token is const_i32, the final signed value must also fit
; exactly in i32. This keeps every integer token authoritative and avoids libc
; conversion, saturation, truncation, and dependence on a trailing NUL byte.
;
; On success, appends TOKEN_INT and returns the index just after the literal.
; On failure, returns -1.


define i64 @weave_lex_integer(ptr %source, ptr %tokens, i64 %start) {
entry:
  %length = call i64 @weave_source_length(ptr %source)
  %first_ch = call i32 @weave_source_byte_at(ptr %source, i64 %start)
  %is_minus = icmp eq i32 %first_ch, 45
  %signed_start = add i64 %start, 1
  %scan_start = select i1 %is_minus, i64 %signed_start, i64 %start
  %token_count = call i64 @weave_tokens_count(ptr %tokens)
  %has_previous = icmp ugt i64 %token_count, 0
  br i1 %has_previous, label %read_previous, label %init

read_previous:
  %previous_index = sub i64 %token_count, 1
  %previous_kind = call i32 @weave_token_kind(ptr %tokens, i64 %previous_index)
  %previous_is_const_i32 = icmp eq i32 %previous_kind, 31
  br label %init

init:
  %requires_i32 = phi i1 [false, %entry], [%previous_is_const_i32, %read_previous]
  %last_digit_limit = select i1 %is_minus, i64 8, i64 7
  br label %loop

loop:
  %index = phi i64 [%scan_start, %init], [%next, %accumulate]
  %magnitude = phi i64 [0, %init], [%next_magnitude, %accumulate]
  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %finish, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)
  %is_digit_status = call i32 @weave_is_digit(i32 %ch)
  %is_digit = icmp ne i32 %is_digit_status, 0
  br i1 %is_digit, label %check_overflow, label %finish

check_overflow:
  %digit_i32 = sub i32 %ch, 48
  %digit = zext i32 %digit_i32 to i64
  %prefix_too_large = icmp ugt i64 %magnitude, 922337203685477580
  %prefix_at_limit = icmp eq i64 %magnitude, 922337203685477580
  %last_digit_too_large = icmp ugt i64 %digit, %last_digit_limit
  %overflow_at_limit = and i1 %prefix_at_limit, %last_digit_too_large
  %overflow = or i1 %prefix_too_large, %overflow_at_limit
  br i1 %overflow, label %fail, label %accumulate

accumulate:
  %scaled = mul i64 %magnitude, 10
  %next_magnitude = add i64 %scaled, %digit
  %next = add i64 %index, 1
  br label %loop

finish:
  %digit_count = sub i64 %index, %scan_start
  %empty = icmp eq i64 %digit_count, 0
  br i1 %empty, label %fail, label %apply_sign

apply_sign:
  ; Plain LLVM integer arithmetic wraps modulo 2^64 without nsw/nuw flags, so
  ; subtracting the admitted 2^63 magnitude yields the exact INT64_MIN bits.
  %negative_value = sub i64 0, %magnitude
  %value = select i1 %is_minus, i64 %negative_value, i64 %magnitude
  br i1 %requires_i32, label %check_i32_range, label %push

check_i32_range:
  %below_i32 = icmp slt i64 %value, -2147483648
  %above_i32 = icmp sgt i64 %value, 2147483647
  %outside_i32 = or i1 %below_i32, %above_i32
  br i1 %outside_i32, label %fail, label %push

push:
  %token_length = sub i64 %index, %start
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 4, i64 %start, i64 %token_length, i64 %value)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %success

success:
  ret i64 %index

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; Identifier / keyword scanning
; ----------------------------------------------------------------------------


define i64 @weave_lex_identifier(ptr %source, ptr %tokens, i64 %start) {
entry:
  %length = call i64 @weave_source_length(ptr %source)
  br label %loop

loop:
  %index = phi i64 [%start, %entry], [%next, %advance]
  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %finish, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)
  %is_continue = call i32 @weave_is_ident_continue(i32 %ch)
  %yes = icmp ne i32 %is_continue, 0
  br i1 %yes, label %advance, label %finish

advance:
  %next = add i64 %index, 1
  br label %loop

finish:
  %token_length = sub i64 %index, %start
  %data = call ptr @weave_source_data(ptr %source)
  %text = getelementptr inbounds i8, ptr %data, i64 %start
  %kind = call i32 @weave_keyword_kind(ptr %text, i64 %token_length)
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 %kind, i64 %start, i64 %token_length, i64 0)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %success

success:
  ret i64 %index

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; String literal scanning
; ----------------------------------------------------------------------------
;
; Strings are kept as source slices. Escapes are skipped here but not decoded.
; The emitter can later decide how to encode them into LLVM string constants.
;
; start points at the opening quote.


define i64 @weave_lex_string(ptr %source, ptr %tokens, i64 %start) {
entry:
  %length = call i64 @weave_source_length(ptr %source)
  %content_start = add i64 %start, 1
  br label %loop

loop:
  %index = phi i64 [%content_start, %entry], [%next_index, %continue]
  %escaped = phi i32 [0, %entry], [%next_escaped, %continue]

  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %fail, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)
  %is_quote = icmp eq i32 %ch, 34
  %is_backslash = icmp eq i32 %ch, 92
  %was_escaped = icmp ne i32 %escaped, 0

  br i1 %was_escaped, label %escaped_char, label %normal_char

escaped_char:
  br label %advance_clear_escape

normal_char:
  br i1 %is_quote, label %finish, label %maybe_escape

maybe_escape:
  br i1 %is_backslash, label %advance_set_escape, label %advance_clear_escape

advance_set_escape:
  %next_index_set = add i64 %index, 1
  br label %continue_set

continue_set:
  br label %continue

advance_clear_escape:
  %next_index_clear = add i64 %index, 1
  br label %continue_clear

continue_clear:
  br label %continue

continue:
  %next_index = phi i64 [%next_index_set, %continue_set], [%next_index_clear, %continue_clear]
  %next_escaped = phi i32 [1, %continue_set], [0, %continue_clear]
  br label %loop

finish:
  %content_length = sub i64 %index, %content_start
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 5, i64 %content_start, i64 %content_length, i64 0)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %success

success:
  %after_quote = add i64 %index, 1
  ret i64 %after_quote

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; Comment skipping
; ----------------------------------------------------------------------------
;
; A semicolon starts a comment that continues until newline or EOF.


define i64 @weave_skip_comment(ptr %source, i64 %start) {
entry:
  %length = call i64 @weave_source_length(ptr %source)
  br label %loop

loop:
  %index = phi i64 [%start, %entry], [%next, %advance]
  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %done, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)
  %is_lf = icmp eq i32 %ch, 10
  br i1 %is_lf, label %done, label %advance

advance:
  %next = add i64 %index, 1
  br label %loop

done:
  ret i64 %index
}

; ----------------------------------------------------------------------------
; WIR punctuation
; ----------------------------------------------------------------------------


define i64 @weave_lex_punctuation(ptr %source, ptr %tokens, i64 %index, i32 %ch) {
entry:
  %is_lparen = icmp eq i32 %ch, 40
  br i1 %is_lparen, label %push_lparen, label %check_rparen

check_rparen:
  %is_rparen = icmp eq i32 %ch, 41
  br i1 %is_rparen, label %push_rparen, label %fail

push_lparen:
  %s0 = call i32 @weave_tokens_push(ptr %tokens, i32 1, i64 %index, i64 1, i64 0)
  br label %single_done

push_rparen:
  %s1 = call i32 @weave_tokens_push(ptr %tokens, i32 2, i64 %index, i64 1, i64 0)
  br label %single_done

single_done:
  %single_status = phi i32 [%s0, %push_lparen], [%s1, %push_rparen]
  %single_failed = icmp ne i32 %single_status, 0
  br i1 %single_failed, label %fail, label %single_success

single_success:
  %after_single = add i64 %index, 1
  ret i64 %after_single

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_lex
;
; Module entry point. Tokenise the entire %weave.Source into the supplied
; %weave.Tokens stream, dispatching one byte at a time through the dispatch
; chain (whitespace / comment / paren / number / string / identifier).
;
; Parameters:
;   source - %weave.Source* with byte data and length already populated.
;   tokens - %weave.Tokens* initialised via weave_tokens_init.
;
; Returns:
;   0 on success; the token stream holds the produced tokens.
;   1 on failure (either argument null, an unrecognised byte, or any inner
;     dispatch returning a sentinel index of -1).
;
; Notes:
;   The lexer does not allocate or take ownership of `source` or `tokens` —
;   the driver owns them. On failure the partial token stream is left in
;   place; the caller frees both via the usual cleanup paths.
; ----------------------------------------------------------------------------


define i32 @weave_lex(ptr %source, ptr %tokens) {
entry:
  %source_null = icmp eq ptr %source, null
  %tokens_null = icmp eq ptr %tokens, null
  %bad = or i1 %source_null, %tokens_null
  br i1 %bad, label %fail, label %loop

loop:
  %index = phi i64 [0, %entry], [%next_index, %continue]
  %length = call i64 @weave_source_length(ptr %source)
  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %push_eof, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)

  %space = call i32 @weave_is_whitespace(i32 %ch)
  %is_space = icmp ne i32 %space, 0
  br i1 %is_space, label %skip_one, label %check_comment

check_comment:
  %is_comment = icmp eq i32 %ch, 59
  br i1 %is_comment, label %skip_comment, label %check_ident

check_ident:
  %ident_start = call i32 @weave_is_ident_start(i32 %ch)
  %is_ident = icmp ne i32 %ident_start, 0
  br i1 %is_ident, label %lex_ident, label %check_digit

check_digit:
  %digit = call i32 @weave_is_digit(i32 %ch)
  %is_digit = icmp ne i32 %digit, 0
  br i1 %is_digit, label %lex_integer, label %check_minus

check_minus:
  %is_minus_ch = icmp eq i32 %ch, 45
  br i1 %is_minus_ch, label %check_minus_digit, label %check_string

check_minus_digit:
  %next_index_for_minus = add i64 %index, 1
  %minus_has_next = icmp ult i64 %next_index_for_minus, %length
  br i1 %minus_has_next, label %read_minus_next, label %check_string

read_minus_next:
  %minus_next_ch = call i32 @weave_source_byte_at(ptr %source, i64 %next_index_for_minus)
  %minus_next_digit_i32 = call i32 @weave_is_digit(i32 %minus_next_ch)
  %minus_next_digit = icmp ne i32 %minus_next_digit_i32, 0
  br i1 %minus_next_digit, label %lex_integer, label %check_string

check_string:
  %is_quote = icmp eq i32 %ch, 34
  br i1 %is_quote, label %lex_string, label %lex_punctuation

skip_one:
  %after_space = add i64 %index, 1
  br label %continue_from_skip_one

continue_from_skip_one:
  br label %continue

skip_comment:
  %after_comment = call i64 @weave_skip_comment(ptr %source, i64 %index)
  br label %continue_from_comment

continue_from_comment:
  br label %continue

lex_ident:
  %after_ident = call i64 @weave_lex_identifier(ptr %source, ptr %tokens, i64 %index)
  %ident_failed = icmp slt i64 %after_ident, 0
  br i1 %ident_failed, label %fail, label %continue_from_ident

continue_from_ident:
  br label %continue

lex_integer:
  %after_integer = call i64 @weave_lex_integer(ptr %source, ptr %tokens, i64 %index)
  %integer_failed = icmp slt i64 %after_integer, 0
  br i1 %integer_failed, label %fail, label %continue_from_integer

continue_from_integer:
  br label %continue

lex_string:
  %after_string = call i64 @weave_lex_string(ptr %source, ptr %tokens, i64 %index)
  %string_failed = icmp slt i64 %after_string, 0
  br i1 %string_failed, label %fail, label %continue_from_string

continue_from_string:
  br label %continue

lex_punctuation:
  %after_punctuation = call i64 @weave_lex_punctuation(ptr %source, ptr %tokens, i64 %index, i32 %ch)
  %punctuation_failed = icmp slt i64 %after_punctuation, 0
  br i1 %punctuation_failed, label %fail, label %continue_from_punctuation

continue_from_punctuation:
  br label %continue

continue:
  %next_index = phi i64 [%after_space, %continue_from_skip_one], [%after_comment, %continue_from_comment], [%after_ident, %continue_from_ident], [%after_integer, %continue_from_integer], [%after_string, %continue_from_string], [%after_punctuation, %continue_from_punctuation]
  br label %loop

push_eof:
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 0, i64 %length, i64 0, i64 0)
  %eof_failed = icmp ne i32 %status, 0
  br i1 %eof_failed, label %fail, label %success

success:
  ret i32 0

fail:
  ret i32 1
}
