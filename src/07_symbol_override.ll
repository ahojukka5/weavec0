; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 07_symbol_override.ll
;
; Module-level declaration and call-target validation.
;
; This module is applied after 07_scope_override.ll and replaces only
; weave_emit_llvm. Validation runs against the complete parsed AST before
; weave_emit_program writes the module header, so a symbol error cannot leave
; partially emitted LLVM text in the caller's output buffer.
; =============================================================================

; Defined by 07_scope_override.ll and reused here for source-slice comparison.
declare i32 @weave_scope_nodes_same_name(ptr %ctx, i64 %lhs_node, i64 %rhs_node)

define i32 @weave_symbol_is_declaration_kind(i32 %kind) {
entry:
  %is_function = icmp eq i32 %kind, 2
  %is_extern = icmp eq i32 %kind, 17
  %is_declaration = or i1 %is_function, %is_extern
  %result = zext i1 %is_declaration to i32
  ret i32 %result
}

define i32 @weave_symbol_is_call_kind(i32 %kind) {
entry:
  %is_i32 = icmp eq i32 %kind, 9
  %is_i64 = icmp eq i32 %kind, 26
  %is_ptr = icmp eq i32 %kind, 18
  %is_void = icmp eq i32 %kind, 19
  %is_bool = icmp eq i32 %kind, 31
  %integer_call = or i1 %is_i32, %is_i64
  %pointer_or_void = or i1 %is_ptr, %is_void
  %value_call = or i1 %integer_call, %pointer_or_void
  %is_call = or i1 %value_call, %is_bool
  %result = zext i1 %is_call to i32
  ret i32 %result
}

define i32 @weave_symbol_validate_unique_declarations(ptr %ctx) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %count = call i64 @weave_ast_count(ptr %ast)
  br label %outer

outer:
  %i = phi i64 [0, %entry], [%next_i, %outer_continue]
  %outer_done = icmp uge i64 %i, %count
  br i1 %outer_done, label %success, label %outer_kind

outer_kind:
  %kind_i = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %decl_i_status = call i32 @weave_symbol_is_declaration_kind(i32 %kind_i)
  %decl_i = icmp ne i32 %decl_i_status, 0
  br i1 %decl_i, label %inner_prepare, label %outer_continue

inner_prepare:
  %first_j = add i64 %i, 1
  br label %inner

inner:
  %j = phi i64 [%first_j, %inner_prepare], [%next_j, %inner_continue]
  %inner_done = icmp uge i64 %j, %count
  br i1 %inner_done, label %outer_continue, label %inner_kind

inner_kind:
  %kind_j = call i32 @weave_ast_kind(ptr %ast, i64 %j)
  %decl_j_status = call i32 @weave_symbol_is_declaration_kind(i32 %kind_j)
  %decl_j = icmp ne i32 %decl_j_status, 0
  br i1 %decl_j, label %compare, label %inner_continue

compare:
  %same_status = call i32 @weave_scope_nodes_same_name(
    ptr %ctx,
    i64 %i,
    i64 %j
  )
  %same = icmp ne i32 %same_status, 0
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

define i32 @weave_symbol_target_exists(ptr %ctx, i64 %call_node) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %count = call i64 @weave_ast_count(ptr %ast)
  br label %loop

loop:
  %i = phi i64 [0, %entry], [%next_i, %continue]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %missing, label %check_kind

check_kind:
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %decl_status = call i32 @weave_symbol_is_declaration_kind(i32 %kind)
  %is_declaration = icmp ne i32 %decl_status, 0
  br i1 %is_declaration, label %compare, label %continue

compare:
  %same_status = call i32 @weave_scope_nodes_same_name(
    ptr %ctx,
    i64 %call_node,
    i64 %i
  )
  %same = icmp ne i32 %same_status, 0
  br i1 %same, label %found, label %continue

continue:
  %next_i = add i64 %i, 1
  br label %loop

found:
  ret i32 1

missing:
  ret i32 0
}

define i32 @weave_symbol_validate_call_targets(ptr %ctx) {
entry:
  %ast = call ptr @weave_emit_ast(ptr %ctx)
  %count = call i64 @weave_ast_count(ptr %ast)
  br label %loop

loop:
  %i = phi i64 [0, %entry], [%next_i, %continue]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %success, label %check_kind

check_kind:
  %kind = call i32 @weave_ast_kind(ptr %ast, i64 %i)
  %call_status = call i32 @weave_symbol_is_call_kind(i32 %kind)
  %is_call = icmp ne i32 %call_status, 0
  br i1 %is_call, label %lookup, label %continue

lookup:
  %exists_status = call i32 @weave_symbol_target_exists(ptr %ctx, i64 %i)
  %exists = icmp ne i32 %exists_status, 0
  br i1 %exists, label %continue, label %fail

continue:
  %next_i = add i64 %i, 1
  br label %loop

success:
  ret i32 0

fail:
  ret i32 1
}

define i32 @weave_symbol_validate_module(ptr %ctx) {
entry:
  %unique_status = call i32 @weave_symbol_validate_unique_declarations(ptr %ctx)
  %unique_failed = icmp ne i32 %unique_status, 0
  br i1 %unique_failed, label %fail, label %calls

calls:
  %call_status = call i32 @weave_symbol_validate_call_targets(ptr %ctx)
  %calls_failed = icmp ne i32 %call_status, 0
  br i1 %calls_failed, label %fail, label %success

success:
  ret i32 0

fail:
  ret i32 1
}

define i32 @weave_emit_llvm(ptr %source, ptr %ast, i64 %program_node, ptr %out) {
entry:
  %ctx_storage = alloca %weave.EmitContext
  call void @weave_emit_context_init(
    ptr %ctx_storage,
    ptr %source,
    ptr %ast,
    ptr %out
  )
  %validation_status = call i32 @weave_symbol_validate_module(ptr %ctx_storage)
  %validation_failed = icmp ne i32 %validation_status, 0
  br i1 %validation_failed, label %fail, label %emit

emit:
  %status = call i32 @weave_emit_program(ptr %ctx_storage, i64 %program_node)
  ret i32 %status

fail:
  ret i32 1
}
