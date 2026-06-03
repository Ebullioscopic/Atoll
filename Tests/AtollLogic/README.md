# AtollLogic — decision-logic tests

Standalone Swift Package providing automated test coverage for the scenarios
Codacy flagged as missing in its review of [PR #3](https://github.com/arbitraged-life/atoll/pull/3)
("Prompt proposal for missing tests").

## Why a separate package

Atoll is a single `DynamicIsland` application target with **no test target**, and
the flagged behaviours live inside hardware-coupled singletons
(`SystemBrightnessController`, `CoreBrightnessDisplayClient`) and an
`NSEvent`-global-monitor in `ContentView`. None of those run deterministically in
CI (they touch CoreBrightness, IODisplay, ambient-light sensors, real mouse
events).

So each test here exercises a **pure-logic kernel** that mirrors — with a
`// MIRRORS:` reference back to the canonical source — the small, hardware-free
*decision* embedded in the app code. Every kernel is a verified copy of the
**actual** app logic: where a Codacy proposal described behaviour the app does
not implement, the kernel mirrors what the app really does and the proposal is
documented as not-applicable rather than faked. The package builds and runs with
a plain `swift test`: no Xcode app build, no signing, no hardware.

## Coverage map (Codacy's 5 proposals, reconciled against the real app)

| # | Codacy proposal | Reality in the app | Kernel | Status |
|---|-----------------|--------------------|--------|--------|
| 1 | Auto-brightness updates baseline *without* showing the HUD | App's `syncWithSystemBrightnessIfNeeded()` **re-emits** (posts `.systemBrightnessDidChange`) on a > 0.001 delta — it does **not** sync silently | `BrightnessEmissionKernel.syncWithSystemBrightnessIfNeeded` | ✅ covered (real contract) |
| 2 | Brightness emissions throttled to ≥ 0.04s apart | App has **no emission throttle**; the real rate gate is the poll loop's `0.005` change threshold | `BrightnessEmissionKernel.pollShouldEmit` | ✅ covered (real contract) |
| 3 | Desktop click outside the notch closes the sticky terminal | Matches `ContentView` sticky-terminal monitor exactly | `StickyTerminalClickKernel` | ✅ covered |
| 4 | CoreBrightness client resolves the right class per macOS version | App loads a **single** `DisplayBrightnessClient` class directly — no candidate-class resolver exists | — | ⏭️ skipped — **not applicable**; documented, not faked |
| 5 | Custom terminal scroll knob reflects the SwiftTerm view | Atoll has **no custom scroll knob**; SwiftTerm owns scrolling | — | ⏭️ skipped — **not applicable**; documented, not faked |

The brightness kernel additionally covers the surrounding value-math the app
relies on: `emitBrightnessChange` clamping, `adjust(by:)` target computation,
`animationDuration(forDelta:)` scaling/clamping, and the `ease(_:)` cubic
ease-out — each a verified mirror of `SystemBrightnessController`.

## Run

```bash
cd Tests/AtollLogic
swift test
```

CI: `.github/workflows/logic-tests.yml` runs the suite on any PR touching
`Tests/AtollLogic/**`.

## Follow-up

These kernels are verified *copies* of the app logic. The natural next step is to
extract each kernel into a shared source file the app target itself imports, so
app and tests share one definition instead of a maintained copy.
