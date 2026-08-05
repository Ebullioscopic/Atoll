# Code Island Phase 6 Verification

**Status:** Complete

**Date:** 2026-08-04

**Scope:** Multi-session dashboard, compact agent activity, selective pop-outs,
Atoll-owned arbitration, origin handoff, and exact-origin suppression. Phase 7
release hardening remains unauthorized.

## Delivered contract

### Metadata-only multi-session dashboard

- `CodeIslandDashboardProjection` accepts only `SessionMetadata`. It cannot
  carry prompt text, commands, questions, answers, tool input, or raw hook
  payloads into the UI.
- Dashboard rows are ordered by the frozen urgency contract: waiting first,
  then working, then recent completion/failure. The longest-waiting session is
  first; working and recent rows are newest first; ties have stable provider and
  opaque-session ordering.
- Cancelled and ended sessions are omitted. Setup and idle states remain in the
  persistent Code Island tab, and active rows expose only agent, project/session
  identity, content-free status, timestamp, and an **Open in origin** action.
- The tab keeps Atoll typography, controls, scrolling, geometry, settings
  navigation, and accessibility structure.

### Pure presentation policy and deterministic queue

- The provider runtime still emits sanitized state and presentation intents;
  it does not select tabs, open Atoll, activate applications, or play UI.
- A pure policy accepts an intent plus Atoll's occupancy projection:
  `available`, `noncritical`, or `systemOrPrivacy`. It returns present, enqueue,
  suppress, state-only, or dismiss.
- System, privacy, lock, and protected HUD states win. A blocking attention
  handoff may interrupt noncritical content. Start/completion/failure pop-outs
  queue while any higher activity is present.
- Deferred work has stable semantic priority: attention, failure, completion,
  then start. Newer state for the same provider/session replaces an older
  queued presentation instead of producing stale duplicates.
- Start animation lasts two seconds, completion five seconds, and a future
  verified failure presentation four seconds. Blocking handoffs persist until
  the provider changes state or ends. Codex currently cannot emit a verified
  failure intent, so that treatment remains capability-gated.
- Routine working updates change dashboard/compact state only. No ordinary
  event opens the Code Island tab. Starts and completions never steal focus.

### Atoll-hosted CodeIsland identity

- The active presentation uses a focused, payload-free extraction of
  CodeIsland's Dex pixel-cloud mascot and motion. It is a reusable SwiftUI view,
  not CodeIsland's panel, application shell, or window controller.
- Atoll owns the containing notch shape, width, height, transitions, tab route,
  and lifecycle. No `NSPanel`, second application, updater, settings window, or
  status item was introduced.
- When the notch is free, a working Codex session receives the compact agent
  live activity. When music is the only compatible owner and its secondary
  slot is free, Dex appears there as a small secondary indicator. It otherwise
  yields to timers, reminders, recording, transfers, extensions, and similar
  live activity.
- Clicking the compact activity is user-initiated navigation to the persistent
  Code Island tab. A blocking handoff contains no decision control and offers
  only **Open in origin**.

### Exact-origin suppression and handoff

- Suppression requires an exact session-specific handle and no conflicting
  known handle. An application bundle match alone always remains uncertain.
- Phase 6 can positively verify Terminal.app by selected-tab TTY and iTerm2 by
  selected session ID. A different tab/pane/app produces a non-match; an
  unsupported or application-only observation remains unknown. Both cases
  present rather than suppress.
- Visibility scripts run away from the main UI path and the frontmost
  application is rechecked after the query to reject a stale result.
- The managed helper resolves its controlling `/dev/tty` as a navigation-only
  handle when Codex delivers hook input through a pipe, making Terminal.app's
  selected-tab TTY comparison reachable without reading terminal contents.
- Origin handoff precisely selects a matching Terminal.app tab or iTerm2
  session when its handle is available. Other origins receive only a
  user-initiated application activation. No provider decision or answer is
  generated on either path.

## Provider boundary

Codex remains **Monitoring**. The verified `PermissionRequest` lifecycle event
can create a metadata-only approval handoff while Codex's own prompt stays in
control. Interactive question observation remains unavailable, and rich tool
output is still not inspected to infer failure. Phase 6 did not promote the
provider capability or modify the Phase 5 bridge/installer contract.

Imported rich views, other provider mascots/icons, and feature-sound resources
remain quarantined. Resource selection, signing, accessibility, localization,
and release/rollback exercises belong to the separately authorized Phase 7
hardening pass.

## Verification evidence

Local verification completed:

- All 28 repository Python-driven regressions passed in 267.982 seconds. The
  suite recompiles and executes the Phase 2 through Phase 6 Swift contract
  programs plus the real Phase 5 helper/listener/runtime regressions.
- The Phase 6 executable runner proves urgency ordering, filtering, occupancy
  policy, blocking-vs-system priority, primary/secondary compact behavior,
  deterministic deferred ordering, positive exact matching, application-only
  uncertainty, false-match presentation, and exact-match suppression.
- Focused XCTest coverage for the same Core/Runtime policy was added for CI.
- The Swift package builds successfully in Debug and Release against the local
  macOS 15.4 SDK with writable isolated caches and an explicit macOS target.
- A clean Debug package build plus the focused host/notch and AppKit-origin
  type checks also pass at Atoll's macOS 14.6 deployment target.
- The actual Atoll host plus notch route type-check against the built package
  modules using only a stubbed AppKit origin boundary. The actual origin adapter
  separately type-checks against AppKit and built Code Island modules.
- Every changed Swift file passes parser validation. `git diff --check` and the
  package-boundary assertions pass.

This machine has Command Line Tools rather than full Xcode. `swift test`
reaches the test target but fails at the pre-existing local limitation
`no such module 'XCTest'`. The complete Atoll application build, real resource
embedding, accessibility/localization QA, and signing/notarization remain CI or
Phase 7 gates.

## Verification commands

Run from the Atoll repository root:

```sh
python3 -m unittest discover -v -s tests -p 'test_*.py'
python3 -m unittest tests.test_code_island_phase_six_presentation
swift build --package-path Packages/CodeIsland --disable-sandbox
swift build -c release --package-path Packages/CodeIsland --disable-sandbox
swift test --package-path Packages/CodeIsland
plutil -lint DynamicIsland.xcodeproj/project.pbxproj
git diff --check
```

On a Command Line Tools installation with the newer default SDK/compiler
mismatch, select a compatible SDK and set writable module, cache, and scratch
paths as in the recorded local build invocation.

## Phase 7 authorization gate

Phase 7 is not authorized. This phase does not claim complete application
regression, visual/accessibility/localization QA, sound/resource packaging,
helper embedding/signing in a newly built app, notarization, upgrade, or
rollback verification.
