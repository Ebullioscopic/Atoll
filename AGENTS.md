# Agent / Contributor Guide — Atoll (DynamicIsland)

This file encodes recurring code-review feedback as durable rules so the same
defects stop getting re-raised on every PR. Automated reviewers (corgea,
codacy, cubic, sourcery, gemini, hound/SwiftLint) run on every PR; the high-signal
classes of issue they catch are written here as MUST / SHOULD rules. Follow them
when writing or reviewing Swift in this repo.

Build verification: `xcodebuild -scheme DynamicIsland build` must succeed before any PR.
Lint: `swiftlint` (config in `.swiftlint.yml`) — fix warnings before pushing.

## Localization (MUST)

- **Never interpolate a runtime value into a localization key.** A key like
  `String(localized: "in \(minutes) min")` produces a *dynamic* key that can't
  be statically extracted into `Localizable.xcstrings` and will never match a
  translation. Use a fixed key with a format specifier:
  `String(format: String(localized: "in %lld min"), minutes)`.
- **Never wrap a no-placeholder localized string in `String(format:)`.**
  `String(format: String(localized: "All-day"))` treats the translation as a
  printf format string — a translator's stray `%` reads garbage memory or crashes.
  Use `String(localized: "All-day")` directly.
- **Localize consistently.** If sibling branches of a status/label switch are
  localized, all branches must be (no stray English "Completed" / "Ready" next to
  localized "Paused" / "Overtime"). Same for countdown units — don't localize the
  `>= 60` branch while leaving `"\(minutes)m"` hardcoded.
- Use `%lld` for `Int` interpolation in format strings (matches `Int` width on
  64-bit), not `%d`, and not a separately-localized fragment concatenated in.

## Concurrency & main thread (MUST)

- **No synchronous blocking on `@MainActor`.** Don't call `process.waitUntilExit()`,
  `Data(contentsOf:)` on a remote URL, or any blocking disk/network I/O on the main
  thread. Move to a background queue / `Task.detached` and hop back for UI.
- **Guard shared mutable state against data races.** State read/written from both a
  background callback (timers, notification blocks, `Process` handlers) and the main
  thread must be synchronized (actor, serial queue, or main-thread confinement).
- **Don't leak or overlap unstored `Task`s.** Store cancellable `Task` handles and
  cancel the prior one before starting a replacement; an un-stored `Task { }` whose
  work overlaps a later invocation races.
- **Schedule reset/UI timers on `.common` run-loop mode** when they must fire during
  user tracking (scrolling, menu tracking). `Timer.scheduledTimer(...)` uses
  `.default`, which is paused during tracking. Create the `Timer` and
  `RunLoop.main.add(timer, forMode: .common)`.

## Safety (MUST)

- **No force-unwrapping of fallible constructors.** `URL(string:)!`,
  `Calendar.date(byAdding:...)!`, dictionary subscripts, and array indexing must be
  guarded (`guard let`, bounds check) — a nil/out-of-range value crashes the app.
- **Validate resolved private/ObjC classes before use.** When resolving a private
  class via `NSClassFromString`, verify the instance `responds(to:)` the selectors
  you depend on before accepting it; a future OS may ship a same-named class with a
  different API (e.g. CoreBrightness client resolution).
- **Observers: balanced add/remove.** Don't double-add an observer; remove only the
  observer you added (don't `removeObserver(self)` unconditionally if you only
  registered a specific token).

## CI / workflows (MUST)

- **Never interpolate untrusted `${{ github.event.* }}` (release tag/name/body,
  PR title, issue body, etc.) directly into a `run:` shell.** GitHub evaluates
  `${{ }}` before bash parses, so `$(...)`/quote-breaking payloads execute. Pass the
  value through an `env:` var and reference it with native shell syntax
  (`"$RELEASE_TAG"`), and write multi-line bodies with `printf '%s' "$VAR" > file`.

## Logic correctness (SHOULD)

- A setter must use its new value (no parameter-ignoring setters).
- `==` / `Equatable` should compare semantic identity, not a per-instance UUID that
  defeats the comparison.
- Permission / capability `#else` branches should fail *closed*, not open.
- Geometry guards must account for insets: if you `insetBy(dx: n, dy: n)` after a
  size guard, the guard threshold must be `>= 2*n + minimum`, else frames collapse
  to zero/negative during resize.

## Logging (SHOULD)

- Gate verbose/emoji `NSLog` debugging behind a debug flag or lower verbosity,
  especially in polling paths that log repeatedly.
