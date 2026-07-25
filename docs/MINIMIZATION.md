# Stage 0 minimization rule

`weavec0` exists only to produce the pinned `weavec1` compiler.

A WIR form belongs in Stage 0 only when it occurs in the source modules at
`WEAVEC1_BOOTSTRAP_COMMIT`. Stage 0 accepts WIR core version 2 but implements a
strict bootstrap profile rather than the complete Stage 1 language surface.

A compiler helper belongs only when it is reachable from the command-line
compilation path required for those sources. Correctness and hardening code
remain when they protect that path: bounded memory operations, deterministic
output, stable diagnostics, runtime ABI validation, and reproducible SDK
packaging are not optional language features.

The bootstrap-surface audit is the removal gate. It must compile every pinned
Stage 1 module, report no Stage 0-only keyword, report no unreachable Stage 0
function, and find no residual implementation of removed compatibility forms.
