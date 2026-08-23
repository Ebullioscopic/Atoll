# Changelog

All notable changes to Atoll will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Opera downloads are noticed too. Opera is Chromium underneath but names its half-finished files `.opdownload` rather than `.crdownload`, so nothing it downloaded ever raised a live activity.
- **Firefox downloads**: download detection now notices Firefox downloads as well as Chromium and Safari ones. Firefox writes its in-progress file as `.part`, which was not among the extensions watched, so its downloads produced no live activity at all. It also creates the destination file up front as an empty placeholder, which the old completion test read as a cancellation — so a Firefox download that *did* finish would have had its activity yanked away instead of showing the completion animation. Completion is now decided by whether the destination holds data once the temporary file goes, which is the same question for every browser.
- Spotify "Like Song" media control: save or remove the current track from your Liked Songs directly from the notch, lock screen, and minimalist player, using the official Spotify Web API (OAuth 2.0 PKCE). Add the control to any media slot in settings. (#579)

- Show the current Claude subscription plan (e.g. `Max 5x`) as a badge next to the Claude card title in the LLM Usage view (#684).
- **AntiGravity Usage Tracking**: Track how much of Antigravity usage is left in the LLM Usage Monitor tab (both Gemini and Claude models)
- **Shelf item removal**: Hovering a Shelf item now reveals a × button that removes just that item, with a VoiceOver-accessible "Remove from Shelf" action that works without hovering (#461).
- **Draggable clipboard tab**: A `.notchTab` clipboard display mode shows clipboard history as a card grid inside the notch whose text, image, and single-file entries can be dragged straight out to Finder or other apps (drag = copy), with a hover × to delete a single item (#698).
- **Shelf marquee selection**: Dragging on empty space in the Shelf now draws a rubber-band rectangle that selects every item it touches, matching Finder. Holding Shift unions the marquee with the existing selection instead of replacing it (#682).
- **Shelf drag-out move toggle**: A new "Allow moving files when dragging out" setting (off by default) keeps drag-out copy-only. Offering a move operation previously let the receiving app relocate the original file out from under the user when the destination was on the same volume (#682).
- **Screen Recording HUD**: Added a recording live activity with optional native stop controls and configurable hover presentation.

- **Lyrics on the side**: Added ability to show lyrics of the current song when calendar is disabled (#741)

### Changed
- Lock screen and notch music controls now follow Apple's sizing and animation: the hover/press highlight fills a circular target roughly 2.2x the glyph instead of hugging it, play/pause shares that highlight with the rest of the row, and the track title and artist scale up to Apple's lock screen proportions. Pressing next/previous marches the chevrons in the direction of travel rather than sliding the whole button (#742).
- Improved the Dutch localization by adding missing translations, corrected terminology, and wording aligned with Apple's Dutch macOS conventions.
- Refreshing the LLM Usage card now skips session logs whose last write predates the seven-day window instead of re-reading the whole log history, and counts a repeated record when the copy inside the window would previously have been suppressed by a copy outside it (#691).
- The separate-tab clipboard now uses the same card grid (two columns) with drag-out and per-item delete, replacing the single-column list (#698).

### Fixed
- The keyboard backlight HUD and OSD toggles come back when the external display app is quit. They were greyed out by the integration setting alone, but the keys are only handed over while that setting is on *and* the provider is actually running — so quitting it returned the keys to Atoll and left the toggles disabled over a setting that had started working again.
- The notch header's glyphs are sized to look the same, rather than to be the same number. Equal point size is equal cap height, which is not equal optical size: measured at 15pt, `gearshape` covers 289pt² of ink against `web.camera`'s 208 — 39% more — and `list.clipboard` stands 19pt tall against `timer`'s 16. Each symbol now has a point size solved so its ink height lands on 16pt, and they share a box wide enough not to clip the tall ones.
- The notch header's buttons no longer crowd each other. Each is a 30pt target, but they sat 4pt apart — close enough to read as one run of buttons — and each glyph carried a default `.padding()` inside its 30pt capsule, which squeezed it by however much SwiftUI felt like and left the icons visibly unequal. The gap is 8pt and every glyph is set at one size and weight.
- The clipboard manager's header icon is `list.clipboard` rather than `doc.on.clipboard`. The latter is the paste glyph — two sheets over a board — which says "copy this" rather than "the things you have copied". The settings cog is `gearshape`, the shape macOS itself draws, instead of the older `gear`.
- The lyrics and calendar toggles no longer lock each other out. Each was disabled while the other was on, with the lyrics one labelled "Show lyrics on the side (requires calendar off)" — yet the notch's own lyrics button was never gated and the player has always had a layout for both, so the combination was reachable from the notch and refused in Settings. Both toggles are free now, and each says what happens when they are on together: lyrics sit on one line under the artist name while the calendar holds the rest of the notch, and take a panel of their own beside the player when it is off.
- Several lock screen and media settings now say what they actually control. The lock screen widget layout picker sat under "Weather Widget" labelled "Layout" while restyling the entire status capsule — it also changes how the battery indicator (configured in its own section further down) is drawn, and silently greys out the location and sunrise rows. Skip button behaviour was headed "Floating window panel skip behaviour" and hidden behind the floating-window toggle, yet governs the notch, lock screen and floating players alike — turning the floating window off left it in force but unreachable. The "Change Media Output" toggle also decides whether the lock screen panel has a volume control at all, which its description did not mention.
- The lock screen reminder could be switched on, and its chip colour chosen, while the reminder live activity that produces it was off — `evaluateCurrentState()` returns before the `defer` that publishes the lock screen snapshot, so nothing appeared and nothing said why. The same controls in Live Activities settings were already gated on it; the Lock Screen tab now matches, and explains the dependency.
- The lock screen widget layout picker has moved out of the Weather Widget section to Appearance, beside Widget appearance. It never controlled the weather alone: `snapshot.widgetStyle` shapes the focus row, the next-event row, the location segment and the battery gauge as well.
- Temperature now starts in whatever unit macOS itself displays, instead of always starting in Celsius. Read via `UnitTemperature(forLocale:)`, since the Temperature control in Language & Region is set independently of the measurement system — a US-region Mac can be set to Celsius and a metric one to Fahrenheit, and inferring the unit from a formatted measurement follows the measurement system and gets both of those backwards. Only the initial value is affected; a unit already chosen is left alone.
- Volume and brightness step sizes now explain why they are greyed out when an external display app owns those keys, instead of appearing broken — and they grey out only while that app actually owns them. Ownership transfers only while DDC integration is on and the selected provider is running, but the controls were gated on the settings alone, so quitting BetterDisplay or Lunar left them disabled even though Atoll had resumed handling the keys. The volume steppers were gated on the external volume listener by itself, which does not even imply the integration is on.
- The Downloads settings tab says what download detection actually does and which browsers it covers, rather than naming a file extension. The "Download indicator style" heading was also drawn in hardcoded white, which is invisible against a light Settings window, and stayed fully lit while its buttons were disabled.
- Media key interception is no longer disabled for the rest of the session when it cannot start. `MediaKeyInterceptor` attempted `CGEvent.tapCreate` exactly once at startup, and that call fails outright until Accessibility is granted; since granting it does not relaunch the app, a prompt answered late left the volume and brightness keys reaching macOS untouched until the app was restarted — or until a HUD style was switched in Settings and switched back, which retried the tap as a side effect. The tap is now retried until it installs: every 2s for the first minute, then every 15s, giving up after an hour.
- On macOS 26 the native volume HUD is drawn by Control Center rather than `OSDUIHelper`, so the SIGSTOP suppression in `SystemOSDManager` no longer has any effect on it there and interception is what keeps it hidden. Measured on macOS 26.6: with the tap installed and swallowing the volume keys, the Control Center panel did not appear in 10 of 10 trials; without interception it appeared in all 10; writing the volume through CoreAudio does not summon it either. Behaviour on earlier macOS versions, and for the brightness HUD, was not measured.
- Fixed hover-to-open silently dying, and the selected Idle Animation never rendering, whenever Idle Animation was enabled and no media was playing. A duplicated `else if` in the closed-notch view chain had an empty body, and its condition (`!coordinator.expandingView.show`) is a strict subset of the branch below it (`!isCurrentScreenExpansionVisible`), so it always won in the idle case and yielded `EmptyView`. `NotchLayout()` has no intrinsic size, so that collapsed the notch to its padding and took the `.contentShape`/`.onHover` hit area with it — which is why hover appeared to work only while music was playing (#725, closes #540, #624).
- Fixed provider icons stretching into a flat smear inside menu-style pickers (most visibly the AirDrop icon in the Shelf's Quick Share popover). Rendering a picker's selected row into the `NSPopUpButton` title drops SwiftUI's frame but keeps `.resizable()`, so the icon expanded to the button's full width; icons now carry their own point size instead. Also affects the Quick Share picker in Settings and the third-party display app picker.
- Fixed the screen recording HUD stop button collapsing out from under the pointer while the stop request is being sent.
- Fixed the screen recording HUD stop button being ignored while hovering when "Open notch on hover" is enabled, because the hover click monitor opened the notch instead of forwarding the click.
- Fixed stale album artwork appearing during manual track transitions in Apple Music and Spotify by publishing track changes immediately and safely handing off asynchronously fetched artwork.
- Fixed the LLM Usage card prompting for the login keychain password on every refresh when the Gemini language server is down. The app now tries the language server first (no keychain needed), and otherwise reads the Gemini CLI's token through the `security` CLI, which is covered by the item's `apple-tool:` partition grant and never triggers a password prompt.
- Fixed the timer being clipped behind the notch after the layout changes, and made the boxes in StatsView uniformly sized.
- Removed the separate floating timer control window; Pause/Stop buttons now render inline inside the notch, vertically centered with the timer countdown (#711).
- The 3D Bluetooth HUD icon, and its preview tile in Settings, no longer render as an empty box when the bundled animation cannot be decoded. Both call sites decided whether to fall back to the SF Symbol by asking whether a file of that name exists, which is true of a Git LFS pointer stub left by a clone made without git-lfs: the file resolves, the fallback never fires, and the player is handed something undecodable. The movie is now validated before use (#744).
- The notch volume HUD slider now glides between the discrete steps the volume keys deliver instead of jumping from one to the next (#742).
- Fixed a launch crash (`BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively`) that could trap while a Bluetooth audio device was connected. `BluetoothAudioManager`'s initialiser scanned connected devices synchronously, and that scan blocks on `Process.waitUntilExit()`, which spins the run loop — letting SwiftUI evaluate a view body that reads `BluetoothAudioManager.shared` and re-enter the initialiser that was still running. The scan now starts on the next main-queue turn instead.
- Fixed excessive memory usage by streaming LLM usage JSONL files instead of loading them entirely into memory
- Reduced idle CPU from always-on notch hover polling and OSDUIHelper process checks by backing off when the app is idle (#641).
- Rich-text clipboard entries now keep their formatting when dragged out of the notch. Rich content is captured as RTF at copy time — including web/HTML copies (browsers, GitHub) that expose only `public.html`, which is now converted to RTF — and the drag offers that styled RTF with a plain-text fallback. Rich-text editors (TextEdit, Pages, Word) receive the formatting; plain-text targets still get plain text. The exact result depends on what the destination app accepts (#717, closes #712).
- Fixed a hairline gap at the top of the notch during open animation, and hover-to-open flapping when the pointer sits on the top edge, on physical-notch Macs (#681).
- Fixed lock-screen widget readability on bright wallpapers by adding a Dark/Light appearance mode for widget text and controls.
- Fixed Codex Today and Week usage totals remaining at zero when parsing Codex session logs (#664).
- Recover the Claude quota display after Claude Code rotates its OAuth token, instead of showing "quota unavailable" until the app is restarted (#685).
- Fixed the Claude quota staying "quota unavailable" on recent Claude Code versions, which store the OAuth token under a per-install hash-suffixed Keychain item (`Claude Code-credentials-<hash>`) and no longer update the un-suffixed item the app read; the freshest matching item is now used (#699, follow-up to #685).
- Normalized Claude model IDs when pricing local usage so newer IDs are costed instead of showing `US$0.00+`, and show an explicit unavailable/partial estimate when a model isn't in the pricing table (#683, #664).

### Removed

## [2.3.3] - 2026-07-24

### Added

### Changed

### Fixed
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
- Fixed the notch auto-closing in the middle of a drag and cancelling the session: dragging an item out necessarily takes the cursor off the pointer, which tore down the view acting as the drag source (#682).
- Fixed an issue where scrolling a long note inside the Dynamic Island returned the view to the home view instead of scrolling the note. (`#636`)
- Fixed Dynamic Island window pinning so it stays anchored while switching macOS Spaces.
- Fixed Atoll being terminated by macOS when starting a voice recording in the Screen Assistant: the app now declares a microphone usage description, which it was missing entirely.
- Closed the extension RPC port to the local network. It was documented as listening on localhost but bound the wildcard address, so anything on the same Wi-Fi could reach port 9020 and drive the extension API — a client identifies itself simply by stating a bundle identifier. It now binds the loopback address of each family, and any connection from elsewhere is refused before it can send anything.
- Stopped the Bluetooth battery refresh from stalling the interface. It ran `system_profiler` and `pmset` on the main thread — about 200 ms each time — at launch and again on every connect, disconnect and refresh, four times in the first twenty seconds of a session here. Those two now run in the background, and the `system_profiler` reading is shared for 30 seconds instead of being taken separately for battery levels and for each device's model lookup, so a connect no longer spawns it twice. Battery levels are unchanged; on a cold start the percentage can arrive a moment after the device does, which the existing brief wait before showing the connection already covers.
- Fixed Notch expansion FPS stutter. Music and Timer managers now cache `NSHostingView` fitting sizes and reuse them for hover-only updates. When the panel size is unchanged, the window moves with `setFrameOrigin` instead of `setFrame`; `FlyoutFrameCalculator.swift` centralizes the flyout placement calculation (#741).
- Fixed Canvas desync during Notch transitions. Static artwork is rendered by SwiftUI, while Spotify Canvas uses an `AVPlayerLayer` hosted in an `NSViewRepresentable`. During close, the video layer implicitly animated its own frame in a separate Core Animation transaction, creating a second, slower slide-out that conflicted with SwiftUI’s transition (#741).

- Fixed the clipboard history shortcut being registered as Cmd+Shift+C while Settings documented Cmd+Shift+V ("similar to Windows+V on PC"). The default is now Cmd+Shift+V, and a one-time migration moves persisted Cmd+Shift+C values, since `KeyboardShortcuts` persists a default on first launch and would otherwise keep the old key forever, and a stored value does not record whether it came from that default or from a deliberate Cmd+Shift+C choice. Every other custom shortcut is left alone.

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
