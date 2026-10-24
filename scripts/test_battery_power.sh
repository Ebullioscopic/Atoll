#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -emit-executable \
  "$repo_root/DynamicIsland/managers/BatteryPowerReading.swift" \
  "$repo_root/tests/BatteryPowerRegression.swift" \
  -o "$build_dir/battery-power-regression"
"$build_dir/battery-power-regression"
