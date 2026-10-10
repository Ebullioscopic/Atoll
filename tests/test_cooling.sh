#!/bin/sh
set -eu
COOLING_SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COOLING_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/atoll-cooling-tests.XXXXXX")
trap 'rm -rf "$COOLING_TEST_DIR"' EXIT HUP INT TERM
cd "$COOLING_SOURCE_ROOT"
xcrun swiftc DynamicIsland/services/FanSMCCore.swift DynamicIsland/services/FanControlWire.swift \
    tests/CoolingSessionHelper.swift -o "$COOLING_TEST_DIR/helper" -framework IOKit
xcrun swiftc DynamicIsland/services/FanSMCCore.swift DynamicIsland/services/FanControlWire.swift \
    DynamicIsland/services/CoolingHelperSession.swift tests/CoolingRegression.swift \
    -o "$COOLING_TEST_DIR/regression" -framework IOKit
"$COOLING_TEST_DIR/regression" "$COOLING_TEST_DIR/helper"
