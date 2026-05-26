; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 03_tokens.ll
;
; Token stream storage and accessors for the Stage 0 bootstrap compiler.
;
; Responsibilities:
;   - own the %weave.Tokens struct (kinds / starts / lengths / values arrays
;     plus count / capacity)
;   - init/free token streams and grow capacity on demand
;   - append tokens (push) from the lexer
;   - expose typed accessors so the parser reads tokens without poking at
;     getelementptr offsets directly
;
; Boundary:
;   No lexing rules live here. Token kinds are numeric constants documented
;   in 00_prelude.ll. The lexer (04_lexer.ll) is the only producer; the
;   parser (06_parser.ll) is the only consumer.
; =============================================================================

; ----------------------------------------------------------------------------
; Token stream layout
; ----------------------------------------------------------------------------
;
; %weave.Tokens = type {
;   ptr, ; token kinds    : i32[count]
;   ptr, ; token starts   : i64[count]
;   ptr, ; token lengths  : i64[count]
;   ptr, ; token values   : i32[count]
;   i64, ; count
;   i64  ; capacity
; }
;
; kinds:
;   token kind constants from 00_prelude.ll
;
; starts:
;   byte offset into the source buffer
;
; lengths:
;   byte length of the token text in source
;
; values:
;   integer literal values for TOKEN_INT
;   0 for other token kinds

; ----------------------------------------------------------------------------
; Field access helpers
; ----------------------------------------------------------------------------

define ptr @weave_tokens_kinds_ptr(ptr %tokens) {
entry:
  %field = getelementptr inbounds %weave.Tokens, ptr %tokens, i32 0, i32 0
  ret ptr %field
}

define ptr @weave_tokens_starts_ptr(ptr %tokens) {
entry:
  %field = getelementptr inbounds %weave.Tokens, ptr %tokens, i32 0, i32 1
  ret ptr %field
}

define ptr @weave_tokens_lengths_ptr(ptr %tokens) {
entry:
  %field = getelementptr inbounds %weave.Tokens, ptr %tokens, i32 0, i32 2
  ret ptr %field
}

define ptr @weave_tokens_values_ptr(ptr %tokens) {
entry:
  %field = getelementptr inbounds %weave.Tokens, ptr %tokens, i32 0, i32 3
  ret ptr %field
}

define ptr @weave_tokens_count_ptr(ptr %tokens) {
entry:
  %field = getelementptr inbounds %weave.Tokens, ptr %tokens, i32 0, i32 4
  ret ptr %field
}

define ptr @weave_tokens_capacity_ptr(ptr %tokens) {
entry:
  %field = getelementptr inbounds %weave.Tokens, ptr %tokens, i32 0, i32 5
  ret ptr %field
}

; ----------------------------------------------------------------------------
; Array access helpers
; ----------------------------------------------------------------------------

define ptr @weave_tokens_kinds(ptr %tokens) {
entry:
  %field = call ptr @weave_tokens_kinds_ptr(ptr %tokens)
  %value = load ptr, ptr %field
  ret ptr %value
}

define ptr @weave_tokens_starts(ptr %tokens) {
entry:
  %field = call ptr @weave_tokens_starts_ptr(ptr %tokens)
  %value = load ptr, ptr %field
  ret ptr %value
}

define ptr @weave_tokens_lengths(ptr %tokens) {
entry:
  %field = call ptr @weave_tokens_lengths_ptr(ptr %tokens)
  %value = load ptr, ptr %field
  ret ptr %value
}

define ptr @weave_tokens_values(ptr %tokens) {
entry:
  %field = call ptr @weave_tokens_values_ptr(ptr %tokens)
  %value = load ptr, ptr %field
  ret ptr %value
}

define i64 @weave_tokens_count(ptr %tokens) {
entry:
  %field = call ptr @weave_tokens_count_ptr(ptr %tokens)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_tokens_capacity(ptr %tokens) {
entry:
  %field = call ptr @weave_tokens_capacity_ptr(ptr %tokens)
  %value = load i64, ptr %field
  ret i64 %value
}

; ----------------------------------------------------------------------------
; weave_tokens_init
;
; Initialize an empty token stream.
;
; Returns:
;   0 on success
;   1 on allocation failure
; ----------------------------------------------------------------------------

define i32 @weave_tokens_init(ptr %tokens) {
entry:
  %capacity = add i64 256, 0

  %kinds_bytes = mul i64 %capacity, 4
  %starts_bytes = mul i64 %capacity, 8
  %lengths_bytes = mul i64 %capacity, 8
  ; Values are stored as i64 so const_i64 literals survive the lexer without
  ; being silently truncated (atoll → i64 → tokens.values → parser).
  %values_bytes = mul i64 %capacity, 8

  %kinds = call ptr @malloc(i64 %kinds_bytes)
  %starts = call ptr @malloc(i64 %starts_bytes)
  %lengths = call ptr @malloc(i64 %lengths_bytes)
  %values = call ptr @malloc(i64 %values_bytes)

  %kinds_null = icmp eq ptr %kinds, null
  %starts_null = icmp eq ptr %starts, null
  %lengths_null = icmp eq ptr %lengths, null
  %values_null = icmp eq ptr %values, null

  %bad1 = or i1 %kinds_null, %starts_null
  %bad2 = or i1 %lengths_null, %values_null
  %failed = or i1 %bad1, %bad2

  br i1 %failed, label %cleanup, label %store

cleanup:
  %kinds_ok = icmp ne ptr %kinds, null
  br i1 %kinds_ok, label %free_kinds, label %check_starts

free_kinds:
  call void @free(ptr %kinds)
  br label %check_starts

check_starts:
  %starts_ok = icmp ne ptr %starts, null
  br i1 %starts_ok, label %free_starts, label %check_lengths

free_starts:
  call void @free(ptr %starts)
  br label %check_lengths

check_lengths:
  %lengths_ok = icmp ne ptr %lengths, null
  br i1 %lengths_ok, label %free_lengths, label %check_values

free_lengths:
  call void @free(ptr %lengths)
  br label %check_values

check_values:
  %values_ok = icmp ne ptr %values, null
  br i1 %values_ok, label %free_values, label %fail

free_values:
  call void @free(ptr %values)
  br label %fail

fail:
  ret i32 1

store:
  %kinds_field = call ptr @weave_tokens_kinds_ptr(ptr %tokens)
  %starts_field = call ptr @weave_tokens_starts_ptr(ptr %tokens)
  %lengths_field = call ptr @weave_tokens_lengths_ptr(ptr %tokens)
  %values_field = call ptr @weave_tokens_values_ptr(ptr %tokens)
  %count_field = call ptr @weave_tokens_count_ptr(ptr %tokens)
  %capacity_field = call ptr @weave_tokens_capacity_ptr(ptr %tokens)

  store ptr %kinds, ptr %kinds_field
  store ptr %starts, ptr %starts_field
  store ptr %lengths, ptr %lengths_field
  store ptr %values, ptr %values_field
  store i64 0, ptr %count_field
  store i64 %capacity, ptr %capacity_field

  ret i32 0
}

; ----------------------------------------------------------------------------
; weave_tokens_free
; ----------------------------------------------------------------------------

define void @weave_tokens_free(ptr %tokens) {
entry:
  %kinds = call ptr @weave_tokens_kinds(ptr %tokens)
  %starts = call ptr @weave_tokens_starts(ptr %tokens)
  %lengths = call ptr @weave_tokens_lengths(ptr %tokens)
  %values = call ptr @weave_tokens_values(ptr %tokens)

  %kinds_ok = icmp ne ptr %kinds, null
  br i1 %kinds_ok, label %free_kinds, label %check_starts

free_kinds:
  call void @free(ptr %kinds)
  br label %check_starts

check_starts:
  %starts_ok = icmp ne ptr %starts, null
  br i1 %starts_ok, label %free_starts, label %check_lengths

free_starts:
  call void @free(ptr %starts)
  br label %check_lengths

check_lengths:
  %lengths_ok = icmp ne ptr %lengths, null
  br i1 %lengths_ok, label %free_lengths, label %check_values

free_lengths:
  call void @free(ptr %lengths)
  br label %check_values

check_values:
  %values_ok = icmp ne ptr %values, null
  br i1 %values_ok, label %free_values, label %done

free_values:
  call void @free(ptr %values)
  br label %done

done:
  %kinds_field = call ptr @weave_tokens_kinds_ptr(ptr %tokens)
  %starts_field = call ptr @weave_tokens_starts_ptr(ptr %tokens)
  %lengths_field = call ptr @weave_tokens_lengths_ptr(ptr %tokens)
  %values_field = call ptr @weave_tokens_values_ptr(ptr %tokens)
  %count_field = call ptr @weave_tokens_count_ptr(ptr %tokens)
  %capacity_field = call ptr @weave_tokens_capacity_ptr(ptr %tokens)

  store ptr null, ptr %kinds_field
  store ptr null, ptr %starts_field
  store ptr null, ptr %lengths_field
  store ptr null, ptr %values_field
  store i64 0, ptr %count_field
  store i64 0, ptr %capacity_field

  ret void
}

; ----------------------------------------------------------------------------
; weave_tokens_reserve
; ----------------------------------------------------------------------------

define i32 @weave_tokens_reserve(ptr %tokens, i64 %needed) {
entry:
  %capacity = call i64 @weave_tokens_capacity(ptr %tokens)
  %enough = icmp ule i64 %needed, %capacity
  br i1 %enough, label %success, label %grow_start

grow_start:
  br label %grow_loop

grow_loop:
  %current = phi i64 [%capacity, %grow_start], [%next, %grow_more]
  %still_small = icmp ult i64 %current, %needed
  br i1 %still_small, label %grow_more, label %reallocate

grow_more:
  %next = mul i64 %current, 2
  br label %grow_loop

reallocate:
  %kinds_old = call ptr @weave_tokens_kinds(ptr %tokens)
  %starts_old = call ptr @weave_tokens_starts(ptr %tokens)
  %lengths_old = call ptr @weave_tokens_lengths(ptr %tokens)
  %values_old = call ptr @weave_tokens_values(ptr %tokens)

  %kinds_bytes = mul i64 %current, 4
  %starts_bytes = mul i64 %current, 8
  %lengths_bytes = mul i64 %current, 8
  %values_bytes = mul i64 %current, 8

  %kinds_new = call ptr @realloc(ptr %kinds_old, i64 %kinds_bytes)
  %starts_new = call ptr @realloc(ptr %starts_old, i64 %starts_bytes)
  %lengths_new = call ptr @realloc(ptr %lengths_old, i64 %lengths_bytes)
  %values_new = call ptr @realloc(ptr %values_old, i64 %values_bytes)

  %kinds_failed = icmp eq ptr %kinds_new, null
  %starts_failed = icmp eq ptr %starts_new, null
  %lengths_failed = icmp eq ptr %lengths_new, null
  %values_failed = icmp eq ptr %values_new, null
  %bad1 = or i1 %kinds_failed, %starts_failed
  %bad2 = or i1 %lengths_failed, %values_failed
  %failed = or i1 %bad1, %bad2

  br i1 %failed, label %fail, label %store

store:
  %kinds_field = call ptr @weave_tokens_kinds_ptr(ptr %tokens)
  %starts_field = call ptr @weave_tokens_starts_ptr(ptr %tokens)
  %lengths_field = call ptr @weave_tokens_lengths_ptr(ptr %tokens)
  %values_field = call ptr @weave_tokens_values_ptr(ptr %tokens)
  %capacity_field = call ptr @weave_tokens_capacity_ptr(ptr %tokens)

  store ptr %kinds_new, ptr %kinds_field
  store ptr %starts_new, ptr %starts_field
  store ptr %lengths_new, ptr %lengths_field
  store ptr %values_new, ptr %values_field
  store i64 %current, ptr %capacity_field

  br label %success

success:
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_tokens_push
;
; Append one token into the stream.
;
; Returns:
;   0 on success
;   1 on allocation failure
; ----------------------------------------------------------------------------

define i32 @weave_tokens_push(
  ptr %tokens,
  i32 %kind,
  i64 %start,
  i64 %length,
  i64 %value
) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %needed = add i64 %count, 1

  %reserve_status = call i32 @weave_tokens_reserve(ptr %tokens, i64 %needed)
  %reserve_failed = icmp ne i32 %reserve_status, 0

  br i1 %reserve_failed, label %fail, label %store

store:
  %kinds = call ptr @weave_tokens_kinds(ptr %tokens)
  %starts = call ptr @weave_tokens_starts(ptr %tokens)
  %lengths = call ptr @weave_tokens_lengths(ptr %tokens)
  %values = call ptr @weave_tokens_values(ptr %tokens)

  %kind_ptr = getelementptr inbounds i32, ptr %kinds, i64 %count
  %start_ptr = getelementptr inbounds i64, ptr %starts, i64 %count
  %length_ptr = getelementptr inbounds i64, ptr %lengths, i64 %count
  %value_ptr = getelementptr inbounds i64, ptr %values, i64 %count

  store i32 %kind, ptr %kind_ptr
  store i64 %start, ptr %start_ptr
  store i64 %length, ptr %length_ptr
  store i64 %value, ptr %value_ptr

  %count_field = call ptr @weave_tokens_count_ptr(ptr %tokens)
  store i64 %needed, ptr %count_field

  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; Token access helpers
; ----------------------------------------------------------------------------

define i32 @weave_token_kind(ptr %tokens, i64 %index) {
entry:
  %kinds = call ptr @weave_tokens_kinds(ptr %tokens)
  %slot = getelementptr inbounds i32, ptr %kinds, i64 %index
  %value = load i32, ptr %slot
  ret i32 %value
}

define i64 @weave_token_start(ptr %tokens, i64 %index) {
entry:
  %starts = call ptr @weave_tokens_starts(ptr %tokens)
  %slot = getelementptr inbounds i64, ptr %starts, i64 %index
  %value = load i64, ptr %slot
  ret i64 %value
}

define i64 @weave_token_length(ptr %tokens, i64 %index) {
entry:
  %lengths = call ptr @weave_tokens_lengths(ptr %tokens)
  %slot = getelementptr inbounds i64, ptr %lengths, i64 %index
  %value = load i64, ptr %slot
  ret i64 %value
}

define i64 @weave_token_value(ptr %tokens, i64 %index) {
entry:
  %values = call ptr @weave_tokens_values(ptr %tokens)
  %slot = getelementptr inbounds i64, ptr %values, i64 %index
  %value = load i64, ptr %slot
  ret i64 %value
}
