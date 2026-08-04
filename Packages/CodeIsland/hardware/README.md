# Buddy — CodeIsland 的硬件桌宠

> 把 macOS 灵动岛上的 AI Coding Agent 状态动画，搬到一颗放在桌上的 ESP32 小屏幕上。

Buddy 是 [CodeIsland](https://github.com/wxtsky/CodeIsland) 的硬件外设功能。Mac 上运行的 CodeIsland 通过蓝牙低功耗（BLE）把当前 AI Coding Agent（Claude / Codex / Gemini / Cursor / Copilot / Trae / Qoder / Factory / CodeBuddy / OpenCode / Kimi / …）的工作状态实时推送给 ESP32，ESP32 在 1.47 寸彩屏上播放对应的像素吉祥物动画：

- **空闲（idle）→ Sleep 场景**：吉祥物闭眼休眠
- **处理中（processing / running）→ Work 场景**：吉祥物在敲代码
- **等待批准（waitApproval）→ Alert 场景**：吉祥物呼叫你
- **等待回答（waitQuestion）→ Question 场景**：吉祥物提示你打开问题

未连接 BLE 时，Buddy 会显示引导页（含项目 GitHub 二维码与设备名）；长按按键即可切到 Demo 模式，自动轮播全部 16 只吉祥物。

---

## 0. 前提

在上手 Buddy 桌宠之前，你需要有充足的动手能力（上手过程会比较坎坷）和基本的 AI 使用能力（便于辅助排查问题）。

## 1. 准备硬件

Buddy 目前只适配下面这一款开发板，零售价约 60 CNY，淘宝上的第三方仿品同样可用。

| 项目 | 型号 / 参数 |
| --- | --- |
| 开发板 | **Waveshare ESP32-C6-LCD-1.47**（微雪电子） |
| 主控 | ESP32-C6FH4（RISC-V 单核，160 MHz，4 MB Flash） |
| 屏幕 | 1.47 寸 IPS，172×320，ST7789 驱动 |
| 无线 | Wi-Fi 6 + BLE 5（本项目使用 BLE） |

**购买参考（非赞助）：**

- 微雪官方：搜索关键字 `ESP32-C6-LCD-1.47`
  - 产品页：<https://www.waveshare.com/product/iot-communication/esp32-c6-lcd-1.47.htm>
  - Wiki：<https://www.waveshare.com/wiki/ESP32-C6-LCD-1.47>

> **关于按钮**：板上的 `BOOT` 键已被复用为业务按键（GPIO9），无需外接按钮——短按切换吉祥物、长按切换 Demo 模式。

更多板子细节见 [HARDWARE_NOTES.md](HARDWARE_NOTES.md)。

---

## 2. 拉取代码

```bash
git clone https://github.com/wxtsky/CodeIsland.git
cd CodeIsland/hardware
```

`hardware/` 目录关键文件：

- [hardware.ino](hardware.ino) — 主程序入口（Arduino sketch）
- `mascot_*.h` — 16 只吉祥物的像素动画绘制函数
- [HARDWARE_NOTES.md](HARDWARE_NOTES.md) — 板子引脚 / 上传踩坑笔记
- [RENDER_OPTIMIZATION.md](RENDER_OPTIMIZATION.md) — 双缓冲渲染优化笔记

---

## 3. 安装 Arduino IDE

到 <https://www.arduino.cc/en/software> 下载 **Arduino IDE 2.x**（macOS Universal 安装包），双击安装即可。

> 偏好 PlatformIO / arduino-cli 的同学可以照搬下方依赖清单，本指南以官方 IDE 2.x 为准。

---

## 4. 添加 ESP32 开发板支持

ESP32-C6 需要 **Arduino-ESP32 v3.0 或更高**。

1. 打开 **Arduino IDE → Settings…**（快捷键 `⌘,`）。
2. 在 **Additional boards manager URLs** 里添加（已有其它链接时用逗号分隔）：

   ```
   https://espressif.github.io/arduino-esp32/package_esp32_index.json
   ```

3. 打开 **Tools → Board → Boards Manager…**，搜索 `esp32`，安装 **"esp32 by Espressif Systems"**（≥ 3.0.0）。
4. 安装完成后，**Tools → Board → esp32** 列表里应能看到 `ESP32C6 Dev Module`。

---

## 5. 安装依赖库

打开 **Sketch → Include Library → Manage Libraries…**，分别搜索并安装：

| 库名 | 作者 | 用途 |
| --- | --- | --- |
| `Adafruit GFX Library` | Adafruit | 2D 图形基础库 |
| `Adafruit ST7735 and ST7789 Library` | Adafruit | ST7789 屏幕驱动 |
| `Adafruit BusIO` | Adafruit | 前两者的依赖（IDE 通常会自动提示一起装） |

> **BLE 库无需单独安装**：`BLEDevice` / `BLEServer` / `BLE2902` 已由 Arduino-ESP32 开发板包内置提供。

安装完毕后建议重启一次 IDE。

---

## 6. 打开工程

1. 在 Arduino IDE 中点击 **File → Open…**，选择 `CodeIsland/hardware/hardware.ino`。
2. 若 IDE 弹出 "this sketch needs to be inside a folder named hardware" 的提示，直接确认/忽略即可——文件本身就在 `hardware/` 目录里。
3. 打开后侧栏应能看到 `hardware.ino` 以及全部 `mascot_*.h` 头文件。

---

## 7. 配置开发板参数

用 USB-C 数据线把 ESP32-C6 接到 Mac，然后在 **Tools** 菜单里设置：

| 选项 | 推荐值 |
| --- | --- |
| Board | **ESP32C6 Dev Module** |
| USB CDC On Boot | **Enabled**（必须，否则串口不工作） |
| CPU Frequency | 160 MHz |
| Flash Size | 4 MB (32 Mb) |
| Partition Scheme | **Huge APP (3MB No OTA/1MB SPIFFS)** |
| Upload Speed | 921600（失败时降到 460800） |
| Port | `/dev/cu.usbmodem*` |

> **关于分区方案与 OTA**：选择 "Huge APP (3MB No OTA)" 是因为固件体积较大，需要完整的 3MB APP 分区。固件中的 `ArduinoOTA` 功能是实验性的 WiFi network OTA，通过单分区直接覆写实现（非 ESP32 原生双分区 OTA），仅在通过 BLE 下发 WiFi 凭据后才会激活。生产环境建议仍通过 USB 烧录。

> 在 Port 列表里看不到 `/dev/cu.usbmodem*`？大概率是数据线只能充电。ESP32-C6 走原生 USB，macOS 免驱，换一根能传数据的线即可。

---

## 8. 烧录固件

1. 点击工具栏 **✓ Verify** 编译，首次编译耗时较长，请耐心等待。
2. 编译通过后点击 **→ Upload**。
3. 若上传卡在 `Connecting...`，按以下顺序手动进入下载模式：
   1. 按住板上的 **BOOT** 键
   2. 点按一下 **RESET** 键
   3. 松开 **BOOT** 键
   4. 立即重新点 **Upload**
4. 上传完成后开发板会自动复位，显示引导页（含 GitHub 二维码与设备名 `Buddy-XXXXXX`）。

---

## 9. 与 macOS 端 CodeIsland 配对

1. 启动 [CodeIsland](https://github.com/wxtsky/CodeIsland) 主程序（需为支持 ESP32 桥接的版本）。
2. 打开 **Preferences → ESP32 / Buddy** 面板，启用桥接开关。
3. 首次连接时 macOS 会请求蓝牙权限，授权后等待扫描到 `Buddy-XXXXXX`，点击连接。
4. Buddy 屏幕出现 `Pair?` 后，短按 **BOOT** 确认配对；如果不想配对，长按 **BOOT** 拒绝。
5. 触发任意 AI Coding Agent（例如让 Claude Code 跑一条命令），Buddy 屏幕会立即切到对应吉祥物的 **Work** 场景。
6. 在 macOS 端可远程调节屏幕亮度（10%–100%）与翻转方向（朝上 / 朝下），无需重新烧录。

> 一直扫不到设备？请到 **系统设置 → 隐私与安全性 → 蓝牙** 确认 CodeIsland 已被授权，然后关掉再打开 Buddy 桥接开关重新触发扫描。

---

## 10. 按键说明

| 操作 | 行为 |
| --- | --- |
| 短按 BOOT | 切换到下一只吉祥物（Onboard / Demo 模式生效；BLE 已连上时由 Mac 决定显示哪只） |
| 长按 ≥ 0.6 秒 | 切换 Demo 模式（自动轮播全部吉祥物） |
| 配对页短按 BOOT | 确认当前 Mac 的配对请求 |
| 配对页长按 BOOT | 拒绝当前 Mac 的配对请求 |

---

## 11. 串口调试

- 波特率：`115200`
- 启动时打印：开发板信息、BLE 设备名（`Buddy-XXXXXX`）
- 此后每隔 ~2 秒打印一次：当前吉祥物 / 场景 / FPS / BLE 状态，便于排查问题

---

## 12. FAQ

Buddy 基于 Arduino 平台开发，上手门槛非常低；遇到问题时建议直接交给 AI 辅助排查。

---

## 许可证

与主仓库一致，见根目录 [LICENSE](../LICENSE)。

Have fun & happy hacking — 让你的桌面也拥有一只 Buddy 🐾
