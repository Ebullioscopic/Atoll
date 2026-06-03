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

So each test here exercises a **pure-logic kernel** that mirrors — line-for-line,
with a `// MIRRORS:` reference back to the canonical source — the small,
hardware-free *decision* embedded in the app code. The package builds and runs
with a plain `swift test`: no Xcode app build, no signing, no hardware.

## Coverage map (Codacy's 5 proposals)

| # | Codacy proposal | Kernel | Status |
|---|-----------------|--------|--------|
| 1 | Auto-brightness updates baseline without showing the HUD | `BrightnessEmissionKernel.syncWithSystemBrightness` | ✅ covered |
| 2 | Brightness emissions throttled to ≥ 0.04s apart | `BrightnessEmissionKernel.emitBrightnessChange` | ✅ covered |
| 3 | Desktop click outside the notch closes the sticky terminal | `StickyTerminalClickKernel` | ✅ covered |
| 4 | CoreBrightness client resolves the right class per macOS version | `CoreBrightnessClassResolver` | ✅ covered |
| 5 | Custom terminal scroll knob reflects the SwiftTerm view | — | ⏭️ skipped — **no custom scroll knob exists**; SwiftTerm owns scrolling. Documented, not faked. |

16 tests (15 active + 1 documented `XCTSkip`), all green.

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
app and tests share one definition. Tracked in the PR description.
