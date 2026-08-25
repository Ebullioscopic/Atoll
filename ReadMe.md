<p align="center">
  <img src=".github/assets/atoll-logo.png" alt="Atoll logo" width="120">
</p>
<h1 align="center">Atoll - DynamicIsland for macOS</h1>
<p align="center">
<a href="https://trendshift.io/repositories/15291" target="_blank"><img src="https://trendshift.io/api/badge/repositories/15291" alt="Ebullioscopic%2FAtoll | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>
</p>
<p align="center">
  <a href="https://github.com/Ebullioscopic/Atoll/stargazers">
    <img src="https://img.shields.io/github/stars/Ebullioscopic/Atoll?style=social" alt="GitHub stars"/>
  </a>
  <a href="https://github.com/Ebullioscopic/Atoll/network/members">
    <img src="https://img.shields.io/github/forks/Ebullioscopic/Atoll?style=social" alt="GitHub forks"/>
  </a>
  <a href="https://github.com/Ebullioscopic/Atoll/releases">
    <img src="https://img.shields.io/github/downloads/Ebullioscopic/Atoll/total?label=Downloads" alt="GitHub downloads"/>
  </a>
  <a href="https://discord.gg/PaqFkRTDF8">
    <img src="https://dcbadge.limes.pink/api/server/https://discord.gg/PaqFkRTDF8?style=flat" alt="Discord server"/>
  </a>
</p>

<p align="center">
  <a href="https://github.com/sponsors/Ebullioscopic">
    <img src="https://img.shields.io/badge/Sponsor-Ebullioscopic-ff69b4?style=for-the-badge&logo=github" alt="Sponsor Ebullioscopic"/>
  </a>
  <a href="https://github.com/Ebullioscopic/Atoll/releases/latest">
    <img src="https://img.shields.io/badge/Download-Atoll%20for%20macOS-0A84FF?style=for-the-badge&logo=apple" alt="Download Atoll for macOS"/>
  </a>
  <a href="https://www.buymeacoffee.com/kryoscopic">
    <img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-kryoscopic-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=000000" alt="Buy Me a Coffee for kryoscopic"/>
  </a>
</p>

<p align="center">
  <a href="https://discord.gg/PaqFkRTDF8">Join our Discord community</a>
</p>

> **This is an independent open-source derivative of [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll), not the official Atoll repository.**
> The upstream project and its existing attributions remain the foundation of this codebase. See [UPSTREAM.md](UPSTREAM.md), [NOTICE](NOTICE), and [LICENSE](LICENSE) for the source and licensing details.

Atoll turns the MacBook notch into a focused command surface for media, system insight, and quick utilities. It stays out of the way until needed, then expands with responsive, native SwiftUI animations. This project keeps that Atoll experience and adds a built-in Codex utility for local coding-agent status.

## Built-in Codex Utility

This project adds Codex task status as a native Atoll utility. Codex is the local coding-agent workflow being surfaced by Atoll; this integration is not a replacement for Codex and does not turn Atoll into an AI service. It uses local Codex Hooks and an Atoll-bundled `CodexHookHelper`; there is no separate CodexAtoll app, menu-bar item, extension authorization flow, or second package to install.

- Configure it from **Atoll Settings → Utilities → Codex**.
- Show running, approval-waiting, and recently completed tasks in the notch.
- Open the matching Codex conversation from the expanded task view.
- Choose whether task previews and fullscreen Codex status are shown.
- Build and distribute the feature as part of the single Atoll app.

The integration is intentionally local-first: it consumes Codex Hook events, keeps the displayed state focused on task metadata and status, and does not parse transcripts, upload prompts or source code, or start a network service.

<p align="center">
  <img src="https://i.postimg.cc/t49mW5yN/Screenshot-2026-03-02-at-6-00-22-PM.png" alt="Atoll lock screen" width="920">
</p>





## Highlights
- Media controls for Apple Music, Spotify, Cider, and more with inline previews.
- Live Activities for media playback, Focus, screen recording, privacy indicators, downloads (beta), and battery/charging.
- Lock screen widgets for media, timers, charging, Bluetooth devices, and weather.
- Lightweight system insight for CPU, GPU, memory, network, and disk usage.
- Productivity tools including timers, clipboard history, color picker, and calendar previews.
- Customization for layouts, animations, hover behavior, and shortcut remapping.

## Other Features
- Gesture controls for opening/closing the notch and media navigation.
- Parallax hover interactions with smooth transitions.
- Lock screen appearance and positioning controls for panels and widgets.

<p align="center">
  <img src="https://i.postimg.cc/HkLGn6yH/846F86A4_A2F9_4CD6_BC84_1D720D377728_1_201_a.jpg" alt="Atoll preview" width="920">
</p>

## Requirements
- macOS 14.0 or later (optimised for macOS 15+).
- MacBook with a notch (14/16‑inch MBP across Apple silicon generations).
- Xcode 15+ to build from source.
- Permissions as needed: Accessibility, Camera, Calendar, Screen Recording, Music.

## Development Run

Unless a Release package is explicitly required, use the Debug app for development and UI verification instead of packaging or copying a new app into `/Applications`:

```bash
./scripts/dev-run
```

It reuses a fixed DerivedData directory for incremental Debug builds, stops every running Atoll instance, and launches only the app produced from the current working tree. The Debug app is named **Atoll Dev**, uses the existing `com.Ebullioscopic.Atoll.dev` bundle identifier, and is ad-hoc signed so local development does not require the release team's signing certificate.

Running the `DynamicIsland` scheme with Xcode's Run command provides the same incremental build/debug workflow and now stops stale Atoll processes before launch.

Do not create or retain extra `.app` copies for individual changes. `/Applications/Atoll.app` may remain installed as the Release copy, but it must not run at the same time as **Atoll Dev**. Before accepting a runtime result, verify that the active executable comes from `DerivedData/Dev/Build/Products/Debug/Atoll.app` and that its bundle identifier is `com.Ebullioscopic.Atoll.dev`.

### Build cache and release retention

Use one canonical cache per build configuration:

- Debug: `DerivedData/Dev` via `./scripts/dev-run`
- Release: `DerivedData/Release` only when a formal package is explicitly requested
- Release output: one latest artifact under `build/releases`

Do not pass a new `-derivedDataPath`, create commit- or timestamp-named build directories, or leave Atoll test files in `/private/tmp`. Xcode's DerivedData contains all dependency and module caches, so changing the path repeatedly multiplies disk usage without changing the source product.

To remove historical caches, logs, test binaries, and old release artifacts while keeping the current Debug cache:

```bash
./scripts/clean-build-artifacts
```

Use `--dry-run` to inspect the candidates first. Use `--all` only when a complete rebuild is intentional; it also removes `DerivedData/Dev`. The script moves candidates to a recoverable Trash quarantine instead of permanently deleting them.

## Installation
1) Download the latest DMG [here](https://github.com/Ebullioscopic/Atoll/releases/latest).
2) Open the DMG and drag Atoll into Applications.
3) Launch Atoll and grant the requested permissions.

## Quick Start
- Hover near the notch to expand; click to enter controls.
- Use tabs for Media, Stats, Timers, Clipboard, and more.
- Adjust layout, appearance, and shortcuts from Settings.
- Add files to Shelf from Terminal: `open -a Atoll /path/to/file`.

## Settings
- Choose appearance, animation style, and per‑feature toggles.
- Remap global shortcuts and adjust hover behaviour.
- Enable lock screen widgets and select data sources.

## Gesture Controls
- Two-finger swipe down to open the notch when hover-to-open is disabled; swipe up to close.
- Enable horizontal media gestures in **Settings → General → Gesture control** to turn the music pane into a trackpad for previous/next or ±10 second seeks.
- Pick the gesture skip behaviour (track vs ±10s) independently from the skip button configuration so swipes can scrub while buttons change tracks—or vice versa.
- Horizontal swipes trigger the same haptics and button animations you see in the notch, keeping visual feedback consistent with tap interactions.

## Troubleshooting (Basics)
- After granting Accessibility or Screen Recording, quit and relaunch the app.
- If metrics are empty, enable categories in Settings → Stats.
- Media not responding: verify player is active and Music permission is granted.

## License
Atoll is released under the GPL v3 License. Refer to [LICENSE](LICENSE) for the full terms.

This repository is a derivative work of Atoll. The Atoll source, its upstream notices, and the GPL v3 terms remain applicable. Changes specific to the Codex utility are maintained in this repository and should not be presented as part of the official upstream Atoll project.

## Acknowledgments

Atoll builds upon the work of several open-source projects and draws inspiration from innovative macOS applications:

- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) - foundational codebase that provided the initial media player integration, AirDrop surface implementation, file dock functionality, and calendar event display. Major architectural patterns and notch interaction models were adapted from this project.

- [**Alcove**](https://tryalcove.com) - primary inspiration for the Minimalistic Mode interface design and the conceptual framework for lock screen widget integration that informed Atoll's compact layout strategy.

- [**Stats**](https://github.com/exelban/stats) - source implementation for CPU temperature monitoring via SMC (System Management Controller) access, frequency sampling through IOReport bindings, and per-core CPU utilisation tracking. The system metrics collection architecture derives from Stats project readers.

- [**Open Meteo**](https://open-meteo.com) - weather apis for the lock screen widgets

- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) - window rendering for Lock Screen Widgets

- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) - Live music visualizer using C++ was adapted from this project

- [**SwiftTerm**](https://github.com/migueldeicaza/SwiftTerm) - Terminal tab implementation in the standard mode was adapted from this project

- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) - thanks DynamicNotch for letting us use their battery huds

- Wick - Thanks Nate for allowing us to replicate the iOS like Timer design for the Lock Screen Widget

- [**OpenUsage**](https://github.com/robinebers/openusage) - LLM Usage Tracking features

- [**OpenRouter**](https://openrouter.ai) - API for getting automated model pricing

## Contributors

<a href="https://github.com/Ebullioscopic/Atoll/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Ebullioscopic/Atoll" />
</a>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Ebullioscopic/Atoll&type=timeline&legend=top-left)](https://www.star-history.com/#Ebullioscopic/Atoll&type=timeline&legend=top-left)

## Updating Existing Clones
If you previously cloned DynamicIsland, update the remote to track the Atoll repository:

```bash
git remote set-url origin https://github.com/Ebullioscopic/Atoll.git
```

A heartfelt thanks to [TheBoredTeam](https://github.com/TheBoredTeam) for being supportive and being totally awesome, Atoll would not have been possible without Boring.Notch

---

<p align="center">
  <img src=".github/assets/iosdevcentre.jpeg" alt="iOS Development Centre exterior" width="420">
  <br>
  <sub>Backed by</sub>
  <br>
  <strong>iOS Development Centre</strong>
  <br>
  Powered by Apple and Infosys
  <br>
  SRM Institute of Science and Technology, Chennai, India
</p>

<p align="center">
  <a href="https://buymeacoffee.com/kryoscopic">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="200" />
  </a>
</p>

<p align="center">
  Your support helps fund teaching children software development.
</p>
