# CodeIsland Upstream Ledger

## Imported baseline

- Repository: <https://github.com/wxtsky/CodeIsland.git>
- Branch: `main`
- Tag: `v1.0.31`
- Commit: `9e3a1eb1844f0b8bf05193228a6ffa41a013dec2`
- Import date: 2026-08-04
- Import method: history-preserving `git subtree`
- Atoll prefix: `Packages/CodeIsland`
- Subtree merge commit: `177aa612daa4c891e3b862a694c02d96045b7a0c`
- License: MIT; preserved in [LICENSE](LICENSE)

The baseline was imported from the adjacent verified clone with:

```sh
git subtree add --prefix=Packages/CodeIsland ../CodeIsland main
```

## Atoll-only changes

Phases 1 and 2 intentionally change the imported source boundary before
anything is linked into Atoll:

- Replaces the standalone `CodeIsland` application product with internal
  `CodeIslandCore`, `CodeIslandRuntime`, and `CodeIslandUI` libraries.
- Replaces the blocking upstream bridge with a Codex-only, deadline-bounded
  helper whose sole completion is status 0 with empty output. It has no socket
  transport or listener in Phase 2 and is not installed or invoked by Atoll.
- Introduces new metadata-only Core projection, archive, file store, capability
  registry, and Codex lifecycle adapter rather than activating rich upstream
  equivalents. The adapter recognizes only documented Codex lifecycle events,
  treats compact SessionStart as continuity, and does not inspect arbitrary
  tool output to manufacture a failure signal.
- Leaves Atoll's Xcode target unlinked through Phase 2, so the imported source
  cannot start a listener, install hooks, or mutate provider configuration.

### Migration staging

| Upstream area | Current disposition | Earliest remaining migration phase |
|---|---|---|
| Rich Core models, normalizers, transcript readers, provider scanners, and retained upstream tests | `Sources/CodeIslandCore/Upstream`; excluded from SwiftPM. New sanitized Phase 2 contracts are active beside the quarantine. | Provider-neutral pieces only when their metadata boundary is proven |
| `HookServer`, `ConfigInstaller`, provider resources, and origin helpers | `Sources/CodeIslandRuntime/Upstream`; excluded from SwiftPM. A new Codex-only adapter and metadata store are active beside the quarantine. | Phases 4 and 5 as activation and provider contracts are proven |
| Mascots, sounds, icons, and reusable visual candidates | `Sources/CodeIslandUI/Upstream`; excluded from SwiftPM | Phase 6, after Atoll-host adaptation |

Core migration staging is deliberate: the imported `SessionSnapshot`, hook
models, `JSONLTailer`, and provider scanners expose rich or provider-specific
data and therefore do not satisfy Atoll's public Core contract unchanged.

### Deliberately removed areas

- Application ownership: `CodeIslandApp`, `AppDelegate`, panel/settings/status
  controllers, `UpdateChecker`, Sparkle, app entitlements, app icons, appcast,
  build/release scripts, and standalone documentation.
- Monolithic application state and responder UI: `AppState` and its extensions,
  application `Models`, `NotchPanelView`, settings views, global hotkeys,
  display/window helpers, and debug harnesses. These are replaced by focused
  Atoll host adapters and sanitized package APIs rather than migrated wholesale.
- Rich persistence and diagnostics: `SessionPersistence`,
  `DiagnosticsExporter`, and transcript-backed application state. Phase 2
  introduced a new typed metadata archive and file store; none of the rich
  upstream persistence is compiled.
- Active Codex response ownership: `CodexAppServerClient`,
  `AppState+CodexAppServer`, and the original blocking bridge implementation.
  The replacement lifecycle-hook bridge cannot produce provider control output.
  The app-server question path remains excluded, so Codex is still labeled
  Monitoring.
- Deferred services and platforms: remote hosts, SSH, Buddy, Bluetooth, ESP32,
  Android, iPhone, and Apple Watch sources and resources.
- Obsolete application tests: `CodeIslandTests` depended on the removed
  executable and app monolith. Relevant behaviors must return as focused tests
  when their replacement Runtime, UI, or Atoll host seam is implemented.
  Upstream Core tests are retained beside their quarantined sources; removed
  responder, companion, ESP32, and performance tests remain recoverable from
  the subtree parent and must be reconsidered with the matching migration.

Every removed file remains available through the subtree parent commit above.
An upstream refresh must follow this mapping and must not reintroduce a second
application lifecycle, responder UI, remote/Buddy code, or rich persistence.

## Refresh procedure

1. Review upstream changes from the last recorded commit.
2. Pull history without squashing:

   ```sh
   git subtree pull --prefix=Packages/CodeIsland \
     https://github.com/wxtsky/CodeIsland.git main
   ```

3. Resolve the expected conflicts at `Package.swift`, migration-staging paths,
   and deliberately removed areas; never accept those areas wholesale.
4. Update the imported commit, date, Atoll-only patch list, and verification
   evidence in this ledger.

## Verification

Run from the Atoll repository root:

```sh
python3 -m unittest tests.test_code_island_package_boundary
python3 -m unittest tests.test_code_island_phase_two_contracts
python3 -m unittest tests.test_privacy_configuration
python3 -m unittest tests.test_timer_lifecycle
swift test --package-path Packages/CodeIsland
```

Swift validation requires a selected Xcode or Command Line Tools installation
whose compiler and macOS SDK versions match.
