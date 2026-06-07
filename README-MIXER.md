# Atoll + FineTune Mixer Fork

This fork of [Atoll](https://github.com/Ebullioscopic/Atoll) adds a **Mixer tab** to the notch: per-app volume and mute, gain boost (2x/3x/4x), per-app output device routing, and a 10-band equalizer with presets. The audio engine is ported from [FineTune](https://github.com/ronitsingh10/FineTune) (GPL-3.0, Ronit Singh). Both projects are GPL-3.0, so this combination is license-compatible; the fork remains GPL-3.0. See `NOTICE`.

## Build requirements

- **Xcode 16.3 or newer.** The ported engine uses `isolated deinit` and `nonisolated` type declarations (Swift 6.1 toolchain features).
- **macOS 15.0+ deployment target.** This fork bumps Atoll's main target from 14.6 to 15.0 — the Core Audio process-tap APIs the mixer depends on (`AudioHardwareCreateProcessTap`, `CATapDescription`) need 14.4+, and FineTune's engine code targets 15.0.

Build: `open DynamicIsland.xcodeproj`, select the DynamicIsland scheme, Run. The project uses Xcode 16 synced folders, so the new sources under `DynamicIsland/Mixer/` are picked up automatically — no project-file changes needed for added Swift files.

## Using the mixer

1. Settings → Mixer → "Enable volume mixer".
2. Grant the **System Audio Recording** permission when prompted (this is what lets the app tap per-app audio). Atoll's existing `NSAudioCaptureUsageDescription` covers it.
3. Open the notch → Mixer tab. Apps appear while they play audio. Each row: volume slider, percentage, mute, boost menu (1–4x), output-device menu (System Default or a specific device), and an EQ popover (10 bands, presets in 5 categories, double-click a band to zero it).

Disabling the toggle tears down all process taps and aggregate devices — the app stops touching other apps' audio entirely.

## What was added/changed

**New code**
- `DynamicIsland/Mixer/` — FineTune's engine: `Audio/` (Engine, Monitors, EQ, AutoEQ, Loudness, DDC, Extensions, Types, Permission), `Models/`, `Settings/`, `Utilities/` (63 files), plus `MixerCoordinator.swift` (lazy lifecycle owner).
- `DynamicIsland/components/Notch/NotchMixerView.swift` — the tab UI.
- `DynamicIsland/components/Settings/MixerSettings.swift` — settings pane.

**Modified Atoll files**
- `enums/generic.swift` — `NotchViews.mixer` case.
- `DynamicIslandViewCoordinator.swift` — tab order.
- `components/Tabs/TabSelectionView.swift` — tab registration (icon `slider.horizontal.3`).
- `ContentView.swift` — view switch case, mixer popover auto-close handling.
- `models/DynamicIslandViewModel.swift` — `isMixerPopoverActive`.
- `models/Constants.swift` — `enableMixerFeature` key (default off).
- `sizing/matters.swift` — tab-count minimum width.
- `components/Settings/SettingsView.swift` — Mixer settings tab (Utilities group).
- `DynamicIslandApp.swift` — engine bootstrap at launch, teardown at quit.
- `Info.plist` — audio-capture string updated; `NSBluetoothAlwaysUsageDescription` added.
- `project.pbxproj` — deployment target 14.6 → 15.0.
- `NOTICE` — FineTune attribution.

**Modified FineTune files (within `Mixer/`)**
- Aggregate devices renamed `FineTune-*` → `AtollMixer-*` (`ProcessTapController`, `OrphanedTapCleanup`, `AudioDeviceMonitor`). Without this, running real FineTune alongside this fork would destroy each other's taps at startup.
- Settings persist to `~/Library/Application Support/AtollMixer/settings.json` (was `FineTune/`), AutoEQ profiles likewise — no clobbering of a real FineTune install.
- `AudioRecordingPermission` TCC SPI made unconditional (was behind FineTune's `ENABLE_TCC_SPI` build flag).
- Removed dead `URLHandlerEngine` conformance (URL-scheme subsystem not ported).
- Excluded subsystems: menu bar UI, global hotkeys, media keys/HUD, Sparkle updater, URL schemes. AutoEQ, loudness compensation, and DDC ship with the engine (they're load-bearing in the DSP chain) but have no UI in the notch — engine APIs exist if you want to surface them.

## Known risks (read before filing build errors)

1. **Actor isolation diagnostics.** FineTune builds with Swift 6 language mode and *default MainActor isolation*; Atoll builds Swift 5 mode, default nonisolated. Core engine classes are explicitly `@MainActor` so most code is unaffected, but if the compiler flags an isolation error in a `Mixer/` file, the fix is adding `@MainActor` to the flagged declaration.
2. **Private API.** Permission preflight uses the TCC private framework (`TCCAccessPreflight`/`TCCAccessRequest`) — same as FineTune. Fine for direct distribution; not App Store eligible.
3. **First tap creation** prompts for System Audio Recording. If the engine shows "permission denied", grant it under System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch.
4. Atoll's waveform visualizer (`AudioTap`) and the mixer both create process taps; they're independent and don't conflict, but both will appear in the system's audio-tap accounting.
