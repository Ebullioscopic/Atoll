# ESP32-C6-LCD-1.47 硬件基础信息

本文件用于沉淀当前项目的开发板基础配置，避免重复检索。

## 1) 开发板信息

- 板型：`Waveshare ESP32-C6-LCD-1.47`
- 主控：`ESP32-C6FH4`
- 无线：`2.4GHz Wi-Fi 6` + `BLE 5`
- 存储：`4MB Flash`
- 屏幕：`1.47" TFT`，`172x320`，驱动 `ST7789`
- 其他：板载 `Micro SD`、`RGB LED`、`BOOT`、`RESET`

## 2) 已验证可用的 LCD 引脚（板载固定）

- `MOSI = GPIO6`
- `SCLK = GPIO7`
- `CS   = GPIO14`
- `DC   = GPIO15`
- `RST  = GPIO21`
- `BL   = GPIO22`（背光）

> 说明：这些是板载屏幕连接，通常不建议改动。

## 3) 当前项目按钮定义（业务按键，外接）

- `BTN_UP  = GPIO9`（按下计数 +1）
- `BTN_CLR = GPIO23`（按下清零）
- 连接方式：按钮一端接 GPIO，另一端接 GND，代码使用 `INPUT_PULLUP`

## 4) Arduino 环境要点

### 必装库

- `Adafruit GFX Library`
- `Adafruit ST7735 and ST7789 Library`

### 开发板设置建议

- 开发板：`ESP32C6 Dev Module`
- `USB CDC On Boot = Enabled`（若串口异常可优先检查）

### 上传模式提示

若出现无法进入下载：

1. 按住 `BOOT`
2. 点按 `RESET`
3. 松开 `BOOT`
4. 再执行上传

## 5) 屏幕点亮关键点（本项目已踩坑）

使用 Adafruit ST7789 时，要显式绑定 SPI 引脚：

```cpp
SPI.begin(TFT_SCLK, -1, TFT_MOSI, TFT_CS);
tft.init(172, 320);
```

背光极性可能因板子/代码不同而不同，可用开关参数快速切换：

```cpp
constexpr bool BACKLIGHT_ACTIVE_HIGH = true; // 不亮可改 false
digitalWrite(TFT_BL, BACKLIGHT_ACTIVE_HIGH ? HIGH : LOW);
```

## 6) 最小自检顺序（推荐每次新工程先跑）

1. 初始化串口 `Serial.begin(115200)`
2. 打开背光 GPIO
3. `SPI.begin(...)` 绑定屏幕引脚
4. `tft.init(172, 320)`
5. 连续刷 `红/绿/蓝` 三色确认显示链路正常
6. 再进入业务 UI

## 7) 参考资料（下次可直接打开）

- Waveshare Wiki: <https://www.waveshare.com/wiki/ESP32-C6-LCD-1.47?Amazon=>
- Waveshare 产品页: <https://www.waveshare.com/product/iot-communication/esp32-c6-lcd-1.47.htm>
- Spotpear Wiki 镜像: <https://spotpear.com/wiki/ESP32-C6-1.47-inch-LCD-Display-Screen-LVGL-SD-WIFI6-ST7789.html>

---

最后更新：2026-04-22
