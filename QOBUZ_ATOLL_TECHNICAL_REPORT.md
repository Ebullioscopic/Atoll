# Dedicated Qobuz provider: correction and verification

Updated: 2026-09-30. This report supersedes the earlier claims in this file, including “Production Solved”, globally posted media keys, all-notification observers, newest-cover fallback and generic MediaRemote hooks. The original contribution is commit `969b290` on `feature/qobuz-and-visualizer-fix`.

## Problem and final behavior

With Qobuz selected, browser or messenger media must not replace the notch's track or receive its playback commands. The previous controller posted global media keys; its generic Perl changes could send both a Qobuz command and the regular global command. Its source also referred to nonexistent `PlaybackState.supportsLike/isLiked` fields and omitted `.qobuz` from exhaustive UI/capability switches.

The corrected source uses `QobuzMediaController` exclusively through `.qobuz`. Amazon Music retains its original provider, and Spotify retains `SpotifyController` and its native AppleScript path. The original visualizer/Lottie changes remain in this branch and were not modified by this correction.

## Architecture

```text
Qobuz player-0.json + readonly qobuz.db + current-release artwork
    -> qobuz_engine.py (owned, bounded worker)
    -> JSONLinesPipeHandler
    -> QobuzMediaController playbackStatePublisher
    -> MusicManager -> notch / lock screen

Notch command -> dedicated Qobuz controller -> qobuz_engine.py
    play/pause/next/previous -> CGEventPostToPid(Qobuz PID)
    shuffle/repeat -> signed qobuz_controls -> Qobuz-only AX DOM classes
```

This provider never reads or publishes system Now Playing. The generic `mediaremote-adapter.pl` was restored to its original implementation. Helpers fail within the selected provider; there is no fallback to another app's global media controls.

The reader selects `shuffledItems` when shuffle is active, resolves track/artist/album/duration from SQLite, converts millisecond positions to seconds, and looks up artwork under that release's directory. It never takes the newest unrelated album cover. SQLite connections are explicitly closed. The artwork cache holds only one cover.

Qobuz can persist position samples more than ten seconds apart. The stream refreshes once per second, with the sample's actual timestamp (including microseconds) as the position anchor. Recent local `Playing`/`Stopped` events refine playback state; incompatible timestamps or an old pause from a previous launch are ignored. A stale position sample is conservative. Metadata latency still includes Qobuz's own persistence delay; no universal sub-10-ms update claim is made.

## Lifecycle and resources

Only one telemetry worker belongs to an active controller. It exits on parent death, closed stdout, or provider preference change. There is no LaunchAgent, scheduler, login daemon or global Qobuz publisher in this implementation. Commands are limited to one in flight in the native controller and have a timeout. Advanced helpers are terminated/reaped when their wrapper is terminated.

The controller task owns the pipe handler and captures the controller weakly per update. It does not await an unbounded instance method that would retain the controller. The shared pipe handler remembers its pending continuation, resumes EOF on close, and closes handles. Generic and filtered Now Playing stream tasks received the same lifetime correction. Closing a pipe can no longer leave that read suspended forever.

This is evidence of the tested component lifetimes and bounded ownership, not a claim that every part of Atoll or macOS is free of memory leaks for all future workloads.

## Supported controls and explicit limits

| Control | Result |
|---|---|
| Play/pause | Verified by real clicks in installed Atoll and Qobuz status logs |
| Next | Verified: selected track changed |
| Previous | Verified: Qobuz restarted the current track, matching its normal behavior |
| Shuffle/repeat | Verified through Qobuz-specific Accessibility actions; authorization is required |
| Timeline seeking | Unavailable: background attempts did not move real playback; native source disables interaction |
| Favoriting | Unavailable: no current-track favorite-state contract was validated |

The installed compatibility layer keeps seeking unavailable and never redirects it globally. Full tests with simultaneously playing WhatsApp/Instagram/Telegram media were not performed. Isolation is established by the exclusive data source, identity rejection test and PID/AX command routing; live controls were tested with another app in front.

## Build and persistence

`qobuz_engine.py` is a declared Copy Bundle Resources input. The Xcode helper build phase compiles `qobuz_controls.swift` for the requested architectures, includes it in app Resources and signs it. Real distribution identities use hardened runtime and a secure timestamp; local debug installation uses ad-hoc signing. There are no third-party Python dependencies. This local host already has Command Line Tools and `/usr/bin/python3` available; a distribution without Python must satisfy that runtime prerequisite.

The full app requires Xcode and its existing package dependencies. This Intel host has Command Line Tools only; it did not compile the full GUI target or validate notarization. Existing GitHub CI compiles the target on macOS 15 and 26 and now runs the Qobuz regression checks. Its final result must be read independently of local parse/typecheck results.

For the installed Intel Atoll 2.3.3 bundle, `tools/qobuz-compatibility/install.py` provides a guarded compatibility layer. It checks the exact provider initializer, string location and unused Mach-O header space; fixes the Swift string count from 16 to 17 bytes; loads a small dedicated control shim; installs/signs the helpers and verifies the bundle. Its legacy Amazon-slot marker migrates to native `.qobuz` when the corrected source is built. It does not alter `Atoll.orig`. See that tool's README for rollback and supported version restrictions. App updates can replace this local layer.

## Executed validation

- Eleven Python regressions passed: metadata, shuffle selection, millisecond position, explicit pause, delayed persistence, stale log/session handling, artwork identity, track artist, closed-app idle, SQLite descriptors and parent-exit cleanup.
- Compiled Swift regression passed: Qobuz identity decoding, foreign-source rejection, unsupported seeking capability, weak controller lifetime and child termination.
- Swift typecheck passed for the dedicated controller/protocol/state/transport contract. Edited GUI source parsed successfully; parsing does not prove whole-target compilation.
- Perl syntax, Xcode project parsing, unique object identifiers/resource references and Git whitespace checks passed.
- Installed app displayed real title/artist/artwork. Play/pause/next/previous were clicked in the notch with another app in front. Shuffle/repeat helpers changed Qobuz's state.
- Bundle deep/strict signature verification passed after compatibility installation.
- A broader local test run passed fourteen cases; unrelated `test_replacement_session_invalidates_delayed_cleanup_token` was interrupted after its Swift compilation ran for more than six minutes. It is not reported as passing. The targeted Qobuz checks were rerun successfully after subsequent changes.

## Operational recovery

Keep the installer's backup manifest and its original files. Stop Atoll, restore only paths listed by that manifest, remove only files listed as newly created, re-sign and remove the compatibility migration marker. Source builds use `.qobuz` directly and keep normal provider selection. Do not restart the retired global Qobuz Now Playing bridge to work around an unavailable control.

The private Central-macOS/MiniMax and Memo Coruja records contain the execution-packet lineage, fuller incident chronology, app hashes, final process audit and memory receipts. Secrets, session databases, private screenshots and music artwork are not included in this public contribution.
