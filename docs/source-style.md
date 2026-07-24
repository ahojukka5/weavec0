# weavec0 source style

The hand-written LLVM IR modules under `src/` follow a small, consistent set
of documentation conventions. These rules are canonical for this repository;
`weavec1`, `weavec-bootstrap`, and `weavec` use corresponding conventions in
their own source trees.

## File header

Every `src/NN_*.ll` opens with a banner-bounded block stating:

- the filename;
- a one-line role;
- a `Responsibilities:` list;
- a `Boundary:` note describing what does not belong in the file.

```llvm
; =============================================================================
; 04_lexer.ll
;
; Source -> token stream for the Stage 0 bootstrap compiler.
;
; Responsibilities:
;   - skip whitespace and `;` line comments
;   - recognise parens, identifiers, integer literals, string literals
;   - classify keywords and WIR operator names against a fixed table
;
; Boundary:
;   No grammar / no AST. The lexer is intentionally a flat dispatch chain.
; =============================================================================
```

## Section banners

Group related definitions under a section banner:

```llvm
; ----------------------------------------------------------------------------
; Token stream layout
; ----------------------------------------------------------------------------
```

Use searchable compiler concepts rather than merely repeating the following
function names.

## Function docstrings

Cross-module functions carry a structured block immediately above `define`:

```llvm
; ----------------------------------------------------------------------------
; weave_lex
;
; Module entry point. Tokenise the entire %weave.Source into the supplied
; %weave.Tokens stream.
;
; Parameters:
;   source - %weave.Source* with byte data and length already populated.
;   tokens - %weave.Tokens* initialised via weave_tokens_init.
;
; Returns:
;   0 on success.
;   1 on failure (null args, unrecognised byte, dispatch sentinel -1).
;
; Notes:
;   The lexer does not allocate or take ownership of `source` or `tokens`.
; ----------------------------------------------------------------------------

define i32 @weave_lex(ptr %source, ptr %tokens) {
```

For status-code functions, document the meaning of zero and non-zero values.
For functions returning an index, document the failure sentinel.

Small accessors and leaf helpers used only within one file may keep a one-line
purpose comment.

## Notes blocks

Use `Notes:` for design tradeoffs a future maintainer could otherwise miss,
such as:

- auditability-oriented linear dispatch chains;
- intentionally discarded parser detail;
- separate string constants for operand and destination formatting.

Comments should explain why a non-obvious choice exists rather than restating
the LLVM IR below it.

## Spacing and trailing whitespace

- One blank line between function blocks.
- Section banners separated by a blank line above and below.
- No trailing whitespace.
- Every file ends with a newline.
