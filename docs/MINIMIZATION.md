# Stage 0 minimization rule

`weavec0` exists only to produce the pinned `weavec1` compiler.

A WIR form belongs in Stage 0 only when it occurs in the sources at
`WEAVEC1_BOOTSTRAP_COMMIT`. A compiler helper belongs only when it is reachable
from the command-line compilation path required for those sources.

Correctness and hardening code remain when they protect that path: bounded
memory operations, deterministic output, stable diagnostics, runtime ABI
validation, and reproducible SDK packaging are not optional language features.

The bootstrap-surface audit is the removal gate. A minimization change must
compile every pinned Stage 1 module and leave no Stage 0-only WIR forms in its
machine-readable report.
