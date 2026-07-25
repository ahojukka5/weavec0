#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(cd "$ROOT" && ./build.sh "$@")
bash "$ROOT/scripts/run-cli-tests.sh" \
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/cli-tests"
bash "$ROOT/scripts/run-parser-negative-matrix.sh" \
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/parser-negative-matrix"
bash "$ROOT/scripts/run-structural-negative-matrix.sh" \
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/structural-negative-matrix"
bash "$ROOT/scripts/run-extern-signature-negative-matrix.sh" \
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/extern-signature-negative-matrix"

printf '[tests] complete WIR, CLI, and generated negative ladders passed\n' >&2
