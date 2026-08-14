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
- **Shelf marquee selection**: Dragging on empty space in the Shelf now draws a rubber-band rectangle that selects every item it touches, matching Finder. Holding Shift unions the marquee with the existing selection instead of replacing it (#682).
- **Shelf drag-out move toggle**: A new "Allow moving files when dragging out" setting (off by default) keeps drag-out copy-only. Offering a move operation previously let the receiving app relocate the original file out from under the user when the destination was on the same volume (#682).
- **Agent Tower**: An optional Agents tab shows a live card for every AI coding agent running in a terminal — Claude Code and Codex to start with — with its project, status and elapsed time. Atoll adds an observe-only hook to the agent's own configuration, backing the file up first and touching nothing but its `hooks` section, and removes its entries again when you turn the feature off.
- **Agent Tower context ring**: Each agent card now shows how full that session's context window is — amber past 70%, red past 90% — plus the session title the agent gave itself and how many of its subagents have finished. The window size is calibrated from the tokens actually seen in the transcript rather than guessed from the model name, because a 1M-context session does not always say so in its model identifier; until it is certain, the raw token count is shown instead of a percentage.
- **Agent Tower approvals**: With approvals switched on, a blocked agent's permission prompt appears in the notch — the exact command, an Approve / This session / Deny choice, and a note field to say what it should do instead. Commands are checked for destructive patterns first (recursive deletes outside the project, `sudo`, force pushes, piping a download or a decoded blob into a shell, disk formatting, Keychain deletion) and the reason is shown before you decide. A remembered approval only ever matches the exact command it was given for, is never offered for anything flagged destructive, and is off by default. If Atoll is closed, busy, or unsure it stays silent and your agent's own prompt appears as usual.
- **Agent Tower in the closed notch**: A waiting approval now appears beside the notch without opening it — the tool name, a risk-coloured icon, and a countdown showing how long the agent will keep waiting — and it takes precedence over the music indicator, because an approval nobody sees is worse than a paused album cover. A merely-running agent shows instead as a small count next to your track, so music is not displaced for the length of a long session. Reminders widen as a request goes unanswered (immediately, then 8 seconds, 1, 5 and 15 minutes) with an optional sound, and are silenced by a new privacy mode or by any Focus mode without hiding the request itself.
- **Jump to an agent's terminal**: Clicking an agent card brings its terminal tab to the front. The tab is matched on the controlling terminal device read from the kernel, not on a window title, so it still lands correctly when several agents share one project — exactly when the feature matters. Terminal.app and iTerm2 select the precise tab; every other terminal, including Ghostty, Warp, Kitty and Alacritty, has the right application raised by walking the agent's process tree, which needs no automation permission at all.
- **Agent Tower is explicit about what it has verified**: each agent in Settings now says whether Atoll has confirmed its behaviour or only read its documentation. Claude Code is fully confirmed; Codex is marked "monitoring only", because its configuration shape is confirmed but Atoll has not observed it acting on an approval; Cursor, Gemini CLI and Qwen Code stay "experimental" since they are not installed to check against. Atoll also no longer registers a `Notification` hook for Codex, whose real configuration does not carry one.

### Changed
- Improved the Dutch localization by adding missing translations, corrected terminology, and wording aligned with Apple's Dutch macOS conventions.
- Refreshing the LLM Usage card now skips session logs whose last write predates the seven-day window instead of re-reading the whole log history, and counts a repeated record when the copy inside the window would previously have been suppressed by a copy outside it (#691).
- The separate-tab clipboard now uses the same card grid (two columns) with drag-out and per-item delete, replacing the single-column list (#698).

### Fixed
- Fixed excessive memory usage by streaming LLM usage JSONL files instead of loading them entirely into memory
- Reduced idle CPU from always-on notch hover polling and OSDUIHelper process checks by backing off when the app is idle (#641).
- Rich-text clipboard entries now keep their formatting when dragged out of the notch. Rich content is captured as RTF at copy time — including web/HTML copies (browsers, GitHub) that expose only `public.html`, which is now converted to RTF — and the drag offers that styled RTF with a plain-text fallback. Rich-text editors (TextEdit, Pages, Word) receive the formatting; plain-text targets still get plain text. The exact result depends on what the destination app accepts (#717, closes #712).
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
- Fixed the Shelf freezing for seconds on every drop, and dragging items out delivering the file name as plain text instead of the file itself. Four call sites bridged to `@MainActor` members of `ShelfItem` with a `Task.detached` plus `DispatchSemaphore.wait`, which deadlocks by construction when called from the main actor and always burned its full 5-second timeout: the deduplication pass in `add()` paid that cost once per existing *and* incoming item, and `createPasteboardItem` timed out to a `nil` URL and fell through to writing plain text. Resolved paths are now cached on the item at drop time (and backfilled off the main actor for items persisted earlier), so deduplication, drag-out, and the context menu need no main-actor disk I/O (#682).
- Fixed Open, Open With, Show in Finder, Quick Look, Compress, Copy Path, and the image actions all missing from the Shelf file context menu, caused by `ShelfItem.fileURL` returning a hard-coded `nil` for files (#682).
- Fixed the notch auto-closing in the middle of a drag and cancelling the session: dragging an item out necessarily takes the cursor off the panel, which tore down the view acting as the drag source (#682).
- Fixed an issue where scrolling a long note inside the Dynamic Island returned the view to the home view instead of scrolling the note. (`#636`)

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
