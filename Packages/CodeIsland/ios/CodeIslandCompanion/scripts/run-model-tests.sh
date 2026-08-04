#!/bin/bash
# Behavior tests for CompanionModels tolerant decoding (#246).
# Runs on macOS without the watchOS SDK: compiles the real model file plus
# the assertions in companion-models-test.swift and executes them.
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp companion-models-test.swift "$TMP/main.swift"
swiftc -o "$TMP/model-tests" ../CodeIslandCompanion/CompanionModels.swift ../Shared/L10n.swift "$TMP/main.swift"
"$TMP/model-tests"
