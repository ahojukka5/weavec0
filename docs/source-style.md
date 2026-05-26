# weavec0 source style

The hand-written LLVM IR modules under `src/` follow a small, consistent set
of documentation conventions. The rules below are the canonical statement
for this repository; the rest of the Weave compiler chain (`weavec1`,
`weavec2`, ...) uses the same conventions in its own source trees.

## File header

Every `src/NN_*.ll` opens with a banner-bounded block stating:

- the filename,
- a one-line role (what this module is, in plain prose),
- a `Responsibilities:` bullet list,
- a `Boundary:` note saying what does **not** belong in the file.

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

Group related defines under a section banner:

```llvm
; ----------------------------------------------------------------------------
; Token stream layout
; ----------------------------------------------------------------------------
```

Use section names that match searchable compiler concepts (parser entry
points, operator dispatch, block emission, AST storage, …) rather than
restating the function names that follow.

## Function docstrings

The cross-module / public functions in each module carry a structured doc
block immediately above the `define`:

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

For status-code functions, say explicitly what `0` and non-zero mean.
For functions that return an index, say what the failure sentinel is
(`-1`, `i64 -1`, etc.).

Internal helpers (small accessors, leaf functions used only in this file)
may keep a one-line purpose comment instead of the full block.

## Notes blocks

Use `Notes:` to capture design tradeoffs the next reader could miss:

- linear dispatch chains chosen over compact tables (auditability over
  compactness),
- manual paren-balancing that captures only a name and discards body
  tokens (a deliberate Stage 0 simplification),
- the split between `@weave.emit.tmp_prefix` and `@weave.emit.indent_tmp`
  cstrings (operand-position vs destination-position).

Comments should explain *why* a non-obvious choice was made, not restate
*what* the code does — the LLVM IR right below already says what.

## Spacing and trailing whitespace

- One blank line between function blocks.
- Section banners separated by a blank line above and below.
- No trailing whitespace; every file ends in a newline.
