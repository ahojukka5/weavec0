; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 02_strings.ll
;
; Growable byte buffers, integer formatting, and byte-slice comparisons used
; by the Stage 0 lexer, parser, and LLVM emitter.
; =============================================================================

; %weave.Buffer = type { ptr, i64, i64 }

; ----------------------------------------------------------------------------
; Buffer field helpers
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
  %value = load ptr, ptr %field
  ret ptr %value
}

define i64 @weave_buffer_length(ptr %buffer) {
entry:
  %field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_buffer_capacity(ptr %buffer) {
entry:
  %field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)
  %value = load i64, ptr %field
  ret i64 %value
}

; ----------------------------------------------------------------------------
; Buffer ownership and growth
; ----------------------------------------------------------------------------

define i32 @weave_buffer_init(ptr %buffer) {
entry:
  %data_field = call ptr @weave_buffer_data_ptr(ptr %buffer)
  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  %capacity_field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)
  store ptr null, ptr %data_field
  store i64 0, ptr %length_field
  store i64 0, ptr %capacity_field

  %data = call ptr @malloc(i64 256)
  %failed = icmp eq ptr %data, null
  br i1 %failed, label %fail, label %store

store:
  store ptr %data, ptr %data_field
  store i64 256, ptr %capacity_field
  store i8 0, ptr %data
  ret i32 0

fail:
  ret i32 1
}

define void @weave_buffer_free(ptr %buffer) {
entry:
  %data_field = call ptr @weave_buffer_data_ptr(ptr %buffer)
  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  %capacity_field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)
  %data = load ptr, ptr %data_field
  %has_data = icmp ne ptr %data, null
  br i1 %has_data, label %release, label %reset

release:
  call void @free(ptr %data)
  br label %reset

reset:
  store ptr null, ptr %data_field
  store i64 0, ptr %length_field
  store i64 0, ptr %capacity_field
  ret void
}

define i32 @weave_buffer_reserve(ptr %buffer, i64 %needed) {
entry:
  %capacity = call i64 @weave_buffer_capacity(ptr %buffer)
  %enough = icmp ule i64 %needed, %capacity
  br i1 %enough, label %success, label %choose_start

choose_start:
  %is_empty = icmp eq i64 %capacity, 0
  %start = select i1 %is_empty, i64 256, i64 %capacity
  br label %grow

grow:
  %current = phi i64 [%start, %choose_start], [%next, %grow_more]
  %large_enough = icmp uge i64 %current, %needed
  br i1 %large_enough, label %allocate, label %check_double

check_double:
  %would_overflow = icmp ugt i64 %current, 9223372036854775807
  br i1 %would_overflow, label %fail, label %grow_more

grow_more:
  %next = mul i64 %current, 2
  br label %grow

allocate:
  %old_data = call ptr @weave_buffer_data(ptr %buffer)
  %new_data = call ptr @realloc(ptr %old_data, i64 %current)
  %failed = icmp eq ptr %new_data, null
  br i1 %failed, label %fail, label %store

store:
  %data_field = call ptr @weave_buffer_data_ptr(ptr %buffer)
  %capacity_field = call ptr @weave_buffer_capacity_ptr(ptr %buffer)
  store ptr %new_data, ptr %data_field
  store i64 %current, ptr %capacity_field
  ret i32 0

success:
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; Buffer append operations
; ----------------------------------------------------------------------------

define i32 @weave_buffer_append_byte(ptr %buffer, i32 %byte_value) {
entry:
  %length = call i64 @weave_buffer_length(ptr %buffer)
  %needed_without_null = add i64 %length, 1
  %overflow1 = icmp ult i64 %needed_without_null, %length
  br i1 %overflow1, label %fail, label %compute_needed

compute_needed:
  %needed = add i64 %needed_without_null, 1
  %overflow2 = icmp ult i64 %needed, %needed_without_null
  br i1 %overflow2, label %fail, label %reserve

reserve:
  %status = call i32 @weave_buffer_reserve(ptr %buffer, i64 %needed)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %append

append:
  %data = call ptr @weave_buffer_data(ptr %buffer)
  %slot = getelementptr inbounds i8, ptr %data, i64 %length
  %byte = trunc i32 %byte_value to i8
  store i8 %byte, ptr %slot
  %new_length = add i64 %length, 1
  %terminator = getelementptr inbounds i8, ptr %data, i64 %new_length
  store i8 0, ptr %terminator
  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  store i64 %new_length, ptr %length_field
  ret i32 0

fail:
  ret i32 1
}

define i32 @weave_buffer_append_bytes(ptr %buffer, ptr %src, i64 %length) {
entry:
  %src_null = icmp eq ptr %src, null
  %nonempty = icmp ne i64 %length, 0
  %invalid = and i1 %src_null, %nonempty
  br i1 %invalid, label %fail, label %compute_length

compute_length:
  %old_length = call i64 @weave_buffer_length(ptr %buffer)
  %new_length = add i64 %old_length, %length
  %overflow1 = icmp ult i64 %new_length, %old_length
  br i1 %overflow1, label %fail, label %compute_needed

compute_needed:
  %needed = add i64 %new_length, 1
  %overflow2 = icmp ult i64 %needed, %new_length
  br i1 %overflow2, label %fail, label %reserve

reserve:
  %status = call i32 @weave_buffer_reserve(ptr %buffer, i64 %needed)
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %fail, label %copy_or_finish

copy_or_finish:
  %empty = icmp eq i64 %length, 0
  br i1 %empty, label %terminate, label %copy

copy:
  %data = call ptr @weave_buffer_data(ptr %buffer)
  %dst = getelementptr inbounds i8, ptr %data, i64 %old_length
  call ptr @memcpy(ptr %dst, ptr %src, i64 %length)
  br label %terminate

terminate:
  %data2 = call ptr @weave_buffer_data(ptr %buffer)
  %terminator = getelementptr inbounds i8, ptr %data2, i64 %new_length
  store i8 0, ptr %terminator
  %length_field = call ptr @weave_buffer_length_ptr(ptr %buffer)
  store i64 %new_length, ptr %length_field
  ret i32 0

fail:
  ret i32 1
}

define i32 @weave_buffer_append_cstr(ptr %buffer, ptr %text) {
entry:
  %null = icmp eq ptr %text, null
  br i1 %null, label %fail, label %append

append:
  %length = call i64 @strlen(ptr %text)
  %status = call i32 @weave_buffer_append_bytes(ptr %buffer, ptr %text, i64 %length)
  ret i32 %status

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; Decimal integer formatting
;
; Magnitudes are deliberately formatted with unsigned division. Two's-complement
; subtraction therefore represents INT32_MIN/INT64_MIN correctly instead of
; overflowing while attempting to create a signed positive value.
; ----------------------------------------------------------------------------

define i32 @weave_buffer_append_u32(ptr %buffer, i32 %value) {
entry:
  %single = icmp ult i32 %value, 10
  br i1 %single, label %emit_single, label %emit_prefix

emit_prefix:
  %prefix = udiv i32 %value, 10
  %prefix_status = call i32 @weave_buffer_append_u32(ptr %buffer, i32 %prefix)
  %prefix_failed = icmp ne i32 %prefix_status, 0
  br i1 %prefix_failed, label %fail, label %emit_remainder

emit_remainder:
  %remainder = urem i32 %value, 10
  br label %emit_digit

emit_single:
  br label %emit_digit

emit_digit:
  %digit = phi i32 [%value, %emit_single], [%remainder, %emit_remainder]
  %ascii = add i32 %digit, 48
  %status = call i32 @weave_buffer_append_byte(ptr %buffer, i32 %ascii)
  ret i32 %status

fail:
  ret i32 1
}

define i32 @weave_buffer_append_i32(ptr %buffer, i32 %value) {
entry:
  %negative = icmp slt i32 %value, 0
  br i1 %negative, label %emit_sign, label %emit_nonnegative

emit_sign:
  %dash_status = call i32 @weave_buffer_append_byte(ptr %buffer, i32 45)
  %dash_failed = icmp ne i32 %dash_status, 0
  br i1 %dash_failed, label %fail, label %emit_magnitude

emit_magnitude:
  %magnitude = sub i32 0, %value
  %negative_status = call i32 @weave_buffer_append_u32(ptr %buffer, i32 %magnitude)
  ret i32 %negative_status

emit_nonnegative:
  %positive_status = call i32 @weave_buffer_append_u32(ptr %buffer, i32 %value)
  ret i32 %positive_status

fail:
  ret i32 1
}

define i32 @weave_buffer_append_u64(ptr %buffer, i64 %value) {
entry:
  %single = icmp ult i64 %value, 10
  br i1 %single, label %emit_single, label %emit_prefix

emit_prefix:
  %prefix = udiv i64 %value, 10
  %prefix_status = call i32 @weave_buffer_append_u64(ptr %buffer, i64 %prefix)
  %prefix_failed = icmp ne i32 %prefix_status, 0
  br i1 %prefix_failed, label %fail, label %emit_remainder

emit_remainder:
  %remainder = urem i64 %value, 10
  br label %emit_digit

emit_single:
  br label %emit_digit

emit_digit:
  %digit = phi i64 [%value, %emit_single], [%remainder, %emit_remainder]
  %digit_i32 = trunc i64 %digit to i32
  %ascii = add i32 %digit_i32, 48
  %status = call i32 @weave_buffer_append_byte(ptr %buffer, i32 %ascii)
  ret i32 %status

fail:
  ret i32 1
}

define i32 @weave_buffer_append_i64(ptr %buffer, i64 %value) {
entry:
  %negative = icmp slt i64 %value, 0
  br i1 %negative, label %emit_sign, label %emit_nonnegative

emit_sign:
  %dash_status = call i32 @weave_buffer_append_byte(ptr %buffer, i32 45)
  %dash_failed = icmp ne i32 %dash_status, 0
  br i1 %dash_failed, label %fail, label %emit_magnitude

emit_magnitude:
  %magnitude = sub i64 0, %value
  %negative_status = call i32 @weave_buffer_append_u64(ptr %buffer, i64 %magnitude)
  ret i32 %negative_status

emit_nonnegative:
  %positive_status = call i32 @weave_buffer_append_u64(ptr %buffer, i64 %value)
  ret i32 %positive_status

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; Byte-slice helpers
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
  %matches = icmp eq i32 %cmp, 0
  br i1 %matches, label %equal, label %not_equal

equal:
  ret i32 1

not_equal:
  ret i32 0
}

