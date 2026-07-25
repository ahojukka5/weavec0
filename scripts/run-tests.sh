#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(cd "$ROOT" && ./build.sh "$@")
bash "$ROOT/scripts/run-cli-tests.sh" \
  "$ROOT/weavec0" "$ROOT/build/bootstrap-tests/cli-tests"

printf '[tests] complete WIR and CLI ladders passed\n' >&2
