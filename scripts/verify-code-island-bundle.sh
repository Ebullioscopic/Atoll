#!/bin/bash

set -euo pipefail

fail() {
  printf 'Code Island bundle verification failed: %s\n' "$1" >&2
  exit 1
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  fail "usage: $0 /path/to/Atoll.app [--require-signature]"
fi

APP_PATH=${1%/}
SIGNATURE_MODE=${2:-}
if [ -n "$SIGNATURE_MODE" ] && [ "$SIGNATURE_MODE" != "--require-signature" ]; then
  fail "unknown option: $SIGNATURE_MODE"
fi

[ "$(basename "$APP_PATH")" = "Atoll.app" ] \
  || fail "the artifact must be named Atoll.app"
[ -d "$APP_PATH/Contents" ] || fail "Atoll.app has no Contents directory"
[ -x "$APP_PATH/Contents/MacOS/Atoll" ] \
  || fail "Atoll's main executable is missing or not executable"

CODEISLAND_APP=$(find "$APP_PATH" -type d -name 'CodeIsland.app' -print -quit)
if [ -n "$CODEISLAND_APP" ]; then
  fail "a standalone CodeIsland application is present"
fi

HELPER="$APP_PATH/Contents/Helpers/codeisland-bridge"
[ -f "$HELPER" ] || fail "the codeisland-bridge helper is missing"
[ -x "$HELPER" ] || fail "the codeisland-bridge helper is not executable"

HELPER_COUNT=$(find "$APP_PATH" -type f -name 'codeisland-bridge' -print | wc -l | tr -d '[:space:]')
[ "$HELPER_COUNT" = "1" ] || fail "the artifact must contain exactly one Code Island helper"

FORBIDDEN_EXECUTABLE=$(find "$APP_PATH/Contents" -type f -perm -111 \( \
  -name 'CodeIsland' -o \
  -name 'codeisland' -o \
  -name 'CodeIslandUpdater' -o \
  -name 'CodeIslandStatusItem' -o \
  -name 'CodeIslandNotchPanel' \
\) -print -quit)
[ -z "$FORBIDDEN_EXECUTABLE" ] \
  || fail "a forbidden standalone CodeIsland executable is present"

RESOURCES="$APP_PATH/Contents/Resources"
[ -d "$RESOURCES" ] || fail "Atoll.app has no Resources directory"

RESOURCE_BUNDLE_COUNT=$(find "$RESOURCES" -type d -name '*CodeIslandUI*.bundle' -print | wc -l | tr -d '[:space:]')
[ "$RESOURCE_BUNDLE_COUNT" = "1" ] \
  || fail "the artifact must contain exactly one CodeIslandUI resource bundle"
RESOURCE_BUNDLE=$(find "$RESOURCES" -type d -name '*CodeIslandUI*.bundle' -print | head -n 1)

SOUNDS_DIRECTORY="$RESOURCE_BUNDLE/Sounds"
[ -d "$SOUNDS_DIRECTORY" ] || fail "the selected Code Island sounds directory is missing"
for sound in 8bit_approval.wav 8bit_complete.wav 8bit_error.wav 8bit_start.wav; do
  [ -f "$SOUNDS_DIRECTORY/$sound" ] \
    || fail "the selected Code Island sounds are incomplete: missing $sound"
  case "$sound" in
    8bit_approval.wav)
      EXPECTED_SOUND_HASH=fde00186690edd954b745b54ed4da2176e18dae0ff6e5651af1e77fdec75bcdb
      ;;
    8bit_complete.wav)
      EXPECTED_SOUND_HASH=ab9fcc1972971f6619a237faf4bcd492ab2010306de82bcb8f86f51858c7488f
      ;;
    8bit_error.wav)
      EXPECTED_SOUND_HASH=bf521d2824625c4b6478cf8a062781ea555424fdcbc1e5375a16ea327fa90bf7
      ;;
    8bit_start.wav)
      EXPECTED_SOUND_HASH=3040eeaf607d888616e7c5d2e1c5a9e0d626d6134d30d23be82da723da1ad2f1
      ;;
  esac
  SOUND_HASH=$(shasum -a 256 "$SOUNDS_DIRECTORY/$sound" | awk '{print $1}')
  [ "$SOUND_HASH" = "$EXPECTED_SOUND_HASH" ] \
    || fail "a selected Code Island sound is not the audited upstream asset: $sound"
done
SOUND_COUNT=$(find "$SOUNDS_DIRECTORY" -maxdepth 1 -type f -name '*.wav' -print | wc -l | tr -d '[:space:]')
[ "$SOUND_COUNT" = "4" ] \
  || fail "the selected Code Island sounds directory must contain exactly four WAV files"

LOCALIZATION_COUNT=$(find "$RESOURCE_BUNDLE" -type f \( -name 'CodeIsland.strings' -o -name 'CodeIsland.xcstrings' \) -print | wc -l | tr -d '[:space:]')
[ "$LOCALIZATION_COUNT" -ge 1 ] \
  || fail "the Code Island localization table is missing"

LICENSE_PATH="$RESOURCE_BUNDLE/ThirdPartyNotices/CodeIsland-LICENSE.txt"
[ -f "$LICENSE_PATH" ] || fail "the bundled CodeIsland MIT license is missing"
grep -Fq 'MIT License' "$LICENSE_PATH" \
  || fail "the bundled CodeIsland MIT license is invalid"
grep -Fq 'Copyright (c) 2026 wxtsky' "$LICENSE_PATH" \
  || fail "the bundled CodeIsland MIT attribution is invalid"
LICENSE_HASH=$(shasum -a 256 "$LICENSE_PATH" | awk '{print $1}')
[ "$LICENSE_HASH" = "6d17ee2bd4e0ff274046102a9582b095dd1e1b59e259bbc4c563ac5453e83c41" ] \
  || fail "the bundled CodeIsland MIT license is incomplete"

if [ "$SIGNATURE_MODE" = "--require-signature" ]; then
  command -v codesign >/dev/null 2>&1 || fail "codesign is unavailable"
  codesign --verify --strict --verbose=2 "$HELPER" \
    || fail "the Code Island helper signature is invalid"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
    || fail "the Atoll application signature is invalid"

  APP_SIGNATURE=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)
  HELPER_SIGNATURE=$(codesign -dv --verbose=4 "$HELPER" 2>&1)
  grep -q '^Authority=Developer ID Application:' <<< "$APP_SIGNATURE" \
    || fail "Atoll is not signed with a Developer ID Application identity"
  grep -q '^Authority=Developer ID Application:' <<< "$HELPER_SIGNATURE" \
    || fail "the Code Island helper is not signed with a Developer ID Application identity"

  APP_TEAM=$(sed -n 's/^TeamIdentifier=//p' <<< "$APP_SIGNATURE")
  HELPER_TEAM=$(sed -n 's/^TeamIdentifier=//p' <<< "$HELPER_SIGNATURE")
  [ -n "$APP_TEAM" ] || fail "Atoll's signing team is unavailable"
  [ "$APP_TEAM" = "$HELPER_TEAM" ] \
    || fail "Atoll and the Code Island helper have different signing teams"
fi

printf 'Code Island bundle verification passed: %s\n' "$APP_PATH"
