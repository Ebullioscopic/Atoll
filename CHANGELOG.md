# Changelog

All notable changes to Atoll will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Spotify "Like Song" media control: save or remove the current track from your Liked Songs directly from the notch, lock screen, and minimalist player, using the official Spotify Web API (OAuth 2.0 PKCE). Add the control to any media slot in settings. (#579)

- Show the current Claude subscription plan (e.g. `Max 5x`) as a badge next to the Claude card title in the LLM Usage view (#684).
- **AntiGravity Usage Tracking**: Track how much of Antigravity usage is left in the LLM Usage Monitor tab (both Gemini and Claude models)
- **Shelf item removal**: Hovering a Shelf item now reveals a × button that removes just that item, with a VoiceOver-accessible "Remove from Shelf" action that works without hovering (#461).
- **Draggable clipboard tab**: A `.notchTab` clipboard display mode shows clipboard history as a card grid inside the notch whose text, image, and single-file entries can be dragged straight out to Finder or other apps (drag = copy), with a hover × to delete a single item (#698).

### Changed
- Improved the Dutch localization by adding missing translations, corrected terminology, and wording aligned with Apple's Dutch macOS conventions.
- Refreshing the LLM Usage card now skips session logs whose last write predates the seven-day window instead of re-reading the whole log history, and counts a repeated record when the copy inside the window would previously have been suppressed by a copy outside it (#691).
- The separate-tab clipboard now uses the same card grid (two columns) with drag-out and per-item delete, replacing the single-column list (#698).

### Fixed
- Dragging a rich-text clipboard entry out of the notch now preserves its formatting: the drag offers the styled RTF (with a plain-text fallback) instead of dropping plain text everywhere, so rich-text editors keep bold/color/font while plain-text fields still resolve the drop (#717, closes #712).
- Fixed a hairline gap at the top of the notch during open animation, and hover-to-open flapping when the pointer sits on the top edge, on physical-notch Macs (#681).
- Fixed lock-screen widget readability on bright wallpapers by adding a Dark/Light appearance mode for widget text and controls.
- Fixed Codex Today and Week usage totals remaining at zero when parsing Codex session logs (#664).
- Recover the Claude quota display after Claude Code rotates its OAuth token, instead of showing "quota unavailable" until the app is restarted (#685).
- Fixed the Claude quota staying "quota unavailable" on recent Claude Code versions, which store the OAuth token under a per-install hash-suffixed Keychain item (`Claude Code-credentials-<hash>`) and no longer update the un-suffixed item the app read; the freshest matching item is now used (#699, follow-up to #685).
- Normalized Claude model IDs when pricing local usage so newer IDs are costed instead of showing `US$0.00+`, and show an explicit unavailable/partial estimate when a model isn't in the pricing table (#683, #664).
- Fixed an issue where `BluetoothHUDAnimations` (.mov files) were missing in release builds.
- Improved the GitHub Actions release workflow to use a monotonic build number allocator and automated patch versioning for stable releases.
- Fixed Cursor quota parsing and display to show the current Cursor Models and Other Models billing buckets with readable long reset durations.
- Fixed files dropped onto the Shelf silently disappearing on macOS 26 (Tahoe) by storing plain bookmarks instead of security-scoped ones, which a non-sandboxed app cannot create (#646).
- Fixed the AirPods pause gesture opening Siri instead of pausing Spotify: the real-time waveform no longer process-taps Spotify while a Bluetooth output route is active, and the tap is rebuilt whenever the output route changes.
- Fixed Noise Cancellation, Adaptive Audio, and Conversation Awareness labels being clipped behind the notch in the AirPods listening-mode HUD; every mode is now trailing-aligned and scales down instead of scrolling.
- Fix crash when Apple Notes sync encounters duplicate remote note IDs
- Stopped sending the track title and artist to LRCLIB on every track change while lyrics are switched off; the setting now gates the request, not just the placeholder text (#694).

### Removed

## [2.3.2] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.1] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.0] - 2026-07-20

### Added
- **Lock Screen & Live Activities**: Full support for Lock Screen widgets, Live Activities, and expanding lock screen music players with flip animations.
- **Screen Assistant (AI)**: Introducing Screen Assistant with snipping capabilities and Gemini API integration.
- **Advanced System HUDs**: Dynamic polling HUDs for Volume (mute/unmute), Brightness, Bluetooth, and Privacy Access Indicators.
- **Clipboard Manager**: New floating clipboard manager panel with customizable settings and quick access.
- **System Stats Panel**: Real-time tracking of CPU usage, Memory, Disk Read/Write, and Network usage with circular progress graphs.
- **Custom Timer**: Dedicated Timer UI with custom timer capabilities.
- **Multi-channel Updates**: Switch seamlessly between Nightly, Alpha, Beta, and Stable update channels directly from Settings.
- **Automated CI/CD**: Full automated release pipeline via GitHub Actions using Sparkle.

### Changed
- **UI & Aesthetics**: Major overhaul to support a new Minimalistic UI option, as well as a Frutiger Aero aesthetic option.
- **Onboarding & Settings**: Revamped the onboarding experience and Settings window layout for a cleaner, native macOS feel.
- **Media Player**: Refined NowPlaying detection, expanded the Lock Screen music player, and smoothed out slider behavior.
- **Performance**: Disabled `OSDUIHelper` polling in favor of event-driven system HUD monitoring to drastically reduce CPU footprint.

### Fixed
- Fixed timeline reset and playback jumping issues in the Media Player.
- Fixed jittering animations on brightness and volume HUDs.
- Fixed corner radius clipping and window alignment bugs across multiple popup panels.
- Fixed double conversion network errors and memory usage spikes in the System Stats panel.
- Fixed lock screen GIF tracking via Git LFS.

### ❤️ Special Thanks to Our Contributors
A massive shoutout to everyone who contributed to this milestone release:
Hariharan Mudaliar, Jis G Jacob, Felipe Giacomini Cocco, delli, Federico Imberti, Dan Querido, Soham Sharma, 杨锟, DanFQ, Amir Zarrinkafsh, HerbJul, StellarSea, XiNian-dada, AkhilKonduru1, createthisnl, fatih ozdil, Santiago Quihui, Venkatesh, A-Akhil, Alex, JoelVR2k, Ninzorn, SSylvain1989, landuoduo, and dozens of others!

## [2.2.0] - 2026-05-30
### Added
- Initial release on the new update pipeline