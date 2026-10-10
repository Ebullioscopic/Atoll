# Cooling

Enable **Settings > System > Cooling > Enable fan controls** to add the Cooling tab. This is off by default and works independently of the Stats feature. Cooling uses the standard notch panel size, with adaptive fan cards and scrolling for narrow layouts or additional fans. Cooling shows actual fan RPM and the hottest readable temperature, with 30%, 50%, 70%, 100%, and Auto controls for each fan.

Presets use the hardware-reported range: `minimumRPM + (maximumRPM - minimumRPM) * fraction`. For a fan with a 2,317–7,826 RPM range, 50% targets about 5,072 RPM and 100% targets 7,826 RPM. Atoll checks the mode and target after a manual write; actual speed may take longer to settle.

The first command starts a bundled helper through macOS administrator authorization. Commands share the approved connection until Atoll exits, sleeps, or loses that connection. Closing the notch and rejected commands preserve the session. No password is stored and no persistent launch daemon is installed. Authorization cancellation or connection failure requires an explicit Retry connection action rather than repeated automatic prompts.

Turning the feature off closes the helper and returns fans controlled by Atoll to Auto. A command still waiting for authorization is cancelled before it can write. The helper also attempts to restore Auto on disconnect, app exit, a 15-second heartbeat expiry, and high (95°C) or unreadable temperatures. Atoll intentionally falls back to firmware Auto for every manual preset, including 100%, while temperature readings are high or unavailable. Auto and heartbeat commands still succeed during this guard. Firmware-controlled fan-stop behavior is allowed in Auto.

## Hardware validation

Tested on `Mac17,9`, Apple M5 Pro: two fans with a 2,317–7,826 RPM range. The user confirmed speed changes and one password for successive preset commands. Native Swift sensor reads confirmed both fans in manual mode at a 7,826 RPM target, then both in automatic mode after Auto was selected.

Intel and other Apple Silicon models have not been hardware-tested. The helper is built for the same architectures as the app; missing SMC keys or invalid sensor limits produce an unavailable/error state. Forced app failure, sleep, and high-temperature restoration have not been exercised on the physical Mac.

## Development

AppleSMC access uses the native 80-byte host-endian IOKit structure, per-fan `md`/`Md` keys, and `flt ` or `fpe2` RPM encodings. Some firmware requires `Ftst` before manual mode. The helper accepts only the four presets, Auto, heartbeat, and quit over a bounded JSON-line Unix socket. Private directory/socket permissions, peer UID checks, and a random session token authenticate the connection.

Run `sh tests/test_cooling.sh` for SMC value/limit tests and socket/session regression tests. The session fixture has no SMC writes and needs neither fan hardware nor administrator access. Real hardware read-only inspection is available through `Atoll.app/Contents/Helpers/AtollFanHelper --read-only`.

The AppleSMC reference is [raminsharifi/MacFanControl](https://github.com/raminsharifi/MacFanControl) (MIT). Its complete license notice is in `THIRD_PARTY_FAN_CONTROL.md` and is bundled in the app resources.
