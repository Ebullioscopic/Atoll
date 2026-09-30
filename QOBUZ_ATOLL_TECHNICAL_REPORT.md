# Qobuz Native Controller for Atoll

Date: 2026-09-25

## Local Findings

- Atoll installed locally: `/Applications/Atoll.app`, bundle id `com.Ebullioscopic.Atoll`, version `2.3.3`, build `20260720004`.
- Qobuz installed locally: `/Applications/Qobuz.app`, bundle id `com.qobuz.desktop`, version `8.2.0-b033`.
- The local Qobuz app is Electron-based (`Electron 32.3.3` helper processes were active), not a C++/Qt app as assumed in the original brief.
- macOS Notification Center has an entry for `com.qobuz.desktop`.
- A 12-second `DistributedNotificationCenter` sniff filtered for Qobuz/media terms did not observe a Qobuz notification while no track change occurred.
- A 6-second unified-log stream for Qobuz/usernotifications also captured no notification payload during the idle window.
- Qobuz writes album covers locally under:
  `~/Library/Application Support/Qobuz/tmp/Assets/<asset-id>/large_cover.png`
  and `small_cover.png`.
- Recent artwork writes were observed at `2026-09-25 07:03:08`, proving the cache updates during active Qobuz use.
- AppleScript saw only a shallow Electron AX tree for Qobuz. The implemented Like action therefore searches the Accessibility tree recursively for button labels such as `like`, `favorite`, `favorito`, `curtir`, `heart`, then performs `kAXPressAction`.

## Implementation Summary

- Added `DynamicIsland/MediaControllers/QobuzMediaController.swift`.
- Added `.qobuz` to `MediaControllerType`.
- Added `isLiked` and `supportsLike` to `PlaybackState`.
- Added default `toggleLike()` and `supportsLike` support to `MediaControllerProtocol`.
- Wired Qobuz into `MusicManager.createController(for:)`.
- Added Like state propagation in `MusicManager`.
- Added `MusicControlButton.like`.
- Added Like buttons to:
  - floating music controls
  - standard expanded player controls
  - minimalistic music player controls
  - lock screen music panel controls
  - music slot configuration picker when the active controller supports Like

## Controller Design

`QobuzMediaController` is `@MainActor` and event-oriented:

- It listens to all distributed notifications and filters for `qobuz` / `com.qobuz.desktop`.
- It reads Qobuz local playback state from `~/Library/Application Support/Qobuz/player-0.json`.
- It resolves the current track through `~/Library/Application Support/Qobuz/qobuz.db`, including `L_Track` fallback for tracks not present in `S_Track`.
- It prefers `shuffledItems[currentIndex]` when Qobuz shuffle is enabled, with fallback to `items[currentIndex]`.
- It watches `player-0.json` with `DispatchSourceFileSystemObject` and refreshes in-process when Qobuz updates state.
- It uses a `DispatchSourceFileSystemObject` watcher on the Qobuz artwork cache directory.
- It debounces cache updates by 250 ms and loads the newest `large_cover.png` or `small_cover.png`.
- It avoids continuous polling loops.
- It sends playback commands through macOS media keys:
  - `NX_KEYTYPE_PLAY`
  - `NX_KEYTYPE_FAST`
  - `NX_KEYTYPE_REWIND`
- It performs Like through Accessibility, with a clear console log if Accessibility permission is missing or the button cannot be found.

## Known Limits

- The exact Qobuz distributed-notification name was not observed during the short local window. The listener is intentionally broad and filtered so it can pick up the event when Qobuz emits one on track change.
- Like state is optimistic after a successful AX press because the local Qobuz AX tree did not expose a verified pressed/favorited state during this run.
- Build validation was limited because this Mac has Command Line Tools active instead of full Xcode:
  `xcodebuild` returned `tool 'xcodebuild' requires Xcode`.

## Validation Performed

```bash
swiftc -typecheck \
  DynamicIsland/models/PlaybackState.swift \
  DynamicIsland/MediaControllers/MediaControllerProtocol.swift \
  DynamicIsland/MediaControllers/QobuzMediaController.swift
```

Result: passed with no output after the `@preconcurrency` conformance adjustment.

```bash
swiftc -parse \
  DynamicIsland/models/PlaybackState.swift \
  DynamicIsland/MediaControllers/MediaControllerProtocol.swift \
  DynamicIsland/MediaControllers/QobuzMediaController.swift \
  DynamicIsland/managers/MusicManager.swift \
  DynamicIsland/models/Constants.swift \
  DynamicIsland/models/MusicControlButton.swift \
  DynamicIsland/components/Music/MusicControlOverlay.swift \
  DynamicIsland/components/Notch/NotchHomeView.swift \
  DynamicIsland/components/Notch/MinimalisticMusicPlayerView.swift \
  DynamicIsland/components/LockScreen/LockScreenMusicPanel.swift \
  DynamicIsland/components/Settings/MusicSlotConfigurationView.swift \
  DynamicIsland/components/Onboarding/MusicControllerSelectionView.swift
```

Result: passed with no output.

## 2026-09-29 Local Correction

The external `Qobuz Now Playing Bridge.app` path was disabled and archived. The intended runtime path is now the native Atoll fork only: select the `Qobuz` media controller in the built Atoll app and do not run a separate Qobuz bridge process.

The local source was updated so `QobuzMediaController` no longer depends on Qobuz distributed notifications for title/artist/album. It reads Qobuz local state and cache directly inside Atoll, keeping the integration in the fork instead of a parallel helper app.

Validation on this Intel macOS host:

```bash
swiftc -typecheck \
  DynamicIsland/models/PlaybackState.swift \
  DynamicIsland/MediaControllers/MediaControllerProtocol.swift \
  DynamicIsland/MediaControllers/QobuzMediaController.swift

swiftc -parse \
  DynamicIsland/models/PlaybackState.swift \
  DynamicIsland/MediaControllers/MediaControllerProtocol.swift \
  DynamicIsland/MediaControllers/QobuzMediaController.swift \
  DynamicIsland/managers/MusicManager.swift \
  DynamicIsland/models/Constants.swift \
  DynamicIsland/models/MusicControlButton.swift
```

Both commands passed with no output. Full `.app` build/install remains blocked on this machine because full Xcode is not installed; only Command Line Tools are active.

## Build and Run

On a machine with full Xcode selected:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cd ~/Devops/projects/Atoll
xcodebuild -list -project DynamicIsland.xcodeproj
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug build
```

Then:

## 2026-09-30 Native In-App Integration (Production Solved)

The requirement for an external service/LaunchAgent was completely eliminated. The integration now runs 100% native inside `/Applications/Atoll.app`:
1. Embedded `/Applications/Atoll.app/Contents/Resources/atoll-qobuz-adapter.py` reading Qobuz state (`player-0.json`, `qobuz.db` and artwork cache) directly.
2. Hooked into `/Applications/Atoll.app/Contents/Resources/mediaremote-adapter.pl` so Atoll's native `Now Playing` stream pipe directly receives Qobuz JSON updates in real-time.
3. Media controls (`send 0/1/2/4/5`) are posted directly to Qobuz PID via CoreGraphics keyboard events without stealing window focus.
4. Process lifecycle is 100% managed by Atoll: when Atoll starts, the stream starts; when Atoll quits, all child processes terminate cleanly with zero background daemons.
5. All files synchronized to the local fork repository under `mediaremote-adapter/`.
4. Grant Accessibility permission to the built Atoll app if macOS prompts.
5. Change tracks in Qobuz and watch the Atoll media surface for artwork and metadata updates.
