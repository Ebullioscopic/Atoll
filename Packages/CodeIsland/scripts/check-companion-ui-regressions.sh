#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

expect_present() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if ! grep -Fq "$pattern" "$file"; then
    fail "$label missing in $file"
  else
    printf 'ok: %s\n' "$label"
  fi
}

expect_absent() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -Fq "$pattern" "$file"; then
    fail "$label found in $file"
  else
    printf 'ok: %s\n' "$label"
  fi
}

expect_absent \
  "idle notch bar must not hardcode Claude" \
  'MascotView(source: "claude", status: .idle' \
  "Sources/CodeIsland/NotchPanelView.swift"

expect_absent \
  "iPhone live card should not duplicate the state mascot" \
  'PixelMascot(source: state.source, status: state.status, size: 42)' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_absent \
  "iPhone discovery card should not duplicate the compact island mascot" \
  'PixelMascot(source: "codex", status: connection.browsing ? .processing : .idle, size: 42)' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_present \
  "iPhone compact island keeps one small mascot" \
  'CompanionMascotView(source: connection.latestState?.source ?? "codex", status: compactStatus, size: 30)' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_present \
  "iPhone StandBy keeps one large mascot" \
  'CompanionMascotView(source: state.source, status: state.status, size: 78)' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_absent \
  "iPhone app should not use the temporary hand-drawn PixelMascot" \
  'PixelMascot(' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_present \
  "iPhone mascot router reuses Mac Dex mascot view" \
  'DexView(status: status, size: size)' \
  "ios/CodeIslandCompanion/Shared/SharedMascotView.swift"

expect_absent \
  "Live Activity should not use the temporary WidgetPixelMascot" \
  'WidgetPixelMascot' \
  "ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift"

expect_present \
  "Live Activity uses shared Mac mascot views" \
  'SharedMascotView(source: state.source, status: MascotAgentStatus(state.status), size: 20)' \
  "ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift"

expect_present \
  "iPhone portrait view scrolls as one page" \
  'ScrollView(.vertical) {' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_present \
  "Live Activity carries question text" \
  'var questionText: String?' \
  "ios/CodeIslandCompanion/Shared/CodeIslandActivityAttributes.swift"

expect_absent \
  "iPhone compact bar should not repeat online text" \
  'Text(active ? "在线"' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_absent \
  "iPhone metadata should not show no-tool placeholder chip" \
  '"无工具调用"' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"

expect_absent \
  "Dynamic Island expanded view should not duplicate question in center region" \
  'DynamicIslandExpandedRegion(.center)' \
  "ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift"

expect_present \
  "Dynamic Island expanded trailing uses adaptive status" \
  'ExpandedTrailingStatus(state: context.state)' \
  "ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift"

expect_present \
  "Dynamic Island single-session expanded trailing stays dot-only" \
  'ExpandedStatusDot(state: state)' \
  "ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift"

expect_absent \
  "Dynamic Island expanded trailing should not use a text badge" \
  'private struct ExpandedStatusBadge' \
  "ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift"

expect_present \
  "Dynamic Island expanded status label stays in bottom metadata" \
  'Text(state.compactStatusLabel)' \
  "ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift"

expect_present \
  "core state payload carries question details" \
  'public let question: AppleCompanionQuestionPayload?' \
  "Sources/CodeIslandCore/AppleCompanionPayload.swift"

expect_present \
  "iPhone state model carries question details" \
  'let question: CompanionQuestionPayload?' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/CompanionModels.swift"

expect_present \
  "iPhone can send selected question answers" \
  'func sendAnswer(_ answer: String)' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/CompanionConnection.swift"

expect_present \
  "Mac handles companion question answers" \
  'func answerCompanionQuestion(_ answer: String)' \
  "Sources/CodeIsland/AppState.swift"

expect_absent \
  "iPhone BLE central must not be lazy because background restoration needs early registration" \
  'lazy var centralManager' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/CompanionBluetoothCentral.swift"

expect_present \
  "iPhone BLE central uses a restoration identifier" \
  'CBCentralManagerOptionRestoreIdentifierKey' \
  "ios/CodeIslandCompanion/CodeIslandCompanion/CompanionBluetoothCentral.swift"

if (( failures > 0 )); then
  printf '\n%d companion UI/protocol regression check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll companion UI/protocol regression checks passed.\n'
