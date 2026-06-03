# Review Bots — Baseline & Triage

Atoll PRs are reviewed by automated bots. This doc records the **fix classes** so
findings are resolved at the source and don't recur.

## Bots

| Bot | Class | Governs |
|-----|-------|---------|
| **corgea[bot]** | Crash-safety, concurrency, logic correctness | Force-unwraps, main-thread blocking, data races, observer leaks, stale state |
| **hound[bot]** | Style | Line length, formatting → governed by `.swiftlint.yml` |

## Trust calibration

Many automated PR reviewers are installed. They are noisy and overlap. How much
to trust each:

| Bot | Trust | Notes |
|-----|-------|-------|
| **corgea** | HIGH | Finds real defects (concurrency, force-unwrap, data races, logic bugs). Read every comment. |
| **cubic** | HIGH (security) | Strong on injection / shell-eval. Numbered, locationed findings. |
| **amazon-q-developer** | MEDIUM-HIGH | Good on security (flagged the workflow injection). |
| **codacy-production** | MEDIUM | SwiftLint-class style + some logic. Mostly absorbed by `.swiftlint.yml`. |
| **sourcery-ai** | MEDIUM | Decent on localization/format-string smells; some over-engineering advice. |
| **gemini-code-assist** | MEDIUM | Being sunset (review ceases 2026-07-17). |
| **hound** | LOW | Mechanical SwiftLint only — superseded by local `.swiftlint.yml` + `.hound.yml`. |
| **coderabbit / codeant / qodo / semanticdiff / ecc-tools / codacy AI** | LOW / INFO | Summaries, share-bait, or paused. Skim, don't action individually. |

## Fix classes (resolved in PR #4)

1. **Force-unwrap → guard/else** — `URL(string:)!`, `calendar.date(...)!`, `workItem!`.
   Replace with `guard let … else { return/continue/break }`.
2. **Main-thread blocking** — `Process.run()`/`waitUntilExit()`/`Data(contentsOf:)`
   on the main actor. Wrap in `Task.detached { }` or `DispatchQueue.global().async`,
   hop back via `await MainActor.run { }` to publish.
3. **Data races on shared state** — serialize via a dedicated queue, or snapshot
   `@Published` values on the main thread before passing into off-main work.
4. **Observer/KVO leaks** — remove-before-add guard; track registration with a Bool
   flag; retain registered windows in a `Coordinator`.
5. **Stale "last checked" timestamps** — derive the cursor from the max row
   timestamp actually scanned, not `Date()`.
6. **Fail-closed permissions** — unknown/unsupported branch returns `false`, never `true`.
7. **Bounds checks** — guard index against the real container size (note: `simd_floatN`
   is fixed-width N, has no `.count`).

## Bake-in workflow

When a valid finding recurs across PRs, encode it once so bots stop raising it:

1. **Style / mechanical** → add/tune a rule in `.swiftlint.yml`.
2. **Correctness pattern** (concurrency, force-unwrap, localization keys, CI
   injection) → add a MUST/SHOULD rule to `AGENTS.md` and fix all current sites.
3. **One-off bug** → just fix it in code.

Then resolve the bot threads rather than replying per-comment.

### Already baked in (PR #8)

- **CI shell injection** (P1, cubic/amazon-q): `mirror-release.yml` now routes all
  `github.event.release.*` through `env:` vars. Rule in `AGENTS.md` → CI section.
- **Dynamic localization keys** (P1, cubic/sourcery): fixed in
  `ReminderLiveActivityManager`, `ContentView`. Rule in `AGENTS.md` → Localization.
- **Redundant `String(format: String(localized:))`** (P2): fixed in
  `LockScreenWeatherWidget`. Rule in `AGENTS.md` → Localization.
- **Inconsistent un-localized strings** (`Completed`/`Ready`/`Start Custom Timer`/
  `\(minutes)m`): fixed. Rule in `AGENTS.md` → Localization.
- **TerminalManager inset guard off-by** (cubic P2): guard now `>= 2*inset + 10`.
  Rule in `AGENTS.md` → Logic correctness (geometry/insets).
- **SystemMediaControllers timer run-loop mode** (cubic P2): now `.common`. Rule in
  `AGENTS.md` → Concurrency.
- **CoreBrightness selector validation** (cubic P2): now `responds(to:)`-checks the
  resolved class. Rule in `AGENTS.md` → Safety.
- **Force-unwrap / data-race / main-thread-blocking classes** (corgea): captured as
  MUST rules in `AGENTS.md` and enforced by `force_unwrapping` in `.swiftlint.yml`.

### Not actioned (intentionally)

- "Add unit tests for X" suggestions (codacy): no test target wired for these UI/
  manager paths; out of scope for an upstream-sync PR.
- "Extract method / SRP" refactors (codacy MEDIUM on TerminalManager): cosmetic,
  upstream code; deferred to avoid diverging further from upstream.
- Share-bait / paused-review / summary comments: ignored.

## Noise control (decided in PR #11)

Adding `.swiftlint.yml` made **hound[bot]** lint the entire codebase and post
99+ inline comments per PR on pre-existing violations in untouched files. Its
style class is fully redundant with the `.swiftlint.yml` + CI gate.

- **`.hound.yml`** (repo root) disables hound's PR commenting. Style is enforced
  by `swiftlint --fix && swiftlint` locally and in CI — not inline PR spam.
- **Durable fix (admin/GUI required):** uninstall the hound GitHub App and trim
  the bot roster to 1–2. Tracked in `docs/BACKLOG.md`.
- Several bots (sourcery, gemini, codacy, corgea) don't understand SIMD
  fixed-width types and post false out-of-bounds warnings on `simd_floatN` —
  these are **dismissable**, not actionable (`simd_floatN` has no `.count`).

## Workflow

```bash
swiftlint --fix && swiftlint        # auto-fix + verify style (hound class)
xcodebuild -scheme DynamicIsland -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

The codesign Run Script phase may fail locally with "no identity found" — that is a
signing-environment issue, **not** a code defect. Successful Swift compilation
(zero `error:` lines) is the verification gate.
