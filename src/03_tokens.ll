; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 03_tokens.ll
;
; Parallel-array token storage for the Stage 0 compiler. Growth is transactional:
; all replacement arrays are allocated and populated before the live token
; stream is changed.
; =============================================================================

; %weave.Tokens = type { ptr, ptr, ptr, ptr, i64, i64 }
; kinds   : i32[count]
; starts  : i64[count]
; lengths : i64[count]
; values  : i64[count]

; ----------------------------------------------------------------------------
; Field and value helpers
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
; Ownership
; ----------------------------------------------------------------------------

define i32 @weave_tokens_init(ptr %tokens) {
entry:
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

  %kinds = call ptr @malloc(i64 1024)
  %starts = call ptr @malloc(i64 2048)
  %lengths = call ptr @malloc(i64 2048)
  %values = call ptr @malloc(i64 2048)
  %kinds_null = icmp eq ptr %kinds, null
  %starts_null = icmp eq ptr %starts, null
  %lengths_null = icmp eq ptr %lengths, null
  %values_null = icmp eq ptr %values, null
  %bad1 = or i1 %kinds_null, %starts_null
  %bad2 = or i1 %lengths_null, %values_null
  %failed = or i1 %bad1, %bad2
  br i1 %failed, label %cleanup_kinds, label %store

cleanup_kinds:
  %has_kinds = icmp ne ptr %kinds, null
  br i1 %has_kinds, label %free_kinds, label %cleanup_starts

free_kinds:
  call void @free(ptr %kinds)
  br label %cleanup_starts

cleanup_starts:
  %has_starts = icmp ne ptr %starts, null
  br i1 %has_starts, label %free_starts, label %cleanup_lengths

free_starts:
  call void @free(ptr %starts)
  br label %cleanup_lengths

cleanup_lengths:
  %has_lengths = icmp ne ptr %lengths, null
  br i1 %has_lengths, label %free_lengths, label %cleanup_values

free_lengths:
  call void @free(ptr %lengths)
  br label %cleanup_values

cleanup_values:
  %has_values = icmp ne ptr %values, null
  br i1 %has_values, label %free_values, label %fail

free_values:
  call void @free(ptr %values)
  br label %fail

store:
  store ptr %kinds, ptr %kinds_field
  store ptr %starts, ptr %starts_field
  store ptr %lengths, ptr %lengths_field
  store ptr %values, ptr %values_field
  store i64 256, ptr %capacity_field
  ret i32 0

fail:
  ret i32 1
}

define void @weave_tokens_free(ptr %tokens) {
entry:
  %kinds = call ptr @weave_tokens_kinds(ptr %tokens)
  %starts = call ptr @weave_tokens_starts(ptr %tokens)
  %lengths = call ptr @weave_tokens_lengths(ptr %tokens)
  %values = call ptr @weave_tokens_values(ptr %tokens)
  %has_kinds = icmp ne ptr %kinds, null
  br i1 %has_kinds, label %free_kinds, label %check_starts

free_kinds:
  call void @free(ptr %kinds)
  br label %check_starts

check_starts:
  %has_starts = icmp ne ptr %starts, null
  br i1 %has_starts, label %free_starts, label %check_lengths

free_starts:
  call void @free(ptr %starts)
  br label %check_lengths

check_lengths:
  %has_lengths = icmp ne ptr %lengths, null
  br i1 %has_lengths, label %free_lengths, label %check_values

free_lengths:
  call void @free(ptr %lengths)
  br label %check_values

check_values:
  %has_values = icmp ne ptr %values, null
  br i1 %has_values, label %free_values, label %reset

free_values:
  call void @free(ptr %values)
  br label %reset

reset:
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
; Transactional growth
; ----------------------------------------------------------------------------

define i32 @weave_tokens_reserve(ptr %tokens, i64 %needed) {
entry:
  %capacity = call i64 @weave_tokens_capacity(ptr %tokens)
  %enough = icmp ule i64 %needed, %capacity
  br i1 %enough, label %success, label %choose_start

choose_start:
  %empty = icmp eq i64 %capacity, 0
  %start = select i1 %empty, i64 256, i64 %capacity
  br label %grow

grow:
  %current = phi i64 [%start, %choose_start], [%next, %grow_more]
  %large_enough = icmp uge i64 %current, %needed
  br i1 %large_enough, label %check_sizes, label %check_double

check_double:
  %double_overflow = icmp ugt i64 %current, 9223372036854775807
  br i1 %double_overflow, label %fail, label %grow_more

grow_more:
  %next = mul i64 %current, 2
  br label %grow

check_sizes:
  %too_large = icmp ugt i64 %current, 2305843009213693951
  br i1 %too_large, label %fail, label %allocate

allocate:
  %kinds_bytes = mul i64 %current, 4
  %wide_bytes = mul i64 %current, 8
  %kinds_new = call ptr @malloc(i64 %kinds_bytes)
  %starts_new = call ptr @malloc(i64 %wide_bytes)
  %lengths_new = call ptr @malloc(i64 %wide_bytes)
  %values_new = call ptr @malloc(i64 %wide_bytes)
  %kinds_null = icmp eq ptr %kinds_new, null
  %starts_null = icmp eq ptr %starts_new, null
  %lengths_null = icmp eq ptr %lengths_new, null
  %values_null = icmp eq ptr %values_new, null
  %bad1 = or i1 %kinds_null, %starts_null
  %bad2 = or i1 %lengths_null, %values_null
  %allocation_failed = or i1 %bad1, %bad2
  br i1 %allocation_failed, label %cleanup_new_kinds, label %copy_or_commit

copy_or_commit:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %has_items = icmp ne i64 %count, 0
  br i1 %has_items, label %copy, label %commit

copy:
  %kinds_old = call ptr @weave_tokens_kinds(ptr %tokens)
  %starts_old = call ptr @weave_tokens_starts(ptr %tokens)
  %lengths_old = call ptr @weave_tokens_lengths(ptr %tokens)
  %values_old = call ptr @weave_tokens_values(ptr %tokens)
  %kinds_copy_bytes = mul i64 %count, 4
  %wide_copy_bytes = mul i64 %count, 8
  call ptr @memcpy(ptr %kinds_new, ptr %kinds_old, i64 %kinds_copy_bytes)
  call ptr @memcpy(ptr %starts_new, ptr %starts_old, i64 %wide_copy_bytes)
  call ptr @memcpy(ptr %lengths_new, ptr %lengths_old, i64 %wide_copy_bytes)
  call ptr @memcpy(ptr %values_new, ptr %values_old, i64 %wide_copy_bytes)
  br label %commit

commit:
  %old_kinds = call ptr @weave_tokens_kinds(ptr %tokens)
  %old_starts = call ptr @weave_tokens_starts(ptr %tokens)
  %old_lengths = call ptr @weave_tokens_lengths(ptr %tokens)
  %old_values = call ptr @weave_tokens_values(ptr %tokens)
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
  call void @free(ptr %old_kinds)
  call void @free(ptr %old_starts)
  call void @free(ptr %old_lengths)
  call void @free(ptr %old_values)
  ret i32 0

cleanup_new_kinds:
  %has_new_kinds = icmp ne ptr %kinds_new, null
  br i1 %has_new_kinds, label %free_new_kinds, label %cleanup_new_starts

free_new_kinds:
  call void @free(ptr %kinds_new)
  br label %cleanup_new_starts

cleanup_new_starts:
  %has_new_starts = icmp ne ptr %starts_new, null
  br i1 %has_new_starts, label %free_new_starts, label %cleanup_new_lengths

free_new_starts:
  call void @free(ptr %starts_new)
  br label %cleanup_new_lengths

cleanup_new_lengths:
  %has_new_lengths = icmp ne ptr %lengths_new, null
  br i1 %has_new_lengths, label %free_new_lengths, label %cleanup_new_values

free_new_lengths:
  call void @free(ptr %lengths_new)
  br label %cleanup_new_values

cleanup_new_values:
  %has_new_values = icmp ne ptr %values_new, null
  br i1 %has_new_values, label %free_new_values, label %fail

free_new_values:
  call void @free(ptr %values_new)
  br label %fail

success:
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; Append and access
; ----------------------------------------------------------------------------

define i32 @weave_tokens_push(ptr %tokens, i32 %kind, i64 %start, i64 %length, i64 %value) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %needed = add i64 %count, 1
  %overflow = icmp ult i64 %needed, %count
  br i1 %overflow, label %fail, label %reserve

reserve:
  %status = call i32 @weave_tokens_reserve(ptr %tokens, i64 %needed)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %store

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

define i32 @weave_token_kind(ptr %tokens, i64 %index) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %in_range = icmp ult i64 %index, %count
  br i1 %in_range, label %load_value, label %out_of_range

load_value:
  %array = call ptr @weave_tokens_kinds(ptr %tokens)
  %slot = getelementptr inbounds i32, ptr %array, i64 %index
  %value = load i32, ptr %slot
  ret i32 %value

out_of_range:
  ; Treat any lookahead beyond the stream as EOF.
  ret i32 0
}

define i64 @weave_token_start(ptr %tokens, i64 %index) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %in_range = icmp ult i64 %index, %count
  br i1 %in_range, label %load_value, label %out_of_range

load_value:
  %array = call ptr @weave_tokens_starts(ptr %tokens)
  %slot = getelementptr inbounds i64, ptr %array, i64 %index
  %value = load i64, ptr %slot
  ret i64 %value

out_of_range:
  ret i64 0
}

define i64 @weave_token_length(ptr %tokens, i64 %index) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %in_range = icmp ult i64 %index, %count
  br i1 %in_range, label %load_value, label %out_of_range

load_value:
  %array = call ptr @weave_tokens_lengths(ptr %tokens)
  %slot = getelementptr inbounds i64, ptr %array, i64 %index
  %value = load i64, ptr %slot
  ret i64 %value

out_of_range:
  ret i64 0
}

define i64 @weave_token_value(ptr %tokens, i64 %index) {
entry:
  %count = call i64 @weave_tokens_count(ptr %tokens)
  %in_range = icmp ult i64 %index, %count
  br i1 %in_range, label %load_value, label %out_of_range

load_value:
  %array = call ptr @weave_tokens_values(ptr %tokens)
  %slot = getelementptr inbounds i64, ptr %array, i64 %index
  %value = load i64, ptr %slot
  ret i64 %value

out_of_range:
  ret i64 0
}
