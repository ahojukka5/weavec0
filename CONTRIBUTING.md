# Contributing to weavec0

Thanks for your interest in `weavec0`. The scope is intentionally narrow:
Stage 0 must remain small enough to audit and complete enough to bootstrap
`weavec1` through a published, versioned SDK.

Read the design rules and known limitations in the
[README](README.md) before changing the compiler or runtime ABI.

## Principles

- **No feature without an end-to-end test.** Add every admitted operator, AST
  shape, diagnostic, or extern case to
  [`test/manifest.txt`](test/manifest.txt).
- **Preserve auditability.** The lexer, parser, and emitter deliberately use
  explicit dispatch chains. Prefer one clear arm over a speculative refactor.
- **Preserve deterministic LLVM output.** After an intentional emitter change,
  run `./build.sh --regen-goldens` and review the complete fixture diff.
- **Treat WIR and the runtime ABI as versioned contracts.** A downstream-visible
  change requires a new SDK release before dependency pins are updated.
- **Keep source documentation current.** Follow
  [`docs/source-style.md`](docs/source-style.md) for LLVM module and function
  documentation.

## What does not belong here

Optimisation, advanced typing, packages, borrow checking, generics, macros,
IDE tooling, incremental compilation, and production compiler architecture
belong in later stages.

Do not add functionality merely because it could fit in Stage 0. Add only what
the stable bootstrap chain actually requires.

## Development workflow

1. Create a focused branch.
2. Edit the relevant `src/*.ll` or runtime file.
3. Add or update the matching test fixture and manifest entry.
4. Run `./build.sh` and confirm all positive and negative cases pass.
5. Regenerate and review goldens when emitter output changes.
6. Update README, changelog, SDK, or ABI documentation when behavior changes.
7. Open a pull request.

CI validates the source build on Linux and macOS. The release workflow also
builds glibc and musl SDKs, rejects dynamically linked compiler executables, and
runs SDK-only smoke tests.

## SDK-affecting changes

A change affects the SDK when it modifies:

- the WIR accepted by `bin/weavec0`;
- emitted LLVM behavior;
- bootstrap object or bitcode contents;
- runtime symbols or signatures;
- archive paths or manifest fields.

For such a change:

1. document compatibility and migration effects;
2. update [`VERSION`](VERSION) intentionally;
3. verify both libc variants;
4. publish the new SDK;
5. only then update downstream pins such as `WEAVEC0_VERSION`.

See [`docs/BOOTSTRAP_SDK.md`](docs/BOOTSTRAP_SDK.md) and
[`RELEASING.md`](RELEASING.md).

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
