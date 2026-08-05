# Code Island Phase 5 Verification

**Status:** Complete

**Date:** 2026-08-04

**Scope:** Verified Codex Monitoring rollout; Phase 6 presentation remains
unauthorized

## Delivered contract

### Non-owning Codex bridge

- The bundled helper reads at most 1 MiB of provider input under a one-second
  monotonic deadline, including when the provider keeps stdin open.
- Raw hook JSON is reduced inside the helper to `SessionObservation`. Only the
  fixed, versioned metadata envelope can cross Atoll's Unix socket.
- The decoder rejects unknown top-level and nested keys, oversized envelopes,
  unsupported schema versions, invalid identifiers, unsafe metadata fields,
  empty origin handles, non-finite timestamps, and providers other than Codex.
- Delivery is bounded and irrelevant to native control. `PermissionRequest`
  exits successfully with no decision output, so Codex keeps its normal
  approval prompt. `Stop` receives the required no-op JSON `{}`. Missing Atoll,
  timeout, cancellation, and shutdown never create an allow, deny, answer, or
  continuation decision.

### Listener and runtime lifecycle

- Atoll binds a user-only (`0600`) Unix socket and never unlinks a pre-existing
  path. Startup reports ready only after bind, permission tightening, listen,
  and socket identity capture succeed.
- Stop unlinks the path only when its device, inode, and owner still match the
  socket Atoll created. Pass-through mode acknowledges shutdown without
  projecting a session, and in-flight connections drain for a bounded period.
- With no ownership receipt, app startup performs discovery and a receipt read
  only. A verified receipt starts the listener before verification and permits
  repair only for that already-consented integration.
- The runtime projects and persists only `SessionMetadata`, in deterministic
  provider/session order. Shutdown stops the endpoint without uninstalling the
  user's activated hooks.

### Explicit activation and reversible adoption

- Atoll Settings exposes `Activate Codex Monitoring`, not a default-on toggle.
  The confirmation sheet repeats the Monitoring label, current limitations,
  every planned mutation, legacy-hook behavior, and the Codex `/hooks` trust
  reminder before creating the plan-bound consent token.
- The installed command includes the exact disclosed listener path and a unique
  Atoll plan marker. Verification requires one exact handler for each selected
  event and zero recognized legacy CodeIsland handlers for those events.
- Recognized legacy commands are removed only under explicit consent and stored
  as a semantic receipt backup. Deactivation removes the exact Atoll handlers,
  restores that backup, and preserves unrelated or concurrently added hooks.
  If `hooks.json` disappeared, deactivation reconstructs the backed-up legacy
  handlers before retiring the receipt.
- Repair requires the persisted receipt to match, preserves its adoption
  backup, restores exact missing handlers, and refreshes only an Atoll-owned
  helper. An externally modified helper fails closed and is not overwritten.
- The Atoll integration directory and installed helper are mode `0700`; the
  ownership receipt containing the legacy-hook backup is mode `0600`.

### Bundle and capability gate

- `codeisland-bridge` is an executable package product copied to
  `Atoll.app/Contents/Helpers` by a dedicated all-actions Copy Files phase with
  `CodeSignOnCopy`; it is not linked as a framework.
- CI requires the live Unix-socket regression, a built executable helper, and
  strict helper signature verification. Release export performs the same
  executable and signature checks before final app signing and notarization.
- `ProviderCapabilityRegistry.phaseFive` enables Codex at Monitoring only.
  Interactive question observation and tool-failure inference remain explicit
  limitations, so Native attention is not claimed.
- The Atoll settings and host contain no approve, deny, always-allow, option,
  free-text answer, or app-server responder control.

## Codex documentation checks

The implementation was checked against the current official
[Codex Hooks documentation](https://developers.openai.com/codex/hooks) on
2026-08-04. The relevant release behavior is:

- user hooks may live in `~/.codex/hooks.json`, all matching hooks run, and
  non-managed commands require explicit review/trust through `/hooks`;
- when no `PermissionRequest` hook decides, Codex uses its normal approval
  flow; and
- `Stop` expects JSON on standard output when a command exits successfully.

“Atoll-managed” means owned and exactly removable by Atoll. These remain Codex
user hooks and do not claim enterprise-managed trust.

## Verification evidence

Local verification completed:

- All 26 repository Python-driven regressions passed. They compile and execute
  the Phase 2 through Phase 5 standalone Swift contract programs, the actual
  helper process, and the existing package-boundary, privacy, and timer checks.
- Phase 5 executable tests cover the strict wire, event-specific completions,
  held-open stdin, live listener behavior where the sandbox permits it,
  pass-through shutdown, occupied/foreign socket preservation, reversible
  legacy adoption, missing-config restoration, receipt-owned repair, runtime
  restart ordering, and metadata-only persistence.
- The package builds in Debug and Release for the selected macOS SDK and the
  Atoll host/settings sources type-check against the built modules.
- All changed Swift sources pass parser validation. `project.pbxproj` passes
  `plutil -lint`, and `git diff --check` passes.

This machine has Command Line Tools rather than full Xcode. The complete Atoll
application build, SwiftPM XCTest target, real helper embedding/signing, and
mandatory live-socket run remain CI gates. The local Phase 5 listener test skips
only a sandbox `EPERM`; CI sets `CODEISLAND_REQUIRE_LIVE_SOCKET=1`, so that case
cannot be skipped there.

## Verification commands

Run from the Atoll repository root:

```sh
python3 -m unittest discover -v -s tests -p 'test_*.py'
python3 -m unittest tests.test_code_island_phase_five_contracts
swift build --package-path Packages/CodeIsland --disable-sandbox
swift build -c release --package-path Packages/CodeIsland --disable-sandbox
swift test --package-path Packages/CodeIsland
plutil -lint DynamicIsland.xcodeproj/project.pbxproj
git diff --check
```

When the selected SDK requires it, use explicit writable module caches, a
scratch path, and the matching macOS target triple as recorded in this phase's
local build invocation.

## Phase 6 historical gate

Phase 6 was subsequently authorized and completed. See
[Code Island Phase 6 Verification](code-island-phase-6-verification.md).
