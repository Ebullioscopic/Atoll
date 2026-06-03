# Review Bots — Baseline & Triage

Atoll PRs are reviewed by automated bots. This doc records the **fix classes** so
findings are resolved at the source and don't recur.

## Bots

| Bot | Class | Governs |
|-----|-------|---------|
| **corgea[bot]** | Crash-safety, concurrency, logic correctness | Force-unwraps, main-thread blocking, data races, observer leaks, stale state |
| **hound[bot]** | Style | Line length, formatting → governed by `.swiftlint.yml` |

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

## Workflow

```bash
swiftlint --fix && swiftlint        # auto-fix + verify style (hound class)
xcodebuild -scheme DynamicIsland -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

The codesign Run Script phase may fail locally with "no identity found" — that is a
signing-environment issue, **not** a code defect. Successful Swift compilation
(zero `error:` lines) is the verification gate.
