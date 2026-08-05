# Code Island Phase 2 Verification

**Status:** Complete

**Date:** 2026-08-04

**Scope:** Codex safety-first runtime only; no Atoll host linkage or provider
activation

## Verified contract

The local verification target was Codex CLI `0.146.0`. The current official
[Codex hooks documentation](https://developers.openai.com/codex/hooks) defines
the two behaviors Phase 2 relies on:

- A command hook that exits successfully with no output lets Codex continue.
- A `PermissionRequest` hook that does not return a provider decision leaves
  the normal Codex approval flow in control.
- A compacted session emits `SessionStart` with `source: "compact"`; that is
  continuity of the same session, not a new start.

The replacement helper therefore has one possible provider completion: status
0 and empty standard output. Its public completion type has no public
initializer, so an Atoll host adapter cannot construct a different output.
Observation delivery success, cancellation, timeout, missing Atoll, and Atoll
shutdown all resolve to that same completion.

Codex remains labeled **Monitoring**, not Native attention. Approval lifecycle
events can be reduced to a sanitized waiting state, but interactive questions
currently arrive through the app-server `requestUserInput` request. That path
requires an active response and remains entirely excluded from the compiled
package. The documented `PostToolUse.tool_response` field is tool-specific JSON,
not a stable success contract, so Phase 2 also does not infer failures by
examining rich provider output. Codex advertises both limitations explicitly.

## Active Phase 2 surface

| Module | Active responsibility |
|---|---|
| `CodeIslandCore` | Opaque session identity, project identity, origin handles, derived state, timestamps, and the pure metadata projector |
| `CodeIslandRuntime` | Metadata archive/file store, explicit provider capability registry, Codex lifecycle normalization, and non-owning completion policy |
| `codeisland-bridge` | Codex-only bounded input adapter with no listener, transport, logs, configuration writes, or provider output |
| `CodeIslandUI` | Boundary marker only; no Phase 2 UI |

The runtime remains disabled by default and reports no running service. The
Atoll Xcode project has no Code Island package reference. No socket listener,
hook installer, discovery service, repair timer, or coding-tool configuration
mutation is active.

## Privacy proof

The persistable type exposes only:

- Provider and validated opaque session identifier.
- Project display identity and optional working directory.
- Application, terminal-session, workspace, pane, and TTY navigation handles.
- Derived state and timestamps.

Codex payloads are parsed transiently inside the adapter. Content-bearing
fields are never copied into `SessionObservation`, `SessionMetadata`, the JSON
archive, or the file store. The archive test asserts an exact JSON key allowlist
and round-trips only the typed metadata projection.

## Behavioral fixture matrix

Each fixture runs through the sanitized adapter and completion-policy seam. The
standalone regression checks all delivery outcomes, while the Python contract
test invokes the real helper process. A test-only native-origin simulator then
proves that a successful empty helper completion preserves the fixture's origin
outcome; no allow, deny, answer, or cancellation type exists in production code.

| Fixture | Required proof |
|---|---|
| Origin allows | Native `allow` remains the result after status 0 with empty output |
| Origin denies | Native `deny` remains distinct after the identical helper completion |
| Origin question | App-server request is not accepted as a hook observation |
| Origin cancellation | Native cancellation remains the result; Atoll never emits it |
| Observer timeout | Held-open stdin triggers the helper's one-second hard deadline and still produces status 0 with empty output |
| Atoll missing | Helper exits successfully with no output |
| Atoll shutdown | The shutdown delivery outcome resolves to the same sealed completion |

## Verification commands

Run from the Atoll repository root:

```sh
python3 -m unittest tests.test_code_island_package_boundary
python3 -m unittest tests.test_code_island_phase_two_contracts
python3 -m unittest tests.test_privacy_configuration
python3 -m unittest tests.test_timer_lifecycle
swift build --package-path Packages/CodeIsland --disable-sandbox
swift build -c release --package-path Packages/CodeIsland --disable-sandbox
swift test --package-path Packages/CodeIsland
```

The standalone Phase 2 regression compiles and executes Core, Runtime, and the
helper without XCTest. `swift test` remains the full-Xcode/CI test route; a
Command Line Tools selection without the XCTest module cannot execute it.
