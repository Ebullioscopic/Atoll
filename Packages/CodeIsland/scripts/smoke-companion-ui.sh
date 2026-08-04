#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIM_NAME="${1:-iPhone 17 Pro}"
PROJECT="ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj"
SCHEME="CodeIslandCompanion"
DERIVED_DATA="$ROOT/.build/CompanionUISmokeDerivedData"
BUNDLE_ID="top.fengye.CodeIslandCompanion"
MODES=(idle interrupted question long)

UDID="$(
  xcrun simctl list devices available |
    grep -m 1 "    ${SIM_NAME} (" |
    sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'
)"

if [[ -z "${UDID}" ]]; then
  printf 'No available simulator named "%s"; falling back to generic iOS build.\n' "$SIM_NAME" >&2
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'generic/platform=iOS' build
  exit 0
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/CodeIslandCompanion.app"
if [[ ! -d "$APP" ]]; then
  printf 'Built app was not found at %s\n' "$APP" >&2
  exit 1
fi

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

for mode in "${MODES[@]}"; do
  SCREENSHOT="$ROOT/.build/companion-ui-${mode}.png"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -CodeIslandCompanionMockState "$mode" >/dev/null
  sleep 2
  xcrun simctl io "$UDID" screenshot "$SCREENSHOT"
  printf 'Companion UI smoke screenshot (%s): %s\n' "$mode" "$SCREENSHOT"
done
