# Intel Atoll 2.3.3 compatibility installation

The normal source build uses the dedicated `.qobuz` provider. This narrowly guarded tool keeps an already installed Intel 2.3.3 bundle usable on a machine with Command Line Tools but no full Xcode. It does not compile or replace the full app.

The installed legacy selection remains the Amazon Music slot, localized as Qobuz. A 17-byte Qobuz identifier needs a matching Swift string count in the provider initializer; the installer verifies the tested instruction bytes, string location and unused Mach-O header padding. A small signed shim directs the inherited control callbacks into the Qobuz helper only when that selection is active. Spotify retains its native AppleScript controller. The generic Perl adapter in the source tree is never repurposed.

Run from a checkout with `/usr/bin/python3`, `clang` and `swiftc` available:

```sh
python3 tools/qobuz-compatibility/install.py --backup-dir /path/to/new/atoll-backup
```

This installer accepts only `/Applications/Atoll.app`, bundle `com.Ebullioscopic.Atoll`, version 2.3.3, on x86_64. A different build fails before mutation. Keep the generated `manifest.json` and saved files. Installation uses ad-hoc signing; it is a local compatibility build, not a notarized distribution. Update or reinstall of Atoll can replace it. Rebuilt native source migrates the marked legacy Qobuz selection to `.qobuz`.

Restore by quitting Atoll, copying back each file marked `existed: true`, removing only files marked `existed: false`, signing the app again, and removing the `atollQobuzLegacyProviderSlot` preference. The installer does that file restoration automatically if its mutation fails. The app's original `Atoll.orig` is untouched.

Play/pause/next/previous use PID-directed Qobuz keyboard events. Shuffle/repeat use the Qobuz accessibility tree and need Accessibility authorization. Seeking and favoriting are unavailable. No launch agent, cron job, bridge publisher, private daemon or package dependency is installed. The single telemetry worker belongs to Atoll and stops on parent exit or selection change; control helpers terminate and are reaped.
