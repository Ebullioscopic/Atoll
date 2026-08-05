# Code Island Phase 4 Verification

**Status:** Complete

**Date:** 2026-08-04

**Scope:** Activation and adoption infrastructure; Codex provider rollout stays
disabled until Phase 5

## Delivered contract

### Read-only discovery and adoption

- Atoll resolves Codex from `PATH` plus common user and Homebrew locations and
  honors `CODEX_HOME` when selecting `hooks.json`.
- Discovery classifies the Codex hook file as missing, unreadable, or readable
  with separate exact counts for Atoll-marked and legacy CodeIsland handlers.
- Existing `com.codeisland.app` preferences, `~/.codeisland/`, the standalone
  app process, and `/tmp/codeisland-<uid>.sock` are inspected without changing
  or controlling them.
- Only content-free preferences with a direct merged-product equivalent are
  decoded: session grouping, smart suppression, completion presentation,
  mascot speed, sound enablement/volume, and a Codex default mascot. Approval,
  auto-allow, webhook, remote, display, update, and application-lifecycle
  preferences are excluded.
- Each refresh creates an immutable Codex plan listing the exact hook, helper,
  ownership-receipt, and socket paths a later activation would change.

### Consent and lifecycle ordering

- Consent is represented by a provider- and plan-bound token. A missing token,
  a token from an older discovery refresh, or a plan with unresolved blockers
  reaches no system adapter.
- The coordinator performs a live adoption preflight and requires the listener
  to report ready before invoking the installer.
- Installation is followed by exact verification. A failure returns the
  listener to pass-through, rolls back a returned receipt when possible,
  drains for a bounded interval, and stops.
- Deactivation enters pass-through first, removes the receipt-owned install,
  drains bounded in-flight work, and stops the listener. If removal fails, the
  listener remains alive in pass-through rather than leaving hooks pointed at
  a dead service.

### Exact managed installation and removal

- The new Codex installer is separate from the quarantined upstream
  `ConfigInstaller`. It operates only on a single consented Codex plan and a
  declared Atoll managed root.
- The bundled helper must exist and be executable before any write. The copied
  helper is mode `0700`; its SHA-256 digest, exact command, event list, and
  paths are stored in a content-free ownership receipt.
- Codex groups use the documented `hooks.json` event -> matcher group ->
  command handler shape. The installer preserves unrelated top-level data,
  matcher groups, handlers, and legacy CodeIsland commands.
- Repeated installation of the same receipt is idempotent. Partial exact
  Atoll handlers are repaired without discarding unrelated handlers in the
  same group.
- Removal targets only handlers whose type and full command match the receipt.
  The helper is removed only when its digest is unchanged. A symlinked managed
  root and modified or conflicting ownership artifacts fail closed.
- No `config.toml` change is planned: current Codex documentation says hooks
  are enabled by default and uses `[features].hooks = false` only to disable
  them.

### Socket conflict migration

- The system probe uses `lstat` plus a bounded local Unix connection attempt to
  distinguish absent, stale, occupied, unexpected, and inaccessible paths.
- Atoll never unlinks an occupied, foreign, inaccessible, or non-socket path.
- A stale socket is reclaimable only when that exact change was disclosed,
  the standalone app is no longer running, the path is still a socket owned by
  the current user, two identity checks agree, and a second probe is still
  stale immediately before unlink.
- Atoll never terminates or deletes `CodeIsland.app`.

### Atoll host and settings

- App startup performs only read-only discovery. The runtime still reports
  `isRunning == false`, the helper is not copied into the app, and no listener,
  installer, repair timer, or metadata store is constructed.
- The Code Island settings page shows Codex presence, hook ownership, existing
  CodeIsland state, compatible preferences, recovery guidance, and every
  proposed changed path. Refresh is the only action.
- Questions and approvals remain in Codex. There is no activation toggle,
  consent button, approval/deny/answer control, or Code Island process-control
  action.

## Codex documentation checks

The implementation was checked against the current official
[Codex Hooks documentation](https://developers.openai.com/codex/hooks) on
2026-08-04:

- User hooks may live in `~/.codex/hooks.json`; multiple matching hooks run,
  and non-managed command hooks require review in `/hooks`.
- A `PermissionRequest` hook that returns no decision leaves the normal Codex
  approval flow in control.
- The documented JSON hierarchy matches the exact groups emitted by the
  installer.

“Atoll-managed” in this design means owned and removable by Atoll. It does not
claim Codex enterprise-managed status and does not bypass Codex trust review.

## Safety boundary

All mutation tests use temporary directories and executable fixtures. They do
not point the installer, coordinator, or reclaimer at the developer's real
home directory, Codex configuration, CodeIsland files, preferences, or socket.
Live local inspection during design remained read-only.

The Phase 4 machinery has no production listener adapter and is unreachable
from the settings UI. `ProviderCapabilityRegistry.phaseTwo` still labels Codex
as Monitoring with activation unavailable, and `CodeIslandRuntime.isRunning`
remains false.

## Verification evidence

Phase 4 was developed through red-to-green executable contract slices:

1. Read-only discovery, legacy footprint classification, preference whitelist,
   plan disclosure, and byte-for-byte no-mutation evidence.
2. Consent/stale-plan gates, live preflight, listener-before-installer order,
   failure pass-through, and deactivation order.
3. Exact Codex installation, idempotency, digest/receipt verification,
   unrelated-hook preservation, reversible removal, and preflight rollback.
4. Socket classification, conflict blocking, disclosed stale reclamation, and
   refusal to unlink a regular file.

Local verification completed:

- All 23 repository Python/standalone-Swift regressions pass.
- The Phase 4 runner compiles the package modules once and executes all four
  Swift contract programs without XCTest.
- `CodeIslandCore`, `CodeIslandRuntime`, `CodeIslandUI`, and the helper compile
  in debug and release package builds for the selected macOS SDK.
- The Atoll host and settings sources type-check against the built package
  modules; all changed Swift sources pass parser validation.
- `project.pbxproj` passes `plutil -lint`; `git diff --check` passes.

The local machine has Command Line Tools rather than a matching full Xcode.
Local `swift test` reaches the test target and then reports `no such module
XCTest`; the complete application build and SwiftPM XCTest suite remain
delegated to the CI matrix. The managed sandbox also prohibits creating a Unix
socket (`EPERM`), so local socket regressions cover the read-only and injected
boundary states; Phase 5 must add and exercise the live-bind cases in CI.

## Verification commands

Run from the Atoll repository root:

```sh
python3 -m unittest discover -v -s tests -p 'test_*.py'
python3 -m unittest tests.test_code_island_phase_four_contracts
swift build --package-path Packages/CodeIsland --disable-sandbox
swift build -c release --package-path Packages/CodeIsland --disable-sandbox
swift test --package-path Packages/CodeIsland
plutil -lint DynamicIsland.xcodeproj/project.pbxproj
git diff --check
```

When the selected Command Line Tools SDK requires it, use an explicit matching
target triple and writable module-cache paths, as recorded in the Phase 3
verification notes.

## Phase 5 authorization gate

Phase 5 is not authorized. Before Codex activation becomes available it must:

- embed, sign, and copy the real helper and add a production listener that
  transports only sanitized observations;
- update and verify event-specific completions. In the current official docs,
  `Stop` expects JSON on standard output while the inert Phase 2 helper emits
  none;
- exercise Codex `/hooks` trust review and confirm failure/timeout behavior;
- choose and test the legacy-hook adoption route without double delivery,
  because all matching Codex hooks run concurrently;
- verify live absent, stale, occupied, shutdown, and rollback socket cases;
- only then replace the Phase 2 capability profile and expose consent plus
  activation UI.
