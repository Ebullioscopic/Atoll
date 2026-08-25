<p align="center">
  <img src=".github/assets/atoll-logo.png" alt="Atoll logo" width="120">
</p>
<h1 align="center">Atoll Codex Integration</h1>
<p align="center">基于 Atoll 的本地 Codex 任务状态模块</p>

> **本项目不是官方 Atoll。** 它基于 [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) 开源，并将 Codex 集成作为主要新增能力。

如果你只想了解这个仓库新增了什么，请先看下面的 **Codex 模块**。上游 Atoll 的原始介绍和功能列表已放到后面的“上游 Atoll 基础能力”章节。来源、许可证和差异说明见 [UPSTREAM.md](UPSTREAM.md)、[NOTICE](NOTICE) 和 [LICENSE](LICENSE)。

## Codex 模块

Codex 是本项目面向本地 coding agent 工作流的状态入口。它把 Codex Hook 事件转换为 Atoll 刘海中的轻量状态提示，让用户在切换到浏览器、编辑器或其他应用时，仍能看到 Codex 是否正在运行、等待批准或刚刚完成。

- **任务状态**：展示运行中、等待批准、已完成等状态。
- **刘海提示**：在紧凑态显示 Codex 状态，在展开态展示任务列表。
- **会话跳转**：从任务卡片打开对应 Codex 会话。
- **完成提醒**：对新完成任务提供可确认的提示。
- **可配置**：在 **Atoll Settings → Utilities → Codex** 中控制启用、任务页、预览、全屏显示和通知。
- **单应用交付**：Codex 是 Atoll 内置实用工具，不需要独立的 CodexAtoll 菜单栏 App、第二个安装包或第三方扩展授权。

### 数据边界

集成使用本地 Codex Hooks 和本地状态文件；不解析 transcript，不上传 prompt、源码或终端输出，也不启动用于 Atoll 集成的网络服务。Atoll 只负责把 Codex 的状态做成可见、可回到会话的提示，不替代 Codex 本身。

## 上游 Atoll 基础能力

本项目保留上游 Atoll 的 macOS 刘海体验，包括媒体控制、系统信息、Live Activities、计时器、剪贴板和其他快捷工具。这些属于上游 Atoll 的基础能力；本仓库的主要新增能力是上面的 Codex 模块。

<p align="center">
  <img src="https://i.postimg.cc/t49mW5yN/Screenshot-2026-03-02-at-6-00-22-PM.png" alt="Atoll lock screen" width="920">
</p>





### 上游 Atoll 功能概览
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
当前仓库暂未发布独立 DMG。请先按 [Development Run](#development-run) 从源码运行，或使用 Xcode 构建当前分支；这样运行的才是包含 Codex 模块的版本。

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
