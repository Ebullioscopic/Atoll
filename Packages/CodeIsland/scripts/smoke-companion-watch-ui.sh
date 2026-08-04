#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj"
SCHEME="CodeIslandWatchApp"
DERIVED_DATA="$ROOT/.build/CompanionWatchUISmokeDerivedData"
BUNDLE_ID="top.fengye.CodeIslandCompanion.watchkitapp"
PAGES=(status message actions activity)

if [[ "$#" -gt 0 ]]; then
  WATCH_NAMES=("$@")
else
  WATCH_NAMES=("Apple Watch SE 3 (40mm)" "Apple Watch Series 11 (46mm)")
fi

find_watch_udid() {
  local name="$1"
  xcrun simctl list devices available |
    grep -m 1 "    ${name} (" |
    sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'
}

for watch_name in "${WATCH_NAMES[@]}"; do
  udid="$(find_watch_udid "$watch_name")"
  if [[ -z "$udid" ]]; then
    printf 'No available watch simulator named "%s"; skipping.\n' "$watch_name" >&2
    continue
  fi

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=watchOS Simulator,id=${udid}" \
    -derivedDataPath "$DERIVED_DATA" \
    build

  app="$DERIVED_DATA/Build/Products/Debug-watchsimulator/CodeIslandWatchApp.app"
  if [[ ! -d "$app" ]]; then
    printf 'Built watch app was not found at %s\n' "$app" >&2
    exit 1
  fi

  xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$app"

  slug="$(tr '[:upper:] ()' '[:lower:]---' <<<"$watch_name" | tr -s '-')"
  for page in "${PAGES[@]}"; do
    screenshot="$ROOT/.build/companion-watch-ui-${slug}-${page}.png"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch \
      "$udid" \
      "$BUNDLE_ID" \
      -CodeIslandWatchSmokeState question \
      -CodeIslandWatchSmokePage "$page" >/dev/null
    sleep 2
    xcrun simctl io "$udid" screenshot "$screenshot" >/dev/null
    printf 'Companion watch UI smoke screenshot (%s, %s): %s\n' "$watch_name" "$page" "$screenshot"
  done
done
