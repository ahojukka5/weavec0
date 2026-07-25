# Documentation

`weavec0` is the hand-written Stage 0 seed for the Weave compiler chain. Its
documentation describes the narrow bootstrap profile, runtime and SDK boundaries,
and the evidence used to keep the implementation small.

## Documents

- [Architecture](architecture.md) — compiler modules, data flow, runtime boundary,
  and verification layers.
- [WIR bootstrap profile](wir.md) — relationship between WIR v2 and the smaller
  Stage 0 implementation profile.
- [Minimization](minimization.md) — evidence required before code or forms may be
  removed.
- [Coverage](coverage.md) — function, basic-block, branch-outcome, and bootstrap
  surface measurements.
- [Bootstrap SDK](bootstrap-sdk.md) — published binary boundary consumed by
  `weavec1`.
- [Source style](source-style.md) — conventions for the hand-written LLVM IR.
- [Releasing](releasing.md) — SDK packaging, validation, and publication.
- [Contributing](../CONTRIBUTING.md) — change policy and required checks.
- [Changelog](../CHANGELOG.md) — released and pending changes.

## Naming policy

Files under `docs/` use lowercase kebab-case names. Conventional repository-root
files such as `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, and
`NOTICE` retain their standard names.
