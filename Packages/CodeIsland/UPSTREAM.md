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

Phase 1 intentionally changes the imported source boundary before anything is
linked into Atoll:

- Replaces the standalone `CodeIsland` application product with internal
  `CodeIslandCore`, `CodeIslandRuntime`, and `CodeIslandUI` libraries.
- Removes CodeIsland's application delegate, app/window controllers, status
  item, settings window, updater, and Sparkle dependency.
- Excludes remote hosts, SSH, Buddy companions, Bluetooth, ESP32, Android, and
  Apple companion code from the first merged release.
- Keeps the bridge executable inert until its provider-specific pass-through
  behavior is implemented and verified.
- Leaves Atoll's Xcode target unlinked during Phase 1, so importing the source
  cannot start a listener, install hooks, or mutate provider configuration.

Removed source remains available through the subtree parent commit above. It
must be migrated selectively; an upstream refresh must not reintroduce a second
application lifecycle, responder UI, remote/Buddy code, or rich persistence.

## Refresh procedure

1. Review upstream changes from the last recorded commit.
2. Pull history without squashing:

   ```sh
   git subtree pull --prefix=Packages/CodeIsland \
     https://github.com/wxtsky/CodeIsland.git main
   ```

3. Resolve the expected conflicts at `Package.swift` and deliberately excluded
   paths; never accept those areas wholesale.
4. Update the imported commit, date, Atoll-only patch list, and verification
   evidence in this ledger.

## Verification

Run from the Atoll repository root:

```sh
python3 -m unittest tests.test_code_island_package_boundary
python3 -m unittest tests.test_privacy_configuration
python3 -m unittest tests.test_timer_lifecycle
swift test --package-path Packages/CodeIsland
```

Swift validation requires a selected Xcode or Command Line Tools installation
whose compiler and macOS SDK versions match.
