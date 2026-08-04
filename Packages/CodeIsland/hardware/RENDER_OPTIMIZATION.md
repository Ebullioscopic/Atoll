# 屏幕刷新优化笔记 — ESP32-C6-LCD-1.47

## 问题

在 ST7789 172x320 屏幕上做逐帧动画时，每帧先 `fillRect` 清黑再重绘，会产生明显的黑色闪烁（撕裂/黑影）。

根本原因：清屏和重绘是多次独立的 SPI 写操作，屏幕在清屏完成后、重绘完成前的这段时间会显示纯黑帧，人眼可见。

## 解决方案：GFXcanvas16 离屏双缓冲

### 核心思路

所有绘制操作先画到内存中的 `GFXcanvas16` 画布，画完后一次性 `drawRGBBitmap` 推送到屏幕。屏幕永远不会看到"半成品"帧。

### 关键代码

```cpp
// 创建离屏缓冲区（172 × 178 × 2 bytes = ~60KB）
GFXcanvas16 canvas(172, 178);
GFXcanvas16* gfx = &canvas;

// 所有绘制函数中：tft.fillRect → gfx->fillRect
// 所有绘制函数中：tft.setTextColor → gfx->setTextColor
// ...以此类推

// loop() 中：
canvas.fillScreen(COL_BG);     // 清离屏缓冲（不可见）
drawCurrentScene(t);            // 画到缓冲区（不可见）
tft.drawRGBBitmap(0, 0,        // 一次性推送到屏幕
    canvas.getBuffer(), 172, 178);
```

### 内存开销

| 缓冲区尺寸 | 计算 | 内存占用 |
|------------|------|---------|
| 172 × 178 | 172 × 178 × 2 (RGB565) | **61,272 bytes ≈ 60KB** |

ESP32-C6 有 512KB SRAM，60KB 完全可接受。

### 注意事项

1. **只缓冲动画区域**：底部 HUD（文字信息）不需要每帧刷新，直接写 `tft`，只在状态变化时更新
2. **GFXcanvas16 的 API 与 tft 完全一致**：都继承自 `Adafruit_GFX`，替换只需改目标对象
3. **用全局指针 `GFXcanvas16* gfx` 规避 Arduino 的 auto-prototype 问题**：函数签名不出现自定义类型
4. **`drawRGBBitmap` 是单次 SPI 连续写入**：传输 ~60KB 数据，在 SPI 40MHz 下约 12ms，肉眼无感

### 优化前后对比

| | 优化前 | 优化后 |
|--|--------|--------|
| 每帧 SPI 写入 | 清屏 1 次 + N 个 fillRect 分散写入 | 1 次连续 blit |
| 屏幕可见中间状态 | 是（黑帧闪烁） | 否 |
| 内存占用 | ~0 | ~60KB |
| 帧率 | 受闪烁影响观感差 | 流畅无撕裂 |

## 其他可选优化（未采用）

- **脏矩形（dirty rect）**：只重绘变化的区域，减少 SPI 传输量。实现复杂度高，当前 60KB blit 已足够快
- **DMA 传输**：ESP32 支持 SPI DMA，可进一步降低 CPU 占用。Adafruit 库默认已用 DMA（如果底层支持）
- **降低缓冲区分辨率**：缩小到 86×89 再放大 2x，省 3/4 内存，但会损失画质

## 适用场景

此方案适用于任何基于 Adafruit GFX 的小尺寸 TFT 屏幕动画项目，只要 MCU 有足够 RAM 放下一个 RGB565 帧缓冲。

---

最后更新：2025-04-22
