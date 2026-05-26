; SPDX-License-Identifier: Apache-2.0
; =============================================================================
; 05_ast.ll
;
; AST storage and accessors for the Stage 0 bootstrap compiler.
;
; Responsibilities:
;   - own the %weave.Ast container (a growable array of %weave.AstNode)
;   - init / free / reserve / grow the node array
;   - push new nodes (weave_ast_push) with kind, three i64 fields a/b/c, and
;     a source text slice (text_start, text_len)
;   - expose typed accessors so the parser and emitter never compute field
;     offsets directly (weave_ast_kind, weave_ast_a/b/c, weave_ast_text_*)
;
; Boundary:
;   AST node *kinds* are numeric constants documented in 00_prelude.ll.
;   The meaning of the a/b/c fields depends on kind and is documented at
;   each parser entry point (06_parser.ll) and emitter entry point
;   (07_emit_llvm.ll). Tree shape is encoded in those fields, not in a
;   separate child-list structure — the AST is deliberately compact.
; =============================================================================

; ----------------------------------------------------------------------------
; AST layout reminder
; ----------------------------------------------------------------------------
;
; %weave.AstNode = type {
;   i32, ; kind
;   i64, ; a
;   i64, ; b
;   i64, ; c
;   i64, ; text_start
;   i64  ; text_len
; }
;
; %weave.Ast = type {
;   ptr, ; nodes
;   i64, ; count
;   i64  ; capacity
; }
;
; The meaning of fields a/b/c depends on node kind.
;
; This is intentionally low-level.
; Stage 0 values simplicity and auditability over abstraction.

; ----------------------------------------------------------------------------
; AST field helpers
; ----------------------------------------------------------------------------

define ptr @weave_ast_nodes_ptr(ptr %ast) {
entry:
  %field = getelementptr inbounds %weave.Ast, ptr %ast, i32 0, i32 0
  ret ptr %field
}

define ptr @weave_ast_count_ptr(ptr %ast) {
entry:
  %field = getelementptr inbounds %weave.Ast, ptr %ast, i32 0, i32 1
  ret ptr %field
}

define ptr @weave_ast_capacity_ptr(ptr %ast) {
entry:
  %field = getelementptr inbounds %weave.Ast, ptr %ast, i32 0, i32 2
  ret ptr %field
}

define ptr @weave_ast_nodes(ptr %ast) {
entry:
  %field = call ptr @weave_ast_nodes_ptr(ptr %ast)
  %value = load ptr, ptr %field
  ret ptr %value
}

define i64 @weave_ast_count(ptr %ast) {
entry:
  %field = call ptr @weave_ast_count_ptr(ptr %ast)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_ast_capacity(ptr %ast) {
entry:
  %field = call ptr @weave_ast_capacity_ptr(ptr %ast)
  %value = load i64, ptr %field
  ret i64 %value
}

; ----------------------------------------------------------------------------
; AST node access
; ----------------------------------------------------------------------------

define ptr @weave_ast_node_ptr(ptr %ast, i64 %index) {
entry:
  %nodes = call ptr @weave_ast_nodes(ptr %ast)
  %slot = getelementptr inbounds %weave.AstNode, ptr %nodes, i64 %index
  ret ptr %slot
}

; ----------------------------------------------------------------------------
; Individual node field accessors
; ----------------------------------------------------------------------------

define ptr @weave_ast_node_kind_ptr(ptr %node) {
entry:
  %field = getelementptr inbounds %weave.AstNode, ptr %node, i32 0, i32 0
  ret ptr %field
}

define ptr @weave_ast_node_a_ptr(ptr %node) {
entry:
  %field = getelementptr inbounds %weave.AstNode, ptr %node, i32 0, i32 1
  ret ptr %field
}

define ptr @weave_ast_node_b_ptr(ptr %node) {
entry:
  %field = getelementptr inbounds %weave.AstNode, ptr %node, i32 0, i32 2
  ret ptr %field
}

define ptr @weave_ast_node_c_ptr(ptr %node) {
entry:
  %field = getelementptr inbounds %weave.AstNode, ptr %node, i32 0, i32 3
  ret ptr %field
}

define ptr @weave_ast_node_text_start_ptr(ptr %node) {
entry:
  %field = getelementptr inbounds %weave.AstNode, ptr %node, i32 0, i32 4
  ret ptr %field
}

define ptr @weave_ast_node_text_len_ptr(ptr %node) {
entry:
  %field = getelementptr inbounds %weave.AstNode, ptr %node, i32 0, i32 5
  ret ptr %field
}

; ----------------------------------------------------------------------------
; weave_ast_init
;
; Allocate the initial backing array (256 nodes) for a caller-owned
; %weave.Ast and store the resulting pointer/count/capacity in place.
;
; Parameters:
;   ast - %weave.Ast* (caller-owned storage, contents overwritten).
;
; Returns:
;   0 on success.
;   1 on malloc failure (the caller is responsible for not pushing into a
;     failed AST; weave_ast_push checks the capacity field and will fail
;     cleanly if it sees zero).
; ----------------------------------------------------------------------------

define i32 @weave_ast_init(ptr %ast) {
entry:
  %capacity = add i64 256, 0
  %node_size = ptrtoint ptr getelementptr(%weave.AstNode, ptr null, i32 1) to i64
  %bytes = mul i64 %capacity, %node_size

  %nodes = call ptr @malloc(i64 %bytes)
  %failed = icmp eq ptr %nodes, null
  br i1 %failed, label %fail, label %store

store:
  %nodes_field = call ptr @weave_ast_nodes_ptr(ptr %ast)
  %count_field = call ptr @weave_ast_count_ptr(ptr %ast)
  %capacity_field = call ptr @weave_ast_capacity_ptr(ptr %ast)

  store ptr %nodes, ptr %nodes_field
  store i64 0, ptr %count_field
  store i64 %capacity, ptr %capacity_field

  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_ast_free
; ----------------------------------------------------------------------------

define void @weave_ast_free(ptr %ast) {
entry:
  %nodes = call ptr @weave_ast_nodes(ptr %ast)
  %has_nodes = icmp ne ptr %nodes, null
  br i1 %has_nodes, label %free_nodes, label %done

free_nodes:
  call void @free(ptr %nodes)
  br label %done

done:
  %nodes_field = call ptr @weave_ast_nodes_ptr(ptr %ast)
  %count_field = call ptr @weave_ast_count_ptr(ptr %ast)
  %capacity_field = call ptr @weave_ast_capacity_ptr(ptr %ast)

  store ptr null, ptr %nodes_field
  store i64 0, ptr %count_field
  store i64 0, ptr %capacity_field

  ret void
}

; ----------------------------------------------------------------------------
; weave_ast_reserve
;
; Ensure capacity for at least `needed` nodes.
;
; Returns:
;   0 on success
;   1 on allocation failure
; ----------------------------------------------------------------------------

define i32 @weave_ast_reserve(ptr %ast, i64 %needed) {
entry:
  %capacity = call i64 @weave_ast_capacity(ptr %ast)
  %enough = icmp ule i64 %needed, %capacity
  br i1 %enough, label %success, label %grow_start

grow_start:
  br label %grow_loop

grow_loop:
  %current = phi i64 [%capacity, %grow_start], [%next, %grow_more]
  %too_small = icmp ult i64 %current, %needed
  br i1 %too_small, label %grow_more, label %reallocate

grow_more:
  %next = mul i64 %current, 2
  br label %grow_loop

reallocate:
  %nodes_old = call ptr @weave_ast_nodes(ptr %ast)
  %node_size = ptrtoint ptr getelementptr(%weave.AstNode, ptr null, i32 1) to i64
  %bytes = mul i64 %current, %node_size

  %nodes_new = call ptr @realloc(ptr %nodes_old, i64 %bytes)
  %failed = icmp eq ptr %nodes_new, null
  br i1 %failed, label %fail, label %store

store:
  %nodes_field = call ptr @weave_ast_nodes_ptr(ptr %ast)
  %capacity_field = call ptr @weave_ast_capacity_ptr(ptr %ast)

  store ptr %nodes_new, ptr %nodes_field
  store i64 %current, ptr %capacity_field

  br label %success

success:
  ret i32 0

fail:
  ret i32 1
}

; ----------------------------------------------------------------------------
; weave_ast_push
;
; Append a new node to the AST array, growing capacity (via realloc) if the
; backing storage is full. The interpretation of the a/b/c fields depends
; on `kind` and is documented at each parser site that builds a node of
; that kind.
;
; Parameters:
;   ast        - %weave.Ast* initialised via weave_ast_init.
;   kind       - AST kind constant (see AST_* list in 00_prelude.ll).
;   a, b, c    - three i64 payload fields (kind-specific meaning).
;   text_start - byte offset into source for the node's name/text slice (or 0
;                if the node carries no text).
;   text_len   - byte length of that slice (0 when no text).
;
; Returns:
;   >=0 : index of the newly appended node.
;   -1  : allocation failure (realloc returned null).
; ----------------------------------------------------------------------------

define i64 @weave_ast_push(
  ptr %ast,
  i32 %kind,
  i64 %a,
  i64 %b,
  i64 %c,
  i64 %text_start,
  i64 %text_len
) {
entry:
  %count = call i64 @weave_ast_count(ptr %ast)
  %needed = add i64 %count, 1

  %reserve_status = call i32 @weave_ast_reserve(ptr %ast, i64 %needed)
  %reserve_failed = icmp ne i32 %reserve_status, 0
  br i1 %reserve_failed, label %fail, label %store

store:
  %node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %count)

  %kind_ptr = call ptr @weave_ast_node_kind_ptr(ptr %node)
  %a_ptr = call ptr @weave_ast_node_a_ptr(ptr %node)
  %b_ptr = call ptr @weave_ast_node_b_ptr(ptr %node)
  %c_ptr = call ptr @weave_ast_node_c_ptr(ptr %node)
  %text_start_ptr = call ptr @weave_ast_node_text_start_ptr(ptr %node)
  %text_len_ptr = call ptr @weave_ast_node_text_len_ptr(ptr %node)

  store i32 %kind, ptr %kind_ptr
  store i64 %a, ptr %a_ptr
  store i64 %b, ptr %b_ptr
  store i64 %c, ptr %c_ptr
  store i64 %text_start, ptr %text_start_ptr
  store i64 %text_len, ptr %text_len_ptr

  %count_field = call ptr @weave_ast_count_ptr(ptr %ast)
  store i64 %needed, ptr %count_field

  ret i64 %count

fail:
  ret i64 -1
}

; ----------------------------------------------------------------------------
; AST node getters
; ----------------------------------------------------------------------------

define i32 @weave_ast_kind(ptr %ast, i64 %index) {
entry:
  %node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %index)
  %field = call ptr @weave_ast_node_kind_ptr(ptr %node)
  %value = load i32, ptr %field
  ret i32 %value
}

define i64 @weave_ast_a(ptr %ast, i64 %index) {
entry:
  %node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %index)
  %field = call ptr @weave_ast_node_a_ptr(ptr %node)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_ast_b(ptr %ast, i64 %index) {
entry:
  %node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %index)
  %field = call ptr @weave_ast_node_b_ptr(ptr %node)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_ast_c(ptr %ast, i64 %index) {
entry:
  %node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %index)
  %field = call ptr @weave_ast_node_c_ptr(ptr %node)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_ast_text_start(ptr %ast, i64 %index) {
entry:
  %node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %index)
  %field = call ptr @weave_ast_node_text_start_ptr(ptr %node)
  %value = load i64, ptr %field
  ret i64 %value
}

define i64 @weave_ast_text_len(ptr %ast, i64 %index) {
entry:
  %node = call ptr @weave_ast_node_ptr(ptr %ast, i64 %index)
  %field = call ptr @weave_ast_node_text_len_ptr(ptr %node)
  %value = load i64, ptr %field
  ret i64 %value
}

; ----------------------------------------------------------------------------
; Convenience constructors
; ----------------------------------------------------------------------------
;
; These helpers make parser code more readable.
;
; AST_INTEGER_LITERAL = 11
; AST_STRING_LITERAL  = 12
; AST_NAME_EXPR       = 13
;
; The parser and emitter still operate directly on the primitive node storage.
; These are only thin wrappers.


define i64 @weave_ast_make_integer_literal(ptr %ast, i32 %value) {
entry:
  %wide = sext i32 %value to i64
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 11,
    i64 %wide,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )

  ret i64 %node
}

; weave_ast_make_integer_literal_i64
;
; Wide i64 sibling of weave_ast_make_integer_literal. Pushes AST kind 36
; (AST_INTEGER_LITERAL_I64) and stores the full i64 value in the `a` field
; without truncation, so the emitter can produce a correctly-typed i64
; immediate operand in call argument position.
;
; Parameters:
;   ast   - %weave.Ast* initialised via weave_ast_init.
;   value - the full i64 literal value, untruncated.
;
; Returns:
;   >=0 : new node index.
;   -1  : on allocation failure (propagated from weave_ast_push).
define i64 @weave_ast_make_integer_literal_i64(ptr %ast, i64 %value) {
entry:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 36,
    i64 %value,
    i64 0,
    i64 0,
    i64 0,
    i64 0
  )

  ret i64 %node
}


define i64 @weave_ast_make_string_literal(
  ptr %ast,
  i64 %text_start,
  i64 %text_len
) {
entry:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 12,
    i64 0,
    i64 0,
    i64 0,
    i64 %text_start,
    i64 %text_len
  )

  ret i64 %node
}


define i64 @weave_ast_make_name_expr(
  ptr %ast,
  i64 %text_start,
  i64 %text_len
) {
entry:
  %node = call i64 @weave_ast_push(
    ptr %ast,
    i32 13,
    i64 0,
    i64 0,
    i64 0,
    i64 %text_start,
    i64 %text_len
  )

  ret i64 %node
}
