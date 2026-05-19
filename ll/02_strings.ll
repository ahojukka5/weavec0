; =============================================================================
; Weave Stage 0 Bootstrap Compiler
; 02_strings.ll
;
; Small string and byte-buffer helpers used by the lexer, parser, and LLVM
; emitter.
;
; This is not a standard library. It is only the tiny text-handling layer needed
; by the Stage 0 bridge.
; =============================================================================

; ----------------------------------------------------------------------------
; Buffer layout
; ----------------------------------------------------------------------------
;
; %weave.Buffer = type { ptr, i64, i64 }
;
; field 0 : data pointer
; field 1 : length
; field 2 : capacity
;
; A buffer owns its data pointer. The data is always kept null-terminated when
; possible, so it can be passed to C helpers for debugging or writing.

; ----------------------------------------------------------------------------
; Buffer field access helpers
; ----------------------------------------------------------------------------

define ptr @weave_buffer_data_ptr(ptr %buffer) {
entry:
  %field = getelementptr inbounds %weave.Buffer, ptr %buffer, i32 0, i32 0
  ret ptr %field
}

define ptr @weave_buffer_length_ptr(ptr %buffer) {
entry:
  %field = getelementptr inbounds %weave.Buffer, ptr %buffer, i32 0, i32 1
  ret ptr %field
}

define ptr @weave_buffer_capacity_ptr(ptr %buffer) {
entry:
  %field = getelementptr inbounds %weave.Buffer, ptr %buffer, i32 0, i32 2
  ret ptr %field
}

define ptr @weave_buffer_data(ptr %buffer) {
entry:
  %field = call ptr @weave_buffer_data_ptr(ptr %buffer)
  %data = load ptr, ptr %field
  ret ptr %data
}

define i64 @weave_buffer_length(ptr %buffer) {
entry:
  %field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  %length = load i64, ptr %field
  ret i64 %length
}

define i64 @weave_buffer_capacity(ptr %buffer) {
entry:
  %field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)
  %capacity = load i64, ptr %field
  ret i64 %capacity
}

; ----------------------------------------------------------------------------
; weave_buffer_init
;
; Initialize an empty buffer.
;
; Returns:
;   0 on success
;   1 on allocation failure
; ----------------------------------------------------------------------------

define i32 @weave_buffer_init(ptr %buffer) {
entry:
  %data_field = call ptr @weave_buffer_data_ptr(ptr %buffer)
  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  %capacity_field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)

  %initial_capacity = add i64 256, 0
  %data = call ptr @malloc(i64 %initial_capacity)
  %is_null = icmp eq ptr %data, null
  br i1 %is_null, label %fail, label %ok

ok:
  store ptr %data, ptr %data_field
  store i64 0, ptr %length_field
  store i64 %initial_capacity, ptr %capacity_field
  store i8 0, ptr %data
  ret i32 0

fail:
  store ptr null, ptr %data_field
  store i64 0, ptr %length_field
  store i64 0, ptr %capacity_field
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_buffer_free
;
; Release owned memory and reset the buffer to an empty state.
; ----------------------------------------------------------------------------

define void @weave_buffer_free(ptr %buffer) {
entry:
  %data_field = call ptr @weave_buffer_data_ptr(ptr %buffer)
  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  %capacity_field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)

  %data = load ptr, ptr %data_field
  %has_data = icmp ne ptr %data, null
  br i1 %has_data, label %free_data, label %done

free_data:
  call void @free(ptr %data)
  br label %done

done:
  store ptr null, ptr %data_field
  store i64 0, ptr %length_field
  store i64 0, ptr %capacity_field
  ret void
}

; ----------------------------------------------------------------------------
; weave_buffer_reserve
;
; Ensure that the buffer can hold at least `needed` bytes, including the final
; null terminator.
;
; Returns:
;   0 on success
;   1 on allocation failure
; ----------------------------------------------------------------------------

define i32 @weave_buffer_reserve(ptr %buffer, i64 %needed) {
entry:
  %capacity = call i64 @weave_buffer_capacity(ptr %buffer)
  %enough = icmp ule i64 %needed, %capacity
  br i1 %enough, label %success, label %grow_start

grow_start:
  %old_data = call ptr @weave_buffer_data(ptr %buffer)
  %old_capacity = call i64 @weave_buffer_capacity(ptr %buffer)
  %is_zero = icmp eq i64 %old_capacity, 0
  br i1 %is_zero, label %from_empty, label %double_loop

from_empty:
  br label %grow_loop

double_loop:
  br label %grow_loop

grow_loop:
  %capacity_phi = phi i64 [256, %from_empty], [%old_capacity, %double_loop], [%next_capacity, %grow_more]
  %still_small = icmp ult i64 %capacity_phi, %needed
  br i1 %still_small, label %grow_more, label %allocate

grow_more:
  %next_capacity = mul i64 %capacity_phi, 2
  br label %grow_loop

allocate:
  %new_data = call ptr @realloc(ptr %old_data, i64 %capacity_phi)
  %failed = icmp eq ptr %new_data, null
  br i1 %failed, label %fail, label %store_new

store_new:
  %data_field = call ptr @weave_buffer_data_ptr(ptr %buffer)
  %capacity_field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)
  store ptr %new_data, ptr %data_field
  store i64 %capacity_phi, ptr %capacity_field
  br label %success

success:
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_buffer_append_byte
;
; Append one byte and preserve null termination.
; ----------------------------------------------------------------------------

define i32 @weave_buffer_append_byte(ptr %buffer, i32 %byte_value) {
entry:
  %length = call i64 @weave_buffer_length(ptr %buffer)
  %needed_without_null = add i64 %length, 1
  %needed = add i64 %needed_without_null, 1
  %reserve_status = call i32 @weave_buffer_reserve(ptr %buffer, i64 %needed)
  %reserve_failed = icmp ne i32 %reserve_status, 0
  br i1 %reserve_failed, label %fail, label %append

append:
  %data = call ptr @weave_buffer_data(ptr %buffer)
  %byte_ptr = getelementptr inbounds i8, ptr %data, i64 %length
  %truncated = trunc i32 %byte_value to i8
  store i8 %truncated, ptr %byte_ptr

  %new_length = add i64 %length, 1
  %null_ptr = getelementptr inbounds i8, ptr %data, i64 %new_length
  store i8 0, ptr %null_ptr

  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  store i64 %new_length, ptr %length_field
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_buffer_append_bytes
;
; Append `length` bytes from `src` and preserve null termination.
; ----------------------------------------------------------------------------

define i32 @weave_buffer_append_bytes(ptr %buffer, ptr %src, i64 %length) {
entry:
  %src_is_null = icmp eq ptr %src, null
  %length_is_zero = icmp eq i64 %length, 0
  %length_is_nonzero = xor i1 %length_is_zero, true
  %invalid = and i1 %src_is_null, %length_is_nonzero
  br i1 %invalid, label %fail, label %reserve

reserve:
  %old_length = call i64 @weave_buffer_length(ptr %buffer)
  %new_length = add i64 %old_length, %length
  %needed = add i64 %new_length, 1
  %reserve_status = call i32 @weave_buffer_reserve(ptr %buffer, i64 %needed)
  %reserve_failed = icmp ne i32 %reserve_status, 0
  br i1 %reserve_failed, label %fail, label %copy_or_finish

copy_or_finish:
  %zero = icmp eq i64 %length, 0
  br i1 %zero, label %terminate, label %copy

copy:
  %data = call ptr @weave_buffer_data(ptr %buffer)
  %dst = getelementptr inbounds i8, ptr %data, i64 %old_length
  call ptr @memcpy(ptr %dst, ptr %src, i64 %length)
  br label %terminate

terminate:
  %data2 = call ptr @weave_buffer_data(ptr %buffer)
  %null_ptr = getelementptr inbounds i8, ptr %data2, i64 %new_length
  store i8 0, ptr %null_ptr

  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  store i64 %new_length, ptr %length_field
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_buffer_append_cstr
;
; Append a null-terminated byte string.
; ----------------------------------------------------------------------------

define i32 @weave_buffer_append_cstr(ptr %buffer, ptr %text) {
entry:
  %is_null = icmp eq ptr %text, null
  br i1 %is_null, label %fail, label %append

append:
  %length = call i64 @strlen(ptr %text)
  %status = call i32 @weave_buffer_append_bytes(ptr %buffer, ptr %text, i64 %length)
  ret i32 %status

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_buffer_append_i32
;
; Append a signed i32 as decimal text.
; ----------------------------------------------------------------------------

define i32 @weave_buffer_append_i32(ptr %buffer, i32 %value) {
entry:
  %is_negative = icmp slt i32 %value, 0
  br i1 %is_negative, label %negative, label %nonnegative

negative:
  %dash_status = call i32 @weave_buffer_append_byte(ptr %buffer, i32 45)
  %dash_failed = icmp ne i32 %dash_status, 0
  br i1 %dash_failed, label %fail, label %negate

negate:
  %positive = sub i32 0, %value
  br label %digits_start

nonnegative:
  br label %digits_start

digits_start:
  %number = phi i32 [%positive, %negate], [%value, %nonnegative]
  %less_than_ten = icmp slt i32 %number, 10
  br i1 %less_than_ten, label %single_digit, label %many_digits

many_digits:
  %prefix = sdiv i32 %number, 10
  %prefix_status = call i32 @weave_buffer_append_i32(ptr %buffer, i32 %prefix)
  %prefix_failed = icmp ne i32 %prefix_status, 0
  br i1 %prefix_failed, label %fail, label %last_digit

last_digit:
  %remainder = srem i32 %number, 10
  br label %emit_digit

single_digit:
  br label %emit_digit

emit_digit:
  %digit = phi i32 [%number, %single_digit], [%remainder, %last_digit]
  %ascii = add i32 %digit, 48
  %status = call i32 @weave_buffer_append_byte(ptr %buffer, i32 %ascii)
  ret i32 %status

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_bytes_equal
;
; Return i32 1 if two byte slices are equal, otherwise i32 0.
; ----------------------------------------------------------------------------

define i32 @weave_bytes_equal(ptr %a, i64 %a_len, ptr %b, i64 %b_len) {
entry:
  %same_length = icmp eq i64 %a_len, %b_len
  br i1 %same_length, label %check_nulls, label %not_equal

check_nulls:
  %a_null = icmp eq ptr %a, null
  %b_null = icmp eq ptr %b, null
  %any_null = or i1 %a_null, %b_null
  br i1 %any_null, label %null_case, label %compare

null_case:
  %both_null = and i1 %a_null, %b_null
  br i1 %both_null, label %equal, label %not_equal

compare:
  %cmp = call i32 @strncmp(ptr %a, ptr %b, i64 %a_len)
  %is_equal = icmp eq i32 %cmp, 0
  br i1 %is_equal, label %equal, label %not_equal

equal:
  ret i32 1

not_equal:
  ret i32 0
}

; ----------------------------------------------------------------------------
; weave_slice_starts_with_cstr
;
; Return i32 1 if the source slice starts with the null-terminated pattern.
; ----------------------------------------------------------------------------

define i32 @weave_slice_starts_with_cstr(ptr %src, i64 %src_len, ptr %pattern) {
entry:
  %pattern_null = icmp eq ptr %pattern, null
  br i1 %pattern_null, label %no, label %have_pattern

have_pattern:
  %pattern_len = call i64 @strlen(ptr %pattern)
  %too_short = icmp ult i64 %src_len, %pattern_len
  br i1 %too_short, label %no, label %compare

compare:
  %cmp = call i32 @strncmp(ptr %src, ptr %pattern, i64 %pattern_len)
  %matches = icmp eq i32 %cmp, 0
  br i1 %matches, label %yes, label %no

yes:
  ret i32 1

no:
  ret i32 0
}
