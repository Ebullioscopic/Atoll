# Code Island Phase 3 Verification

**Status:** Complete

**Date:** 2026-08-04

**Scope:** Atoll host shell only; no provider activation, discovery, listener,
hook installation, repair, adoption, or live-activity presentation

## Delivered contract

- Atoll links `CodeIslandCore`, `CodeIslandRuntime`, and `CodeIslandUI` from the
  local package. The `codeisland-bridge` executable remains unlinked and is not
  copied into the application.
- The standard Atoll tab row contains a persistent **Code Island** entry
  immediately before **Terminal**, including before provider activation and
  while no session exists.
- The notch content switch routes that entry to one Atoll-owned view. The
  setup and idle states use Atoll geometry, navigation, typography, and
  controls; they contain no provider content.
- Atoll owns the embedded host lifecycle. App startup starts only the inert
  host shell, and app shutdown clears its transient state. The contained
  runtime still reports `isRunning == false` and starts no service.
- A pure adapter maps sanitized metadata transitions to content-free activity
  intents. It does not select a tab, show a pop-out, play a sound, suppress an
  event, or otherwise present UI; those Atoll policies remain deferred to
  Phase 6.
- Atoll Settings contains a searchable, read-only **Code Island** page under
  Developer. The setup dashboard opens this destination directly. It reports
  Codex as **Monitoring**, activation as unavailable, and explicitly states
  that questions and approvals stay in Codex.

## Safety boundary

Phase 3 performs no coding-tool configuration writes. The Atoll host does not
construct a metadata file store, installer, hook server, or network listener.
It receives no provider events because no provider is activated. The only
current dashboard state reached by the app is setup-required; the idle state
is a tested contract for the later activation phase.

The activity subject contains only provider, opaque session identity,
sanitized project display name, origin-navigation handles, and transition
time. No prompt, response, command, question, option, answer, tool input, or
raw payload crosses into the UI or activity-intent models. Atoll has no
approval, denial, always-allow, or answer control.

## Verification evidence

The Phase 3 work was developed through three red-to-green contract slices:

1. Persistent tab plus setup/idle dashboard state.
2. Inert Atoll lifecycle plus sanitized activity intents.
3. Read-only settings destination plus direct navigation.

Local verification completed:

- All 21 Python/standalone-Swift repository regressions pass.
- `CodeIslandCore`, `CodeIslandRuntime`, `CodeIslandUI`, and the helper compile
  in both debug and release Swift package builds.
- The new Atoll host and settings views type-check against the built package
  modules.
- All changed Atoll Swift sources pass parser validation.
- `project.pbxproj` passes `plutil -lint`.
- `git diff --check` passes.

The local developer selection is Command Line Tools rather than full Xcode,
so a complete `xcodebuild` application build is delegated to the existing CI
matrix. CI now runs the Phase 3 contracts before compiling Atoll on its macOS
15 and macOS 26 runners.

## Verification commands

Run from the Atoll repository root:

```sh
python3 -m unittest discover -v -s tests -p 'test_*.py'
python3 -m unittest \
  tests.test_code_island_phase_three_dashboard \
  tests.test_code_island_phase_three_activity \
  tests.test_code_island_phase_three_settings
swift build --package-path Packages/CodeIsland --disable-sandbox
swift build -c release --package-path Packages/CodeIsland --disable-sandbox
swift test --package-path Packages/CodeIsland
plutil -lint DynamicIsland.xcodeproj/project.pbxproj
git diff --check
```

On a Command Line Tools installation whose default target disagrees with the
selected SDK, use the matching explicit target triple and a writable module
cache. `swift test` still requires the XCTest module supplied by full Xcode.

## Next authorization gate

Phase 4 is not authorized. Read-only provider discovery, consent, listener
startup, hook installation, reversible removal, socket-conflict handling, and
existing-CodeIsland adoption remain unchanged and inactive.
