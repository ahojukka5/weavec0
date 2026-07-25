; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 07_scope_override.ll
;
; Per-function binding scope and defensive name validation.
;
; This module is linked with llvm-link --override after the ordinary Stage 0
; modules. It replaces three emitter entry points without duplicating the large
; handwritten emitter:
;
;   - weave_emit_function
;   - weave_emit_lookup_local_type
;   - weave_emit_name_expr
;
; The override keeps the emitted LLVM text byte-for-byte identical for valid
; WIR while making binding resolution function-local and rejecting undefined,
; duplicate, or parameter/local-shadowing bindings before any function text is
; appended.
; =============================================================================

@weave.emit.current_param_list = external global i64
@weave.scope.current_function_node = global i64 -1

@weave.scope.define_i32 = private unnamed_addr constant [13 x i8] c"define i32 @\00"
@weave.scope.define_i64 = private unnamed_addr constant [13 x i8] c"define i64 @\00"
@weave.scope.define_ptr = private unnamed_addr constant [13 x i8] c"define ptr @\00"
@weave.scope.define_void = private unnamed_addr constant [14 x i8] c"define void @\00"
@weave.scope.define_i1 = private unnamed_addr constant [12 x i8] c"define i1 @\00"
@weave.scope.fn_sig = private unnamed_addr constant [6 x i8] c"() {\0A\00"
@weave.scope.fn_sig_1_suffix = private unnamed_addr constant [9 x i8] c".arg) {\0A\00"
@weave.scope.entry = private unnamed_addr constant [8 x i8] c"entry:\0A\00"
@weave.scope.close_fn = private unnamed_addr constant [4 x i8] c"}\0A\0A\00"
@weave.scope.indent_tmp = private unnamed_addr constant [5 x i8] c"  %t\00"
@weave.scope.load_i32 = private unnamed_addr constant [19 x i8] c" = load i32, ptr %\00"
@weave.scope.load_i64 = private unnamed_addr constant [19 x i8] c" = load i64, ptr %\00"
@weave.scope.load_i1 = private unnamed_addr constant [18 x i8] c" = load i1, ptr %\00"
@weave.scope.load_ptr = private unnamed_addr constant [19 x i8] c" = load ptr, ptr %\00"

define i32 @weave_scope_is_binding_kind(i32 %kind) {
entry:
  %is_param = icmp eq i32 %kind, 30
  %is_let = icmp eq i32 %kind, 7
  %is_binding = or i1 %is_param, %is_let
  br i1 %is_binding, label %yes, label %no

yes:
  ret i32 1

no:
  ret i32 0
}

define i64 @weave_scope_function_start(ptr %ctx, i64 %function_node) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %has_previous = icmp sgt i64 %function_node, 0
  br i1 %has_previous, label %prepare, label %zero

prepare:
  %first = sub i64 %function_node, 1
  br label %scan

scan:
  %index = phi i64 [%first, %prepare], [%previous, %continue]
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %index)
  %is_function = icmp eq i32 %kind, 2
  %is_extern = icmp eq i32 %kind, 17
  %is_separator = or i1 %is_function, %is_extern
  br i1 %is_separator, label %after_separator, label %check_zero

check_zero:
  %at_zero = icmp eq i64 %index, 0
  br i1 %at_zero, label %zero, label %continue

continue:
  %previous = sub i64 %index, 1
  br label %scan

after_separator:
  %start = add i64 %index, 1
  ret i64 %start

zero:
  ret i64 0
}

define i32 @weave_scope_nodes_same_name(ptr %ctx, i64 %lhs_node, i64 %rhs_node) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %source = call ptr @weave_emit_source(ptr %ctx)
  %data = call ptr @weave_source_data(ptr %source)
  %lhs_start = call i64 @weave_ast_text_start(ptr %ast, i64 %lhs_node)
  %lhs_len = call i64 @weave_ast_text_len(ptr %ast, i64 %lhs_node)
  %rhs_start = call i64 @weave_ast_text_start(ptr %ast, i64 %rhs_node)
  %rhs_len = call i64 @weave_ast_text_len(ptr %ast, i64 %rhs_node)
  %lhs_text = getelementptr inbounds i8, ptr %data, i64 %lhs_start
  %rhs_text = getelementptr inbounds i8, ptr %data, i64 %rhs_start
  %same = call i32 @weave_bytes_equal(
    ptr %lhs_text,
    i64 %lhs_len,
    ptr %rhs_text,
    i64 %rhs_len
  )
  ret i32 %same
}

define i32 @weave_scope_validate_bindings(ptr %ctx, i64 %function_node) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %start = call i64 @weave_scope_function_start(ptr %ctx, i64 %function_node)
  br label %outer

outer:
  %i = phi i64 [%start, %entry], [%next_i, %outer_continue]
  %outer_done = icmp uge i64 %i, %function_node
  br i1 %outer_done, label %success, label %outer_kind

outer_kind:
  %kind_i = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %binding_i_i32 = call i32 @weave_scope_is_binding_kind(i32 %kind_i)
  %binding_i = icmp ne i32 %binding_i_i32, 0
  br i1 %binding_i, label %inner_prepare, label %outer_continue

inner_prepare:
  %first_j = add i64 %i, 1
  br label %inner

inner:
  %j = phi i64 [%first_j, %inner_prepare], [%next_j, %inner_continue]
  %inner_done = icmp uge i64 %j, %function_node
  br i1 %inner_done, label %outer_continue, label %inner_kind

inner_kind:
  %kind_j = call i32 @weave_ast_kind(ptr %ast, i64 %j)
  %binding_j_i32 = call i32 @weave_scope_is_binding_kind(i32 %kind_j)
  %binding_j = icmp ne i32 %binding_j_i32, 0
  br i1 %binding_j, label %compare, label %inner_continue

compare:
  %same_i32 = call i32 @weave_scope_nodes_same_name(
    ptr %ctx,
    i64 %i,
    i64 %j
  )
  %same = icmp ne i32 %same_i32, 0
  br i1 %same, label %fail, label %inner_continue

inner_continue:
  %next_j = add i64 %j, 1
  br label %inner

outer_continue:
  %next_i = add i64 %i, 1
  br label %outer

success:
  ret i32 0

fail:
  ret i32 1
}

define i32 @weave_emit_lookup_local_type(ptr %ctx, i64 %name_start, i64 %name_len) {
entry:
  %function_node = load i64, ptr @weave.scope.current_function_node
  %has_function = icmp sge i64 %function_node, 0
  br i1 %has_function, label %prepare, label %not_found

prepare:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %source = call ptr @weave_emit_source(ptr %ctx)
  %data = call ptr @weave_source_data(ptr %source)
  %name_text = getelementptr inbounds i8, ptr %data, i64 %name_start
  %start = call i64 @weave_scope_function_start(ptr %ctx, i64 %function_node)
  br label %loop

loop:
  %i = phi i64 [%start, %prepare], [%next_i, %continue]
  %done = icmp uge i64 %i, %function_node
  br i1 %done, label %not_found, label %check_kind

check_kind:
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %is_param = icmp eq i32 %kind, 30
  %is_let = icmp eq i32 %kind, 7
  %is_binding = or i1 %is_param, %is_let
  br i1 %is_binding, label %check_name, label %continue

check_name:
  %binding_start = call i64 @weave_ast_text_start(ptr %ast, i64 %i)
  %binding_len = call i64 @weave_ast_text_len(ptr %ast, i64 %i)
  %binding_text = getelementptr inbounds i8, ptr %data, i64 %binding_start
  %same_i32 = call i32 @weave_bytes_equal(
    ptr %name_text,
    i64 %name_len,
    ptr %binding_text,
    i64 %binding_len
  )
  %same = icmp ne i32 %same_i32, 0
  br i1 %same, label %return_type, label %continue

return_type:
  %param_type_wide = call i64 @weave_ast_a(ptr %ast, i64 %i)
  %let_type_wide = call i64 @weave_ast_b(ptr %ast, i64 %i)
  %type_wide = select i1 %is_param, i64 %param_type_wide, i64 %let_type_wide
  %type_kind = trunc i64 %type_wide to i32
  ret i32 %type_kind

continue:
  %next_i = add i64 %i, 1
  br label %loop

not_found:
  ret i32 -1
}

define i64 @weave_emit_name_expr(ptr %ctx, i64 %node_index) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %name_start = call i64 @weave_ast_text_start(ptr %ast, i64 %node_index)
  %name_len = call i64 @weave_ast_text_len(ptr %ast, i64 %node_index)
  %type_kind = call i32 @weave_emit_lookup_local_type(
    ptr %ctx,
    i64 %name_start,
    i64 %name_len
  )
  %missing = icmp eq i32 %type_kind, -1
  br i1 %missing, label %fail, label %emit

emit:
  %temp = call i64 @weave_emit_next_temp(ptr %ctx)
  %is_ptr = icmp eq i32 %type_kind, 58
  %s0 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.indent_tmp)
  %temp_i32 = trunc i64 %temp to i32
  %s1 = call i32 @weave_emit_i32(ptr %ctx, i32 %temp_i32)
  br i1 %is_ptr, label %emit_ptr, label %check_i64

check_i64:
  %is_i64 = icmp eq i32 %type_kind, 39
  br i1 %is_i64, label %emit_i64, label %check_bool

check_bool:
  %is_bool = icmp eq i32 %type_kind, 72
  br i1 %is_bool, label %emit_bool, label %emit_i32

emit_i32:
  %s2_i32 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.load_i32)
  %s3_i32 = call i32 @weave_emit_source_slice(ptr %ctx, i64 %name_start, i64 %name_len)
  %s4_i32 = call i32 @weave_emit_newline(ptr %ctx)
  %a0 = icmp ne i32 %s0, 0
  %a1 = icmp ne i32 %s1, 0
  %a2 = icmp ne i32 %s2_i32, 0
  %a3 = icmp ne i32 %s3_i32, 0
  %a4 = icmp ne i32 %s4_i32, 0
  %a01 = or i1 %a0, %a1
  %a23 = or i1 %a2, %a3
  %a0123 = or i1 %a01, %a23
  %abad = or i1 %a0123, %a4
  br i1 %abad, label %fail, label %success

emit_i64:
  %s2_i64 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.load_i64)
  %s3_i64 = call i32 @weave_emit_source_slice(ptr %ctx, i64 %name_start, i64 %name_len)
  %s4_i64 = call i32 @weave_emit_newline(ptr %ctx)
  %b0 = icmp ne i32 %s0, 0
  %b1 = icmp ne i32 %s1, 0
  %b2 = icmp ne i32 %s2_i64, 0
  %b3 = icmp ne i32 %s3_i64, 0
  %b4 = icmp ne i32 %s4_i64, 0
  %b01 = or i1 %b0, %b1
  %b23 = or i1 %b2, %b3
  %b0123 = or i1 %b01, %b23
  %bbad = or i1 %b0123, %b4
  br i1 %bbad, label %fail, label %success

emit_bool:
  %s2_bool = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.load_i1)
  %s3_bool = call i32 @weave_emit_source_slice(ptr %ctx, i64 %name_start, i64 %name_len)
  %s4_bool = call i32 @weave_emit_newline(ptr %ctx)
  %c0 = icmp ne i32 %s0, 0
  %c1 = icmp ne i32 %s1, 0
  %c2 = icmp ne i32 %s2_bool, 0
  %c3 = icmp ne i32 %s3_bool, 0
  %c4 = icmp ne i32 %s4_bool, 0
  %c01 = or i1 %c0, %c1
  %c23 = or i1 %c2, %c3
  %c0123 = or i1 %c01, %c23
  %cbad = or i1 %c0123, %c4
  br i1 %cbad, label %fail, label %success

emit_ptr:
  %s2_ptr = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.load_ptr)
  %s3_ptr = call i32 @weave_emit_source_slice(ptr %ctx, i64 %name_start, i64 %name_len)
  %s4_ptr = call i32 @weave_emit_newline(ptr %ctx)
  %d0 = icmp ne i32 %s0, 0
  %d1 = icmp ne i32 %s1, 0
  %d2 = icmp ne i32 %s2_ptr, 0
  %d3 = icmp ne i32 %s3_ptr, 0
  %d4 = icmp ne i32 %s4_ptr, 0
  %d01 = or i1 %d0, %d1
  %d23 = or i1 %d2, %d3
  %d0123 = or i1 %d01, %d23
  %dbad = or i1 %d0123, %d4
  br i1 %dbad, label %fail, label %success

success:
  ret i64 %temp

fail:
  ret i64 -9223372036854775808
}

define i32 @weave_emit_function(ptr %ctx, i64 %node_index) {
entry:
  store i64 %node_index, ptr @weave.scope.current_function_node
  %bindings_status = call i32 @weave_scope_validate_bindings(
    ptr %ctx,
    i64 %node_index
  )
  %bindings_failed = icmp ne i32 %bindings_status, 0
  br i1 %bindings_failed, label %fail, label %prepare

prepare:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %body_node = call i64 @weave_ast_a(ptr %ast, i64 %node_index)
  %param_wrapper = call i64 @weave_ast_b(ptr %ast, i64 %node_index)
  %param_count = call i64 @weave_ast_c(ptr %ast, i64 %node_index)
  %param_list = call i64 @weave_ast_a(ptr %ast, i64 %param_wrapper)
  %return_type_wide = call i64 @weave_ast_c(ptr %ast, i64 %body_node)
  %return_type = trunc i64 %return_type_wide to i32
  %returns_i64 = icmp eq i32 %return_type, 39
  %returns_ptr = icmp eq i32 %return_type, 58
  %returns_void = icmp eq i32 %return_type, 59
  %returns_bool = icmp eq i32 %return_type, 72
  %name_start = call i64 @weave_ast_text_start(ptr %ast, i64 %node_index)
  %name_len = call i64 @weave_ast_text_len(ptr %ast, i64 %node_index)
  br i1 %returns_i64, label %emit_i64_define, label %check_ptr_define

check_ptr_define:
  br i1 %returns_ptr, label %emit_ptr_define, label %check_void_define

check_void_define:
  br i1 %returns_void, label %emit_void_define, label %check_bool_define

check_bool_define:
  br i1 %returns_bool, label %emit_bool_define, label %emit_i32_define

emit_i32_define:
  %s0_i32 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.define_i32)
  br label %emit_name

emit_i64_define:
  %s0_i64 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.define_i64)
  br label %emit_name

emit_ptr_define:
  %s0_ptr = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.define_ptr)
  br label %emit_name

emit_void_define:
  %s0_void = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.define_void)
  br label %emit_name

emit_bool_define:
  %s0_bool = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.define_i1)
  br label %emit_name

emit_name:
  %s0 = phi i32 [%s0_i32, %emit_i32_define], [%s0_i64, %emit_i64_define], [%s0_ptr, %emit_ptr_define], [%s0_void, %emit_void_define], [%s0_bool, %emit_bool_define]
  %s1 = call i32 @weave_emit_source_slice(ptr %ctx, i64 %name_start, i64 %name_len)
  %has_param = icmp ne i64 %param_count, 0
  store i64 %param_list, ptr @weave.emit.current_param_list
  br i1 %has_param, label %emit_param_sig, label %emit_no_param_sig

emit_no_param_sig:
  %s2_no_param = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.fn_sig)
  br label %emit_entry

emit_param_sig:
  %sig_status = call i32 @weave_emit_param_sig_list(ptr %ctx, i64 %param_list)
  %sig_suffix = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.fn_sig_1_suffix)
  %sig_failed = icmp ne i32 %sig_status, 0
  %suffix_failed = icmp ne i32 %sig_suffix, 0
  %s2_param_bad = or i1 %sig_failed, %suffix_failed
  br label %emit_entry

emit_entry:
  %s2 = phi i32 [%s2_no_param, %emit_no_param_sig], [0, %emit_param_sig]
  %s2_param_failed = phi i1 [false, %emit_no_param_sig], [%s2_param_bad, %emit_param_sig]
  %s3 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.entry)
  %s0_failed = icmp ne i32 %s0, 0
  %s1_failed = icmp ne i32 %s1, 0
  %s2_failed = icmp ne i32 %s2, 0
  %s3_failed = icmp ne i32 %s3, 0
  %head_bad0 = or i1 %s0_failed, %s1_failed
  %head_bad1 = or i1 %s2_failed, %s3_failed
  %head_bad2 = or i1 %head_bad1, %s2_param_failed
  %head_bad = or i1 %head_bad0, %head_bad2
  br i1 %head_bad, label %fail, label %maybe_init_param

maybe_init_param:
  br i1 %has_param, label %init_params, label %body

init_params:
  %p_status = call i32 @weave_emit_init_param_list(ptr %ctx, i64 %param_list)
  %p_failed = icmp ne i32 %p_status, 0
  br i1 %p_failed, label %fail, label %body

body:
  call void @weave_emit_set_return_type(ptr %ctx, i32 %return_type)
  %body_status = call i32 @weave_emit_stmt(ptr %ctx, i64 %body_node)
  %body_failed = icmp ne i32 %body_status, 0
  br i1 %body_failed, label %fail, label %close

close:
  %s4 = call i32 @weave_emit_cstr(ptr %ctx, ptr @weave.scope.close_fn)
  %close_failed = icmp ne i32 %s4, 0
  br i1 %close_failed, label %fail, label %success

success:
  store i64 -1, ptr @weave.scope.current_function_node
  ret i32 0

fail:
  store i64 -1, ptr @weave.scope.current_function_node
  ret i32 1
}
