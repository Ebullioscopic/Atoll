# Code Island Phase 7 Verification

**Status:** Implementation complete; signed/notarized artifact execution pending release CI

**Authorized:** 2026-08-04 by user approval

**Implementation completed:** 2026-08-04

## Delivered contract

- Atoll is the sole owner and persistence namespace for Code Island feature
  preferences. An upgrade with no Atoll preference keys receives the approved
  Phase 7 default snapshot; its presentation behavior remains compatible with
  Phase 6 and feature sounds remain off by default.
- The persistent dashboard can group the same urgency-ordered sanitized rows as
  one list, by status, or by provider. Terminal metadata can be retained
  indefinitely or for a bounded window. Active sessions never expire, cleanup
  is scheduled even when no later provider event arrives, and a failed archive
  replacement leaves the in-memory projection intact before a bounded retry.
- Smart suppression and completion presentation are explicit policy inputs.
  A disabled completion pop-out is state-only; changing suppression never gives
  Atoll authority to approve, deny, answer, or skip provider-owned decisions.
- Dex can be disabled or slowed, including a static zero-speed state. macOS
  Reduce Motion always pauses mascot animation. The settings sliders and icon
  actions expose explicit accessibility labels and values.
- Four selected upstream WAV files are packaged behind a semantic allowlist.
  Sounds are globally off by default and play only after Atoll selects a start,
  attention, completion, or verified-failure presentation. Suppressed,
  state-only, and compact processing events remain silent.
- A dedicated `CodeIsland.xcstrings` catalog covers the audited Code Island
  interface literals. It currently carries an English source/fallback only;
  this phase does not claim completed non-English translations.
- Guided adoption displays compatible legacy feature preferences but imports
  them only through a default-off consent toggle after successful activation.
  Values with no first-release effect are not offered, and every persisted key
  stays under `atoll.codeIsland.*`.

## Distribution boundary

`scripts/verify-code-island-bundle.sh` checks a built `Atoll.app` for:

- one `Atoll` executable and exactly one
  `Contents/Helpers/codeisland-bridge` helper;
- no standalone `CodeIsland.app`, updater, status-item, panel, or other known
  CodeIsland application executable anywhere in the product;
- exactly one `CodeIslandUI` resource bundle containing the dedicated
  localization table, the four exact hash-audited WAV assets, and the complete
  upstream MIT license;
- when `--require-signature` is selected, strict app/helper signatures,
  Developer ID Application identities, and matching team identifiers.

The ordinary CI workflow runs structural verification against its newly built
debug application. The release workflow runs the signature-required form after
final nested-code and app signing, then notarizes and staples the DMG and asks
Gatekeeper to assess that disk-image primary signature. These workflow checks
fail closed; this local implementation record does not substitute for their
credentialed result.

## Upgrade and rollback gates

- The Phase 6 schema-1 metadata archive is decoded unchanged; Phase 7 adds no
  rich content and requires no archive migration.
- An upgraded install with no Phase 7 preference keys loads the frozen default
  snapshot, and read-only discovery cannot persist imported preferences.
- Phase 5 reversible hook adoption, concurrent-hook preservation, missing-file
  restoration, deactivation, and pass-through shutdown regressions remain in
  the full suite and CI workflow.

## Verification evidence

Passed locally on 2026-08-04:

- `python3 -m unittest discover -v -s tests -p 'test_*.py'` — **47 tests
  passed** in 369.967 seconds, including every prior Code Island phase,
  privacy configuration, timer lifecycle, Phase 7 executable seams, upgrade/
  rollback preservation, and positive/negative artifact-verifier fixtures.
- Compatible-SDK `swift build` and `swift build -c release` for
  `Packages/CodeIsland` — both passed for `arm64-apple-macosx15.0` with the
  Command Line Tools macOS 15.4 SDK.
- Direct `swiftc -typecheck` passes for the Atoll preference store and host,
  the complete Code Island settings surface, and the notch/dashboard adapters
  against the built package modules.
- The release-mode SwiftPM resource bundle contains the exact expected sound
  and license hashes plus the dedicated string catalog.
- `bash -n` for the artifact verifier, JSON catalog parsing, workflow YAML
  parsing, Swift source parsing, project-file `plutil -lint`, security/control
  boundary searches, and `git diff --check` all passed.

This machine has Command Line Tools rather than the full Xcode application.
Its local SwiftPM test runner cannot import `XCTest`, so `swift test`, the full
Atoll application build, signed helper/app verification, notarization,
stapling, Gatekeeper assessment, and manual VoiceOver/visual review remain
transparent CI or release-machine gates. The workflows now require the
automatable portions before distribution.
