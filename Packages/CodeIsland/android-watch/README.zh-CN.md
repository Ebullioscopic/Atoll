# CodeIsland Buddy Watch

[English](README.md) | 简体中文

这是 CodeIsland 的 Wear OS 手表端实现，兼容仓库中 `hardware/Buddy` 使用的 BLE 协议。

## 功能

- 以 `Buddy` 名称作为 BLE 外设广播，可被 macOS 端扫描与连接
- 同步 mascot、Agent 状态、工具名、亮度与屏幕方向
- 通过资源限定符同时适配 **方形** 与 **圆形** 手表屏幕
- 轻点屏幕向主机回传当前 mascot 的 `sourceId`
- 长按切换本地 demo 模式，收到新的实时帧后自动恢复 Agent 模式

## 协议兼容

该应用与 `Sources/CodeIslandCore/ESP32Protocol.swift` 保持一致：

- Service UUID：`0000beef-0000-1000-8000-00805f9b34fb`
- Write Characteristic：`0000beef-0001-1000-8000-00805f9b34fb`
- Notify Characteristic：`0000beef-0002-1000-8000-00805f9b34fb`
- Agent 帧：`sourceId + statusId + toolLen + toolName`
- 亮度帧：`0xFE + percent`
- 方向帧：`0xFD + orientation`

## 环境要求

- 支持 BLE Peripheral / Advertising 的 Wear OS 设备
- 本地已安装 Android SDK
- Java 17

## 编译

在仓库根目录执行：

```bash
# 仅构建手表 debug APK
./build.sh --watch

# 同时构建 macOS App 与手表 debug APK
./build.sh --with-watch
```

也可以直接进入手表工程：

```bash
cd android-watch
./gradlew assembleDebug
./gradlew testDebugUnitTest
```

## 产物

- Debug APK：`android-watch/app/build/outputs/apk/debug/app-debug.apk`
- Release APK：`android-watch/app/build/outputs/apk/release/app-release-unsigned.apk`

## 说明

- 首次启动请在手表上授予蓝牙与通知权限。
- 若设备不支持 BLE 广播，应用会在界面上明确显示不支持状态，而不是静默失败。
