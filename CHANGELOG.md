# Changelog

All notable changes to Atoll will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Highlights
- **Lyrics that follow the music:** synced lyrics sweep word by word in time with playback — beside the player, pinned under the closed notch, and in a new lyrics column on the lock screen — with NetEase Cloud Music as a fallback source.
- **A more capable lock screen:** a volume slider under the playback controls, a large-artwork player that opens on lock, a fingerprint unlock animation, colored widgets, a custom weather city and a day-range temperature gauge.
- **More music sources, more control:** TIDAL, NetEase Cloud Music, QQ Music and Auto Detect join the source picker, and the heart control favourites songs in Apple Music, Spotify, YouTube Music and Cider.
- **New notch controls:** a per-app volume mixer, Keep Awake, screen and keyboard cleaning modes, a swipe-between-tabs gesture, a default tab, a tab rail and adjustable animation speed.
- **LLM Usage grows up:** GitHub Copilot, OpenRouter, DeepSeek, New API and Antigravity tracking, with cache-aware cost estimates and a remaining-quota view.
- **Productivity:** a redesigned clipboard with a draggable in-notch tab and Maccy support, file conversion and marquee selection on the Shelf, a pop-out terminal, and 3 Days, Week and Month calendar views.
- **Settings backup:** export your settings to a file and import them on the same Mac or another one.
- **Performance and battery life:** much less idle CPU and background polling, smoother 120 Hz animation, and bounded memory for LLM usage logs and lock screen artwork.
- **Ready for macOS 27:** fullscreen hover, display detection, AirPlay and Siri overlay compatibility fixes.

### Added
- **Notch:** Swipe two fingers left or right over the tab bar to switch tabs. Off by default. (#794)
- **Notch:** A "Close automatically after 3 seconds" option lets the Toggle Notch Open shortcut keep the notch open until pressed again. On by default. (#435)
- **Notch:** With "Hide until hovered on non-notch displays" and "Open notch on hover" on, an option opens the full notch straight away on hover. Off by default. (#577)
- **Notch:** An island top margin slider (0–12 pt, 6 pt by default) for external displays using the Dynamic Island style. (#487)
- **Notch:** An "Open to" setting chooses which enabled tab the notch opens on, alongside the automatic and remember-last-tab behaviours. (#905)
- **Notch:** A slider speeds up the expand, collapse and hover animations from 1× to 2×; with Reduce Motion on, the notch uses a short fade. (#907)
- **Notch:** The tab switcher can sit as a rail down the leading edge instead of in the header, and can switch tabs on hover. (#693)
- **Notch:** Left and right arrow keys can seek the playing track by 10 seconds while the notch is open on the home view. Off by default. (#768)
- **Notch:** A per-app volume mixer in the header gives each app playing audio its own volume slider and mute button, remembered per app. Off by default. (#805)
- **Notch:** Keep Awake keeps the Mac awake indefinitely or for 15 minutes to 4 hours, with an option to keep the display on, ⌘⇧K to toggle it, and a separate option to stay awake with the lid closed. (#804, #677)
- **Notch:** Clean screen blacks out every display and Clean keyboard ignores key presses until you click, so you can wipe them down. Off by default. (#677)
- **Media:** TIDAL can be selected as the music source, with its own Now Playing session, real-time waveform and official logo. (#764, #775, #782)
- **Media:** NetEase Cloud Music, QQ Music and Auto Detect can be picked as the music source; other players no longer take over the notch. (#913, #816, #721)
- **Media:** The heart control favourites the playing song in Apple Music, Spotify and YouTube Music — no subscription or developer credentials required — and shows TIDAL's favourite state. (#599, #702, #788)
- **Media:** A Spotify "Like Song" control saves or removes the current track from your Liked Songs from the notch, lock screen and minimalist player. (#454, #579)
- **Media:** Favourite the current song in Cider through Cider's local API; add its token in media settings. (#788)
- **Media:** TIDAL's shuffle and repeat buttons now actually change playback. (#788)
- **Media:** The source picker says what each source supports and shows each app's own icon; unsupported controls are dimmed rather than hidden. (#788)
- **Lyrics:** Show lyrics on the side of the player when the calendar is off. (#739, #741)
- **Lyrics:** The sung line is lit by a highlight that sweeps word by word in time with the music, with a Sweep or Solid setting; instrumental breaks show as music notes. (#755)
- **Lyrics:** Pin the current line under the closed notch, with Current, 3-line or 5-line context and a stable height through intros and instrumental breaks. Off by default. (#806, #828)
- **Lyrics:** When LRCLIB has nothing, lyrics are looked up in NetEase Cloud Music's catalogue, confirmed by duration. (#713, #812)
- **Lock Screen:** A volume slider sits under the playback controls, with an "Always show volume control" option; the volume keys move it while the Mac is locked. (#745, #770)
- **Lock Screen:** The expanded player carries the whole song in its own lyrics column, scrolling to and sweeping the line being sung. (#496, #755)
- **Lock Screen:** An option opens the lock screen player with large album art as soon as the Mac locks, without changing the wallpaper. Off by default. (#490)
- **Lock Screen:** An option hides the music panel and widgets while a screen saver runs. Off by default. (#819)
- **Lock Screen:** Weather can use a city you type instead of Location Services, for Macs that can't find their position. Off by default. (#934)
- **Lock Screen:** With "Use colored gauges" on, the inline layout colors its weather, battery, charging, Bluetooth and air quality icons. (#434)
- **Lock Screen:** The temperature gauge shows the day's low-to-high range as a gradient with a dot for the current reading, and colors Fahrenheit readings correctly. (#786)
- **Lock Screen:** Choose a lock, an animated fingerprint scan, or both as the lock screen activity. (#774)
- **Lock Screen:** A Dark/Light appearance mode keeps widget text and controls readable on bright wallpapers. (#689)
- **Lock Screen:** Widgets step aside for the macOS 27 Siri overlay, with a configurable, battery-friendly detection mode. (#512)
- **HUDs:** A HUD when the Mac goes offline, and a compact HUD with the network name when it connects to Wi-Fi or Personal Hotspot. (#827)
- **HUDs:** The charging HUD shows actual charging watts, and the battery popover shows charging power and total power input. (#894)
- **HUDs:** A screen recording live activity with an optional stop control and configurable hover presentation. (#552)
- **Downloads:** An option shows the current download speed beside the indicator. Off by default. (#795)
- **Downloads:** Firefox, Opera and Free Download Manager downloads now raise the download live activity. (#578, #759, #321)
- **Calendar:** 3 Days, Week and Month views, switchable beside the date or in Settings; Month shows every week without scrolling. (#482, #802)
- **Calendar:** Turn off "Show date picker" for a minimal calendar that shows only the day's events. (#341)
- **Calendar:** A "Show beside music player" option keeps the calendar off the Home tab while music is playing. (#920)
- **Calendar:** Double-click a day to open it in Calendar, Fantastical or Notion Calendar. (#383, #236)
- **Timer:** Double-click a running timer's name to rename it. (#824)
- **Timer:** Choose how long the timer rings and how long it stays silent before reminding you again; reminders continue in overtime until stopped. (#859, #865)
- **Timer:** Timers started in the Clock app appear in the notch with inline pause and stop controls and overtime. (#672, #726)
- **Terminal:** Pop the terminal out into a floating window that stays above other apps, and return it to the notch with the same session. (#372)
- **Terminal:** An option opens the notch on the Terminal tab while a command is running. Off by default. (#604)
- **Shelf:** Right-click a file and choose Convert To for images, video, audio and rich text; the original is never modified. (#730)
- **Shelf:** Drag on empty space to marquee-select items, with Shift to add to the selection. (#433, #682)
- **Shelf:** Hover an item to reveal a × button that removes just that item, also available to VoiceOver. (#461, #649)
- **Shelf:** An "Allow moving files when dragging out" setting; drag-out is copy-only by default. (#682)
- **Clipboard:** A notch tab shows clipboard history as a card grid whose items can be dragged straight into other apps, with per-item delete. (#697, #698)
- **Clipboard:** Use Maccy as the clipboard source; the clipboard icon then opens Maccy and Atoll releases its own shortcut. (#748)
- **Clipboard:** A "Save History Across Restarts" setting; with it off, history (including images) is kept in memory only. (#727, #743)
- **LLM Usage:** GitHub Copilot quotas (premium requests, chat, completions) with plan and reset date, for GitHub.com and `ghe.com`. Off by default. (#940)
- **LLM Usage:** OpenRouter spend for today and this week and your key's credit limit, with optional per-model analytics. Off by default. (#709, #834)
- **LLM Usage:** DeepSeek prepaid balance per currency, with a low-balance warning. Off by default. (#709)
- **LLM Usage:** Monitor multiple New API accounts with balance, usage, RPM, TPM and request counts; keys are kept in the Keychain. (#752)
- **LLM Usage:** Antigravity tracking for Gemini and Claude models, with token counts, estimated cost and reset countdowns; pool rows no longer show quotas as dollar amounts. (#638, #811)
- **LLM Usage:** The Claude card shows your subscription plan as a badge. (#684)
- **LLM Usage:** An option shows remaining quota instead of usage; an unused quota shows an empty gauge. (#868)
- **LLM Usage:** Cost estimates price cache reads and writes at the provider's cache rates. (#811)
- **Screen Assistant:** The OpenAI provider accepts a custom base URL and model ID for OpenAI-compatible proxies and local servers. (#348, #807)
- **Extensions:** Extensions can request content-only tabs that manage their own scrolling. Requires AtollExtensionKit with `contentLayout`. (#602, #817)
- **Extensions:** Extensions settings link to the Marketplace at getatoll.app/marketplace. (#773, #783)
- **Settings:** Export your settings to a JSON file and import them again; API keys, sign-ins and private data are never included. (#885)

### Changed
- **Performance:** Opening, closing and hovering the notch is smoother on 120 Hz displays, with less main-thread work during animation.
- **Performance:** Lower CPU while the notch is open: progress, lyrics and audio animations are capped at 30 fps, Spotify Canvas decodes once, and the artwork glow is cached. (#825, #839)
- **Performance:** Less rendering work while a timer is running. (#862)
- **Performance:** The Shelf loads items lazily and reads file metadata off the main thread, so drops and drags stay responsive. (#932, #842, #814, #688, #669)
- **Performance:** Much less idle CPU: hover, OSD, clipboard, Bluetooth, brightness and Focus monitoring are event-driven or run only when needed, and pause while the display sleeps. (#641, #654, #690, #720, #853)
- **Performance:** Checking for macOS's HUD helper is now a direct kernel query instead of a subprocess, previously Atoll's largest CPU consumer. (#767)
- **Performance:** The notch no longer re-renders every second while system stats are monitored, and stats sampling is lighter. (#653, #656)
- **Performance:** Bounded Shelf thumbnail cache and fewer memory leaks in audio and battery observers. (#653)
- **Performance:** LLM usage logs are streamed, skipped when outside the 7-day window and split in one pass, keeping memory flat on very large logs. (#655, #691, #701, #710, #718, #870)
- **Design:** Music controls follow Apple's sizing and animation, with circular hover targets and animated skip chevrons. (#742, #750)
- **Design:** The notch volume HUD glides between steps. (#742)
- **Design:** The LIVE indicator on streams follows Apple's thin-rule design across the notch, lock screen and floating player. (#761)
- **Design:** The battery with its percentage inside is drawn the way Apple draws it, and the option now works outside Minimalistic UI. (#760)
- **Design:** The charging notification draws a lightning bolt inside its battery icon. (#486)
- **Design:** Notch header icons are optically balanced and evenly spaced; the clipboard uses `list.clipboard` and settings `gearshape`. (#763)
- **Clipboard:** A redesigned panel with search, a sliding segmented control and card rows with thumbnails; the separate-tab clipboard uses the same two-column grid. (#698, #743)
- **Lock Screen:** The music player sits lower, its sliders rest grey until used, play/pause is larger than its neighbours, and the source badge sits on the artwork's corner. (#750)
- **Lock Screen:** The lock icon uses the system `lock.fill` symbol, and the lock and fingerprint timings follow the selected icon. (#774)
- **Lock Screen:** The expanded player waits 30 seconds before collapsing, and never while the pointer is on it. (#755)
- **Lock Screen:** The default player width is 390 pt, with a maximum of 460 pt.
- **Timer:** Pause and stop controls appear inline in the notch instead of in a separate floating window. (#711, #726)
- **Displays:** "Show on a specific display" remembers displays by hardware ID, so identical monitors can be told apart; same-named displays are numbered. (#696)
- **Settings:** Lock Screen settings are split into General and Widgets, Lock Screen Glass lives in one place, and segmented pickers animate like the clipboard panel. (#373, #787)
- **Settings:** Settings describe what they actually control; the widget layout picker moved to Appearance, and lyrics and calendar can now be on together. (#753)
- **Settings:** Temperature starts in the unit macOS displays. (#753)
- **Settings:** The lock screen reminder controls are disabled, with an explanation, while the reminder live activity is off. (#753)
- **Settings:** Downloads settings explain what download detection covers. (#759)
- **Lyrics:** Lyrics lookups fall through to the next provider when one fails, not only when it finds nothing. (#828)
- **LLM Usage:** The pricing table covers current Claude, GPT and Gemini models, and usage-log model IDs are matched more flexibly. (#811)
- **LLM Usage:** Codex usage is priced by the model each session actually used. (#811)
- **Localization:** French, Korean and Simplified Chinese are complete, and Spanish, Turkish and Dutch are improved. (#651, #666, #695, #703, #714, #789, #856, #911, #935)
- **Localization:** Traditional Chinese (zh-Hant) is now available. (#676)
- **Localization:** 168 previously hard-coded strings can now be translated. (#789)

### Fixed
- **Notch:** Clicking the notch over a full-screen app no longer leaves the app's title bar and the menu bar showing. (#386)
- **Notch:** Hovering the wings of a closed live activity no longer makes the notch shake or flicker. (#444, #943)
- **Notch:** A hover exit no longer closes the notch right after it opens. (#457, #823, #832, #941)
- **Notch:** The notch stays centred under the camera when a HUD, track change or animation needs more room. (#505, #514, #836, #898)
- **Notch:** Hover-to-open and the idle animation work again while nothing is playing. (#540, #545, #624, #725)
- **Notch:** No hairline gap at the top of the notch while opening, and no hover flapping at the top edge. (#673, #681, #715)
- **Notch:** Opening and closing the lid in clamshell mode or connecting a display no longer misplaces the notch. (#327)
- **Notch:** With "Hide until hovered", the notch hides again when the pointer leaves along the top edge. (#487)
- **Notch:** On macOS 27, the notch can be opened by hover in fullscreen and no longer disappears when the saved display can't be found. (#632, #757)
- **Notch:** Hiding in fullscreen works in Split View, ignores the same app's fullscreen windows on other Spaces, and follows the app macOS reports as Now Playing. (#409, #528, #936)
- **Notch:** Live activities no longer cover the frontmost app's menus; they slide aside, gather to one side or fold into the notch. (#793, #837, #844, #942)
- **Notch:** Scrolling no longer leaves the open notch blurred and dimmed. (#330)
- **Notch:** One swipe skips one track, not several.
- **Notch:** Short text no longer scrolls in the marquee.
- **Notch:** Menu-style pickers no longer stretch their icons. (#746)
- **Notch:** The notch window no longer shrinks below its normal size for inline sneak peeks.
- **HUDs:** macOS's own volume and brightness HUD is no longer frozen, stuck or misplaced, including after quitting or a crash, and is left alone when Atoll draws no HUD. (#593, #668, #803, #908)
- **HUDs:** Volume no longer keeps changing after rapid key presses, and steps pressed after a mute apply correctly. (#892)
- **HUDs:** The volume HUD shows the icon of the device actually playing, and its speaker icon is visible in Light Mode. (#792, #879, #912)
- **HUDs:** "Use accent color" follows the macOS accent colour. (#379)
- **HUDs:** Vertical and circular HUDs no longer appear twice on one screen with multiple displays. (#419, #846)
- **HUDs:** The keyboard backlight HUD appears for dedicated illumination keys, including keys remapped with Karabiner-Elements. (#276)
- **HUDs:** With Lunar or BetterDisplay, Atoll handles the volume keys for outputs those apps can't control. (#465)
- **HUDs:** Brightness keys no longer snap back after auto-brightness changes the level. (#737, #852)
- **HUDs:** Media key interception retries until Accessibility is granted, which also keeps macOS 26's native volume HUD hidden. (#377, #601, #751)
- **HUDs:** Switching off the custom OSD dismisses it immediately. (#785)
- **HUDs:** Step-size settings and keyboard backlight toggles are only disabled while an external display app actually owns the keys.
- **HUDs:** No phantom AirPods noise-control pop-ups on track changes. (#822)
- **HUDs:** Repeated identical HUDs no longer re-animate the notch, and camera and microphone indicators no longer flicker. (#893)
- **HUDs:** The camera indicator handles Camera Extension and phone cameras correctly. (#884)
- **HUDs:** The microphone indicator follows which apps are actually recording and no longer gets stuck. (#858)
- **HUDs:** Brief screen captures, such as AltTab thumbnails, no longer flash the recording activity. (#362)
- **HUDs:** The Focus toast no longer replays after unrelated HUDs. (#415)
- **HUDs:** The screen recording stop button works while hovering and stays put while stopping. (#552)
- **HUDs:** The 3D Bluetooth HUD falls back to a symbol instead of an empty box when its animation can't be loaded. (#744)
- **Media:** Track changes no longer show stale artwork in Apple Music and Spotify, and Spotify artwork catches up after ads. (#103, #738)
- **Media:** Streamed Apple Music tracks get their own artwork, and local recordings no longer get an unrelated cover. (#404, #876)
- **Media:** The Apple Music progress bar no longer jumps when the notch opens. (#356)
- **Media:** The Now Playing source no longer disappears from the picker after a failed startup check. (#745, #816, #904, #913, #921)
- **Media:** Lyrics and the progress bar no longer drift ahead or behind after pausing, or run ahead of the music.
- **Media:** Impossible remaining times are shown as `--:--`, and unusable durations no longer crash the slider.
- **Media:** The real-time waveform picks up players started later and no longer stays flat. (#740, #833)
- **Media:** Custom Lottie visualizers can be selected and shown, and invalid URLs no longer crash Atoll. (#40)
- **Media:** The output picker's volume slider can be dragged, its mute glyph fits its button, and closing one picker no longer closes the notch.
- **Media:** Volume no longer reads as zero on outputs that publish no per-channel level.
- **Media:** The expanded player's time labels no longer overlap its controls at scaled resolutions. (#836, #900)
- **Media:** Inline lyrics no longer crowd the transport controls, and the minimalistic player's lyrics no longer overlap the timer. (#838)
- **Media:** Spotify ads no longer open an oversized Now Playing HUD, and TIDAL keeps its state when a YouTube video briefly takes over. (#827)
- **Media:** With the battery hidden, the minimalistic player's artwork stays below the notch. (#875, #925)
- **Media:** Atoll no longer quits when Music reports no AirPlay devices on macOS 27. (#659, #799)
- **Media:** The AirPlay picker shows its empty state when no devices are found.
- **Lyrics:** Untagged tracks and different versions (karaoke, remix, live) no longer get the wrong lyrics.
- **Lyrics:** Timed lyrics are preferred over untimed ones, and untimed lyrics are shown as separate lines.
- **Lyrics:** The pinned strip no longer shows the previous song's lyrics, and an "instrumental" match for a different recording no longer stops the search. (#828)
- **Lyrics:** Lines appear on time, keep moving on streams without a duration, clear when none is current, and scroll back to the top on a new track.
- **Lock Screen:** Lock screen widgets, artwork and overlays appear on the display set as main. (#374, #524, #945)
- **Lock Screen:** Turning off weather no longer hides the other status widgets, and stops weather and location requests. (#523)
- **Lock Screen:** Full-screen artwork no longer freezes Atoll on song changes or spikes memory past 1 GB. (#791, #866)
- **Lock Screen:** Full-screen artwork restores your full wallpaper setup, including Shuffle and Aerials, on unlock. (#488)
- **Lock Screen:** The player keeps your liquid glass style with large artwork. (#495)
- **Lock Screen:** The lock screen notch matches the physical notch, with no hairline above it. (#887, #899)
- **Lock Screen:** The unlock animation completes in one clean contraction, and the notch's top corners are restored. (#774, #782)
- **Lock Screen:** Atoll no longer draws HUDs nobody can see while locked, and muting empties the volume capsule. (#745)
- **Lock Screen:** The music player comes back if something hides it while locked.
- **Lock Screen:** Layout fixes for the volume slider, seek bar, expanded player spacing and output device row, and play/pause responds without lag.
- **Lock Screen:** The positioning preview can move widgets as far as the setting allows.
- **Settings:** The Controls tab no longer overflows the window, the swipe indicator no longer overlaps settings, and stray dividers and mislabelled footers are fixed. (#787)
- **Calendar:** The music player, calendar and Mirror no longer squeeze or overlap each other on the Home tab. (#447, #800, #933)
- **Calendar:** Switching days is fast again with large Reminders libraries. (#513)
- **Calendar:** Calendar and Reminders permissions are shown and handled independently. (#657, #886, #919, #929)
- **Calendar:** Zoom's Join button opens the meeting. (#813)
- **Timer:** The timer keeps counting while the Mac sleeps and rings on wake if it ran out. (#271)
- **Timer:** A finished timer no longer hides a newly started one. (#644)
- **Timer:** Scrolling the presets list no longer closes the notch, and the Timer tab no longer leaves empty space or clips behind the notch. (#711, #726)
- **Terminal:** Input method candidates appear above the terminal. (#548, #639)
- **Terminal:** No grey flash when switching to the Terminal tab. (#854)
- **Terminal:** Drag-selection scrolls through the scrollback at the edge. (#895)
- **Shelf:** Links and text dropped on the Shelf are visible and removable. (#902)
- **Clipboard:** Rich text keeps its formatting when dragged out. (#712, #717)
- **Clipboard:** Clearing favorites deletes their images, a saved panel position stays on screen, and the copy checkmark no longer resets early. (#743)
- **Clipboard:** Clipboard descriptions show the shortcut you actually have bound. (#743)
- **Downloads:** Paused downloads show a pause glyph instead of a spinner, and resumed downloads are picked up again. (#922, #923)
- **Notes:** Note titles and the search field are visible while typing in Light Mode. (#927, #928)
- **Stats:** The Stats tab keeps updating with the notch on several displays. (#851)
- **Stats:** CPU temperature works on M5-series Macs. (#585, #797)
- **Stats:** Stats boxes are uniformly sized and aligned. (#826)
- **Battery:** The battery popover is readable in Light Mode. (#494, #924)
- **Battery:** UI Mode only shows battery controls that can be used. (#930)
- **AirPods:** Battery reads no longer hold a Bluetooth connection open. (#565)
- **LocalSend:** Transfers to LocalSend 1.18 receivers in HTTPS mode work. (#815)
- **Screen Assistant:** The response window can be dragged by its header. (#292)
- **Permissions:** Accessibility grants are noticed whenever they happen, and the prompt appears at most once per version. (#443, #897)
- **Permissions:** Fewer Developer Tools Access prompts from the AirPods and Clock timer monitors. (#280)
- **LLM Usage:** Reading the Claude quota no longer logs Claude Code out or causes repeated Keychain prompts. (#820, #831)
- **LLM Usage:** The Claude quota recovers after token rotation and supports newer Claude Code Keychain items. (#685, #699)
- **LLM Usage:** Claude reset countdowns appear again. (#810)
- **LLM Usage:** Claude and new OpenAI models are priced instead of showing `US$0.00+` or `n/a`. (#664, #683, #818)
- **LLM Usage:** Codex Today and Week totals are no longer stuck at zero. (#664, #686)
- **LLM Usage:** Gemini no longer prompts for the login keychain password on every refresh, and Antigravity no longer prompts repeatedly. (#726)
- **LLM Usage:** Antigravity server discovery is reliable on busy Macs, and its card title fits on one line. (#811)
- **LLM Usage:** The LLM Usage tab is the same height as other tabs. (#811)
- **Stability:** Atoll no longer spins a CPU core after a `log stream` helper exits, and stops those helpers when it quits. (#891, #939, #946)
- **Stability:** High-memory alerts are based on the real memory footprint. (#869, #918)
- **Stability:** A launch crash with a Bluetooth audio device connected is fixed.
- **Localization:** Russian clipboard history size labels are correct. (#724, #926)
- **Localization:** Korean formatting, typos and product names are corrected. (#789, #911)

### Removed
- **Screen Assistant:** The Display Mode setting; its Popover option never worked, and the shortcut now always opens the assistant panel. (#58)
- **Timer:** The separate floating timer control window, replaced by inline controls. (#711)

### Security
- **Privacy:** Clipboard history skips content that password managers mark as private or transient. (#938)
- **Privacy:** Your OpenAI key is only sent to OpenAI; custom servers require HTTPS unless running on this Mac. (#807)
- **Privacy:** Copilot, OpenRouter, DeepSeek and New API credentials are stored in the Keychain. (#709, #752, #834, #940)
- **Policy:** `SECURITY.md` explains how to report vulnerabilities privately through GitHub. (#776)

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
- Moved the Gemini, OpenAI, Claude, and Groq API keys out of plaintext preferences into the Keychain, migrating any key already saved on first launch.
- Turning off Camera or Microphone detection now stops the monitor behind it instead of only hiding its indicator, and turning it back on starts it without relaunching the app (#692).

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
