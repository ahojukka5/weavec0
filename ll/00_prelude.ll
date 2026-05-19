; =============================================================================
; Weave Stage 0 Bootstrap Compiler
; 00_prelude.ll
;
; This file defines the shared LLVM IR conventions used by the hand-written
; Stage 0 compiler.
;
; Stage 0 has one responsibility:
;
;     input.weave -> output.ll
;
; It does not assemble, link, optimize, expand packages, or implement the full
; future Weave language. It is the first small bridge toward self-hosting.
; =============================================================================

; ----------------------------------------------------------------------------
; Target
; ----------------------------------------------------------------------------
;
; The first Stage 0 artifact targets a normal 64-bit Linux environment.
; Keep pointer-sized values as i64 when interacting with C ABI functions.
;
; If this compiler is ported later, this file is the place where target-level
; assumptions should be reviewed first.

source_filename = "weave-stage0-bootstrap"
target triple = "x86_64-unknown-linux-gnu"

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"

; ----------------------------------------------------------------------------
; Core type conventions
; ----------------------------------------------------------------------------
;
; Stage 0 intentionally uses a tiny set of runtime data structures.
;
; Integers:
;   i32 is the language-level integer used by the bootstrap subset.
;   i64 is used for C ABI sizes, byte offsets, capacities, and pointer-sized data.
;
; Pointers:
;   ptr is used directly. Null checks must use `icmp eq ptr %p, null`.
;   Do not cast pointers to i32 for null checks or address calculations.
;
; Booleans:
;   i1 is used internally for LLVM branch conditions.
;   i32 0 and i32 1 may be used at the language/runtime boundary.

; A growable byte buffer used for emitted LLVM text and temporary strings.
; data     : pointer to allocated bytes
; length   : number of bytes currently used
; capacity : number of bytes allocated
%weave.Buffer = type { ptr, i64, i64 }

; A source file loaded into memory.
; data   : null-terminated byte buffer
; length : source length in bytes, excluding final null terminator
%weave.Source = type { ptr, i64 }

; A token stream is represented by parallel arrays.
; kinds    : ptr to i32 token kinds
; starts   : ptr to i64 byte offsets into source
; lengths  : ptr to i64 token byte lengths
; values   : ptr to i32 integer values, used only by integer tokens
; count    : number of tokens currently stored
; capacity : number of tokens allocated
%weave.Tokens = type { ptr, ptr, ptr, ptr, i64, i64 }

; The parser keeps only the token stream and current cursor.
; tokens : pointer to %weave.Tokens
; index  : current token index
%weave.Parser = type { ptr, i64 }

; A compact AST node.
;
; kind  : AST node kind
; a     : first integer field, meaning depends on kind
; b     : second integer field, meaning depends on kind
; c     : third integer field, meaning depends on kind
; text_start : source byte offset for name/string tokens, or 0
; text_len   : source byte length for name/string tokens, or 0
;
; Stage 0 uses a deliberately primitive AST. It is allowed to be simple.
; It is not allowed to grow into a full production compiler AST too early.
%weave.AstNode = type { i32, i64, i64, i64, i64, i64 }

; A growable AST node array.
; nodes    : ptr to %weave.AstNode
; count    : number of nodes currently used
; capacity : number of nodes allocated
%weave.Ast = type { ptr, i64, i64 }

; The full compilation context passed through the Stage 0 pipeline.
; source : pointer to %weave.Source
; tokens : pointer to %weave.Tokens
; ast    : pointer to %weave.Ast
; output : pointer to %weave.Buffer
%weave.CompileContext = type { ptr, ptr, ptr, ptr }

; ----------------------------------------------------------------------------
; Token kind constants
; ----------------------------------------------------------------------------
;
; These are duplicated as preprocessor-like constants using comments rather than
; global variables. LLVM IR does not have textual constants, so the numeric
; values are used directly in later files.
;
; TOKEN_EOF     = 0
; TOKEN_LPAREN  = 1
; TOKEN_RPAREN  = 2
; TOKEN_IDENT   = 3
; TOKEN_INT     = 4
; TOKEN_STRING  = 5
; TOKEN_FN      = 6
; TOKEN_RETURN  = 7
; TOKEN_IF      = 8
; TOKEN_ELSE    = 9
; TOKEN_WHILE   = 10
; TOKEN_LET     = 11
; TOKEN_SET     = 12
; TOKEN_PLUS    = 13
; TOKEN_MINUS   = 14
; TOKEN_STAR    = 15
; TOKEN_SLASH   = 16
; TOKEN_EQ      = 17
; TOKEN_EQEQ    = 18
; TOKEN_NE      = 19
; TOKEN_LT      = 20
; TOKEN_LE      = 21
; TOKEN_GT      = 22
; TOKEN_GE      = 23
; TOKEN_BLOCK   = 24
; TOKEN_CORE_MODULE  = 25
; TOKEN_CORE_VERSION = 26
; TOKEN_DECLS        = 27
; TOKEN_PARAMS       = 28
; TOKEN_RETURNS      = 29
; TOKEN_BODY         = 30
; TOKEN_CONST_I32    = 31
; TOKEN_I32          = 32
; TOKEN_PARAM_GET    = 33
; TOKEN_CALL_I32     = 34
; TOKEN_LOCAL_GET    = 35
; TOKEN_THEN         = 36
; TOKEN_LT_I32       = 37
; TOKEN_CONST_STRING = 38
;
; Add new token kinds only when a bootstrap test requires them.

; ----------------------------------------------------------------------------
; AST kind constants
; ----------------------------------------------------------------------------
;
; AST_PROGRAM         = 1
; AST_FUNCTION        = 2
; AST_BLOCK           = 3
; AST_RETURN_STMT     = 4
; AST_IF_STMT         = 5
; AST_WHILE_STMT      = 6
; AST_LET_STMT        = 7
; AST_SET_STMT        = 8
; AST_CALL_EXPR       = 9
; AST_BINARY_EXPR     = 10
; AST_INTEGER_LITERAL = 11
; AST_STRING_LITERAL  = 12
; AST_NAME_EXPR       = 13
; AST_EXPR_STMT       = 14
;
; Keep this list small. Stage 0 exists to cross the bootstrap gap, not to model
; the complete future Weave language.

; ----------------------------------------------------------------------------
; Binary operator constants
; ----------------------------------------------------------------------------
;
; BIN_ADD = 1
; BIN_SUB = 2
; BIN_MUL = 3
; BIN_DIV = 4
; BIN_EQ  = 5
; BIN_NE  = 6
; BIN_LT  = 7
; BIN_LE  = 8
; BIN_GT  = 9
; BIN_GE  = 10

; ----------------------------------------------------------------------------
; Exit/status conventions
; ----------------------------------------------------------------------------
;
; Functions returning i32 use:
;
;   0 : success
;   1 : failure
;
; Functions returning pointers use:
;
;   null : failure / not found / allocation failed
;
; Error handling in Stage 0 should remain blunt and deterministic.
; Diagnostics can become beautiful later. The bridge must first be crossable.
