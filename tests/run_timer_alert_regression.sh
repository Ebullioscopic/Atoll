#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
scratch_dir=$(mktemp -d)
trap 'rm -rf "$scratch_dir"' EXIT
swiftc -module-cache-path "$scratch_dir/cache" \
  DynamicIsland/managers/TimerAlertController.swift \
  tests/TimerAlertRegression.swift -o "$scratch_dir/regression"
"$scratch_dir/regression"
