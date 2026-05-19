; =============================================================================
; Weave Stage 0 Bootstrap Compiler
; 00_prelude.ll
;
; This file defines the shared LLVM IR conventions used by the hand-written
; Stage 0 compiler.
;
; Stage 0 has one responsibility:
;
;     input.wir -> output.ll
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
; TOKEN_RESERVED_13 = 13
; TOKEN_RESERVED_14 = 14
; TOKEN_RESERVED_15 = 15
; TOKEN_RESERVED_16 = 16
; TOKEN_RESERVED_17 = 17
; TOKEN_RESERVED_18 = 18
; TOKEN_RESERVED_19 = 19
; TOKEN_RESERVED_20 = 20
; TOKEN_RESERVED_21 = 21
; TOKEN_RESERVED_22 = 22
; TOKEN_RESERVED_23 = 23
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
; TOKEN_CONST_I64    = 38
; TOKEN_I64          = 39
; TOKEN_CAST_I64_TO_I32 = 40
; TOKEN_CONST_STRING = 41
; TOKEN_ADD_I64      = 42
; TOKEN_MUL_I64      = 43
; TOKEN_ADD_I32      = 44
; TOKEN_PRINT        = 45
; TOKEN_LT_I64       = 46
; TOKEN_LE_I64       = 47
; TOKEN_NE_I64       = 48
; TOKEN_CONST_BOOL   = 49
; TOKEN_TRUE         = 50
; TOKEN_FALSE        = 51
; TOKEN_AND_BOOL     = 52
; TOKEN_OR_BOOL      = 53
; TOKEN_CONST_NULL   = 54
; TOKEN_EQ_PTR       = 55
; TOKEN_NE_PTR       = 56
; TOKEN_EXTERN       = 57
; TOKEN_PTR          = 58
; TOKEN_VOID         = 59
; TOKEN_CALL_PTR     = 60
; TOKEN_CALL_VOID    = 61
; TOKEN_PTR_ADD      = 62
; TOKEN_LOAD_I64     = 63
; TOKEN_STORE_I64    = 64
; TOKEN_LOAD_U8      = 65
; TOKEN_STORE_I8     = 66
; TOKEN_CALL_I64     = 67
; TOKEN_RETURN_VOID  = 68
; TOKEN_MOD_I32      = 69
; TOKEN_LOAD_PTR     = 70
; TOKEN_STORE_PTR    = 71
; TOKEN_BOOL         = 72
; TOKEN_CALL_BOOL    = 73
; TOKEN_NE_I32       = 74
; TOKEN_EQ_I32       = 75
; TOKEN_GE_I32       = 76
; TOKEN_LE_I32       = 77
; TOKEN_MUL_I32      = 78
; TOKEN_DIV_I32      = 79
; TOKEN_LOAD_I32     = 80
; TOKEN_STORE_I32    = 81
; TOKEN_CAST_I32_TO_I64 = 82
; TOKEN_CONST_STRING_PTR = 83
; TOKEN_SUB_I64      = 84
; TOKEN_EQ_I64       = 85
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
; AST_CAST_EXPR       = 15
; AST_NULL_LITERAL   = 16
; AST_EXTERN         = 17
; AST_CALL_PTR_EXPR  = 18
; AST_CALL_VOID_EXPR = 19
; AST_STMT_LIST      = 20
; AST_PTR_ADD_EXPR   = 21
; AST_LOAD_I64_EXPR  = 22
; AST_STORE_I64_STMT = 23
; AST_LOAD_U8_EXPR   = 24
; AST_STORE_I8_STMT  = 25
; AST_CALL_I64_EXPR  = 26
; AST_RETURN_VOID_STMT = 27
; AST_LOAD_PTR_EXPR  = 28
; AST_STORE_PTR_STMT = 29
; AST_PARAM          = 30
; AST_CALL_BOOL_EXPR = 31
; AST_LOAD_I32_EXPR  = 32
; AST_STORE_I32_STMT = 33
; AST_CAST_I32_TO_I64_EXPR = 34
;
; Keep this list small. Stage 0 exists to cross the bootstrap gap, not to model
; the complete future Weave language.

; ----------------------------------------------------------------------------
; Binary operator constants
; ----------------------------------------------------------------------------
;
; BIN_ADD = 1
; BIN_RESERVED_2 = 2
; BIN_RESERVED_3 = 3
; BIN_RESERVED_4 = 4
; BIN_EQ  = 5
; BIN_NE  = 6
; BIN_LT  = 7
; BIN_LE  = 8
; BIN_GT  = 9
; BIN_GE  = 10
; BIN_ADD_I64 = 11
; BIN_MUL_I64 = 12
; BIN_LT_I64  = 13
; BIN_LE_I64  = 14
; BIN_NE_I64  = 15
; BIN_AND_BOOL = 16
; BIN_OR_BOOL  = 17
; BIN_EQ_PTR   = 18
; BIN_NE_PTR   = 19
; BIN_MOD_I32  = 20
; BIN_NE_I32   = 21
; BIN_EQ_I32   = 22
; BIN_GE_I32   = 23
; BIN_LE_I32   = 24
; BIN_MUL_I32  = 25
; BIN_DIV_I32  = 26
; BIN_SUB_I64  = 27
; BIN_EQ_I64   = 28

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
