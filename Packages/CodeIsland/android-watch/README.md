# CodeIsland Buddy Watch

English | [简体中文](README.zh-CN.md)

Wear OS companion app that mirrors the `hardware/Buddy` protocol used by CodeIsland.

## Features

- Acts as a BLE peripheral named `Buddy`, discoverable from the macOS app
- Mirrors mascot, agent status, tool name, brightness, and orientation frames
- Supports both **square** and **round** watch screens through resource-qualified sizing
- Tap the screen to notify the host with the current mascot `sourceId`
- Long-press to toggle local demo mode until the next live frame arrives

## Protocol Compatibility

This app follows the same contract as `Sources/CodeIslandCore/ESP32Protocol.swift`:

- Service UUID: `0000beef-0000-1000-8000-00805f9b34fb`
- Write char: `0000beef-0001-1000-8000-00805f9b34fb`
- Notify char: `0000beef-0002-1000-8000-00805f9b34fb`
- Agent frame: `sourceId + statusId + toolLen + toolName`
- Brightness frame: `0xFE + percent`
- Orientation frame: `0xFD + orientation`

## Requirements

- Wear OS device with BLE peripheral / advertising support
- Android SDK installed locally
- Java 17

## Build

From the repository root:

```bash
# Build watch debug APK only
./build.sh --watch

# Build macOS app + watch debug APK
./build.sh --with-watch
```

Or directly inside the watch project:

```bash
cd android-watch
./gradlew assembleDebug
./gradlew testDebugUnitTest
```

## Output

- Debug APK: `android-watch/app/build/outputs/apk/debug/app-debug.apk`
- Release APK: `android-watch/app/build/outputs/apk/release/app-release-unsigned.apk`

## Notes

- On first launch, grant Bluetooth and notification permissions on the watch.
- If the device does not support BLE advertising, the app will show an unsupported state instead of silently failing.
