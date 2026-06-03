# Atoll — Backlog

Real, non-blocking findings surfaced during automated PR review. None of these
block a merge (they are pre-existing tech debt, not regressions introduced by
the PR that surfaced them). Triaged from PR #11's bot flood.

## Review-bot hygiene

- [ ] **Uninstall the `hound[bot]` GitHub App** (repo Settings → GitHub Apps).
      Requires repo admin → must be done via GUI by `arbitraged-life`.
      Rationale: hound's style class is 100% redundant with `.swiftlint.yml` +
      CI. After adding `.swiftlint.yml` it sprayed 99+ inline comments per PR on
      untouched files. `.hound.yml` now silences its commenting, but removing
      the app entirely is the clean fix.
- [ ] **Trim the review-bot roster.** 7 bots currently race on every PR
      (hound, corgea, sourcery-ai, gemini-code-assist, codacy-production,
      codeant-ai, codefactor-io). Recommend keeping 1–2 (e.g. gemini + codacy)
      and uninstalling the rest. Several don't understand SIMD fixed-width types
      and post false "out-of-bounds" warnings on `simd_float4`.
- [ ] **Stop `codefactor-io` auto-committing to PR branches.** It pushed an
      UNSIGNED commit (`0afa4d2`) directly to `fix/pr4-review-findings`, which
      will violate the signature-required ruleset on merge. Either disable its
      auto-fix-commit feature or uninstall it.

## Real code findings (pre-existing — fix opportunistically)

- [ ] **DockerHealthManager.swift:~76** — `Process`/`Pipe` are non-`Sendable`,
      created on the main actor then used inside `Task.detached` (concurrency
      race). Create them inside the detached task instead. (gemini HIGH)
- [ ] **AppleNotesSyncManager.swift:~72** — `NSAppleScript` executed inside
      `Task.detached`; AppleScript should run on the main thread. (codacy MED)
- [ ] **MusicManager.swift:~1228** — cache key for `title`/`artist` is captured
      BEFORE `updateFromPlaybackState` applies new track metadata, so the key
      can be built from the previous song. Capture after the update. (codeant)
- [ ] **NotificationFeedManager.swift:~158-162** — `ORDER BY ended_at DESC
      LIMIT 10` then advancing `lastHermesCheck` to the batch max skips unseen
      rows when >10 new sessions arrive between polls; also runs synchronous
      SQLite on the main actor. Page fully or cap the cursor at the oldest
      scanned row; move I/O off-main. (codeant / corgea)
- [ ] **LiquidGlassBackground.swift:~75** — `configureBackdropLayers()` can
      double-register KVO observers if `removeBackdropObservers()` didn't run.
      Add a remove-before-add guard / registration flag. (corgea)

## Dismissed (bot false-positives — do NOT "fix")

- `RealTimeAudioSpectrum.swift` "`index < 4` unsafe, bound by `magnitudes.count`"
  (sourcery / gemini / codacy / corgea): WRONG. `getSmoothedMagnitudes()`
  returns `simd_float4` — a fixed 4-lane SIMD vector that has no `.count`.
  Hardcoded `4` is correct; `.count` was the original compile error.
- `TimerManager.swift` "`isFinished = false` at zero is inverted" (sourcery /
  codacy): by design — `isFinished`/`isOvertime` are mutually exclusive;
  completion is observed via `isFinished || isOvertime`.
- `IdleAnimationManager.swift` "`global().sync` blocks caller" (gemini /
  codacy): already fixed in `f029e32` (the `.sync` hop was removed); bots
  reviewed the stale line.
- All `hound[bot]` `line_length` / `closure_parameter_position` violations on
  files not touched by the PR: pre-existing, redundant with swiftlint/CI.
