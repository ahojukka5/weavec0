; =============================================================================
; Weave Stage 0 Bootstrap Compiler
; 04_lexer.ll
;
; The lexer converts source bytes into a token stream.
;
; Responsibility:
;
;     source bytes -> tokens
;
; It does not parse syntax. It only recognizes the small token vocabulary needed
; by the Stage 0 bootstrap subset.
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
@weave.kw.block = private unnamed_addr constant [6 x i8] c"block\00"

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
  br i1 %set_yes, label %return_set, label %check_block

check_block:
  %is_block = call i32 @weave_bytes_equal(ptr %text, i64 %length, ptr @weave.kw.block, i64 5)
  %block_yes = icmp ne i32 %is_block, 0
  br i1 %block_yes, label %return_block, label %return_ident

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

return_block:
  ret i32 24

return_ident:
  ret i32 3
}

; ----------------------------------------------------------------------------
; Integer scanning
; ----------------------------------------------------------------------------
;
; Scan a non-negative decimal integer starting at `start`.
; Negative numbers are intentionally represented as unary/binary minus later.
;
; On success, appends TOKEN_INT and returns the index just after the literal.
; On failure, returns -1.


define i64 @weave_lex_integer(ptr %source, ptr %tokens, i64 %start) {
entry:
  %length = call i64 @weave_source_length(ptr %source)
  br label %loop

loop:
  %index = phi i64 [%start, %entry], [%next, %advance]
  %at_end = icmp uge i64 %index, %length
  br i1 %at_end, label %finish, label %read

read:
  %ch = call i32 @weave_source_byte_at(ptr %source, i64 %index)
  %is_digit = call i32 @weave_is_digit(i32 %ch)
  %yes = icmp ne i32 %is_digit, 0
  br i1 %yes, label %advance, label %finish

advance:
  %next = add i64 %index, 1
  br label %loop

finish:
  %token_length = sub i64 %index, %start
  %empty = icmp eq i64 %token_length, 0
  br i1 %empty, label %fail, label %parse_value

parse_value:
  %data = call ptr @weave_source_data(ptr %source)
  %text = getelementptr inbounds i8, ptr %data, i64 %start
  %value = call i32 @atoi(ptr %text)
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 4, i64 %start, i64 %token_length, i32 %value)
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
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 %kind, i64 %start, i64 %token_length, i32 0)
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
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 5, i64 %content_start, i64 %content_length, i32 0)
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
; Single and two-character punctuation/operators
; ----------------------------------------------------------------------------


define i64 @weave_lex_punctuation(ptr %source, ptr %tokens, i64 %index, i32 %ch) {
entry:
  %length = call i64 @weave_source_length(ptr %source)

  %is_lparen = icmp eq i32 %ch, 40
  br i1 %is_lparen, label %push_lparen, label %check_rparen

check_rparen:
  %is_rparen = icmp eq i32 %ch, 41
  br i1 %is_rparen, label %push_rparen, label %check_plus

check_plus:
  %is_plus = icmp eq i32 %ch, 43
  br i1 %is_plus, label %push_plus, label %check_minus

check_minus:
  %is_minus = icmp eq i32 %ch, 45
  br i1 %is_minus, label %push_minus, label %check_star

check_star:
  %is_star = icmp eq i32 %ch, 42
  br i1 %is_star, label %push_star, label %check_slash

check_slash:
  %is_slash = icmp eq i32 %ch, 47
  br i1 %is_slash, label %push_slash, label %check_equal

check_equal:
  %is_equal = icmp eq i32 %ch, 61
  br i1 %is_equal, label %equal_or_eqeq, label %check_bang

check_bang:
  %is_bang = icmp eq i32 %ch, 33
  br i1 %is_bang, label %bang_or_ne, label %check_lt

check_lt:
  %is_lt = icmp eq i32 %ch, 60
  br i1 %is_lt, label %lt_or_le, label %check_gt

check_gt:
  %is_gt = icmp eq i32 %ch, 62
  br i1 %is_gt, label %gt_or_ge, label %fail

push_lparen:
  %s0 = call i32 @weave_tokens_push(ptr %tokens, i32 1, i64 %index, i64 1, i32 0)
  br label %single_done

push_rparen:
  %s1 = call i32 @weave_tokens_push(ptr %tokens, i32 2, i64 %index, i64 1, i32 0)
  br label %single_done

push_plus:
  %s2 = call i32 @weave_tokens_push(ptr %tokens, i32 13, i64 %index, i64 1, i32 0)
  br label %single_done

push_minus:
  %s3 = call i32 @weave_tokens_push(ptr %tokens, i32 14, i64 %index, i64 1, i32 0)
  br label %single_done

push_star:
  %s4 = call i32 @weave_tokens_push(ptr %tokens, i32 15, i64 %index, i64 1, i32 0)
  br label %single_done

push_slash:
  %s5 = call i32 @weave_tokens_push(ptr %tokens, i32 16, i64 %index, i64 1, i32 0)
  br label %single_done

equal_or_eqeq:
  %eq_next_index = add i64 %index, 1
  %eq_has_next = icmp ult i64 %eq_next_index, %length
  br i1 %eq_has_next, label %eq_read_next, label %push_eq

eq_read_next:
  %eq_next_ch = call i32 @weave_source_byte_at(ptr %source, i64 %eq_next_index)
  %eqeq = icmp eq i32 %eq_next_ch, 61
  br i1 %eqeq, label %push_eqeq, label %push_eq

push_eq:
  %s6 = call i32 @weave_tokens_push(ptr %tokens, i32 17, i64 %index, i64 1, i32 0)
  br label %single_done

push_eqeq:
  %s7 = call i32 @weave_tokens_push(ptr %tokens, i32 18, i64 %index, i64 2, i32 0)
  br label %double_done

bang_or_ne:
  %ne_next_index = add i64 %index, 1
  %ne_has_next = icmp ult i64 %ne_next_index, %length
  br i1 %ne_has_next, label %ne_read_next, label %fail

ne_read_next:
  %ne_next_ch = call i32 @weave_source_byte_at(ptr %source, i64 %ne_next_index)
  %is_ne = icmp eq i32 %ne_next_ch, 61
  br i1 %is_ne, label %push_ne, label %fail

push_ne:
  %s8 = call i32 @weave_tokens_push(ptr %tokens, i32 19, i64 %index, i64 2, i32 0)
  br label %double_done

lt_or_le:
  %lt_next_index = add i64 %index, 1
  %lt_has_next = icmp ult i64 %lt_next_index, %length
  br i1 %lt_has_next, label %lt_read_next, label %push_lt

lt_read_next:
  %lt_next_ch = call i32 @weave_source_byte_at(ptr %source, i64 %lt_next_index)
  %is_le = icmp eq i32 %lt_next_ch, 61
  br i1 %is_le, label %push_le, label %push_lt

push_lt:
  %s9 = call i32 @weave_tokens_push(ptr %tokens, i32 20, i64 %index, i64 1, i32 0)
  br label %single_done

push_le:
  %s10 = call i32 @weave_tokens_push(ptr %tokens, i32 21, i64 %index, i64 2, i32 0)
  br label %double_done

gt_or_ge:
  %gt_next_index = add i64 %index, 1
  %gt_has_next = icmp ult i64 %gt_next_index, %length
  br i1 %gt_has_next, label %gt_read_next, label %push_gt

gt_read_next:
  %gt_next_ch = call i32 @weave_source_byte_at(ptr %source, i64 %gt_next_index)
  %is_ge = icmp eq i32 %gt_next_ch, 61
  br i1 %is_ge, label %push_ge, label %push_gt

push_gt:
  %s11 = call i32 @weave_tokens_push(ptr %tokens, i32 22, i64 %index, i64 1, i32 0)
  br label %single_done

push_ge:
  %s12 = call i32 @weave_tokens_push(ptr %tokens, i32 23, i64 %index, i64 2, i32 0)
  br label %double_done

single_done:
  %single_status = phi i32 [%s0, %push_lparen], [%s1, %push_rparen], [%s2, %push_plus], [%s3, %push_minus], [%s4, %push_star], [%s5, %push_slash], [%s6, %push_eq], [%s9, %push_lt], [%s11, %push_gt]
  %single_failed = icmp ne i32 %single_status, 0
  br i1 %single_failed, label %fail, label %single_success

single_success:
  %after_single = add i64 %index, 1
  ret i64 %after_single

double_done:
  %double_status = phi i32 [%s7, %push_eqeq], [%s8, %push_ne], [%s10, %push_le], [%s12, %push_ge]
  %double_failed = icmp ne i32 %double_status, 0
  br i1 %double_failed, label %fail, label %double_success

double_success:
  %after_double = add i64 %index, 2
  ret i64 %after_double

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; weave_lex
;
; Convert a source buffer into a token stream.
;
; Returns:
;   0 on success
;   1 on failure
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
  br i1 %is_digit, label %lex_integer, label %check_string

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
  %status = call i32 @weave_tokens_push(ptr %tokens, i32 0, i64 %length, i64 0, i32 0)
  %eof_failed = icmp ne i32 %status, 0
  br i1 %eof_failed, label %fail, label %success

success:
  ret i32 0

fail:
  ret i32 1
}
