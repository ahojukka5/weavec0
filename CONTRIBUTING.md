# Contributing to weavec0

Thanks for your interest in `weavec0`. Before opening a PR or filing an
issue, please read the **Bootstrap Strategy** section of the
[README](README.md). The bar for what gets merged here is very specific:
`weavec0` exists only to be small enough to be trustworthy *and* large
enough to compile the next compiler (`weavec1`). Everything else is out
of scope.

## Principles

- **No feature without a test.** A patch that adds an admitted operator,
  AST kind, or syntactic shape must come with a test in
  [`test/manifest.txt`](test/manifest.txt) that exercises it end-to-end
  through `./build.sh`.
- **Add to the dispatch chains, don't rewrite them.** The lexer, parser,
  and emitter are deliberately flat dispatch chains over numeric tags.
  Compactness is sacrificed for auditability. New behaviour goes in as
  one more arm, not as a refactor.
- **Output style matters.** The emitted LLVM IR is a deliverable; the
  test ladder's golden fixtures pin its exact shape. After any output
  change, run `./build.sh --regen-goldens`, then review the resulting
  `git diff` for unintended differences before committing.
- **Match the source style.** See
  [`docs/source-style.md`](docs/source-style.md). Every module file
  opens with a `Responsibilities:` block; every cross-module entry-point
  function carries `Parameters:` / `Returns:` docstrings; `Notes:`
  blocks capture non-obvious design tradeoffs.

## What does NOT belong here

Refer to the **Important Non-Goals** section of the README for the
canonical list. In short: optimisation, advanced types, packages,
borrow checking, generics, macros, beautiful diagnostics, IDE tooling,
incremental or parallel compilation, production performance. Those all
belong in later compiler stages.

## Workflow

1. Fork and create a feature branch.
2. Edit the relevant `src/*.ll`, add or update a test under `test/`,
   and update [`test/manifest.txt`](test/manifest.txt).
3. Run `./build.sh` locally — every test must pass.
4. If your change affects emitter output, rerun
   `./build.sh --regen-goldens` and commit the regenerated `.expected.ll`
   alongside your source change.
5. Open a PR. CI will rerun `./build.sh` on Linux and macOS; the merge
   bar is "CI green and the change matches the principles above".

## Licensing

By submitting a contribution, you agree that your contribution is
licensed under the Apache License, Version 2.0 (see
[`LICENSE`](LICENSE)).
