#pragma once
#include "mascot_common.h"

// Dex (Codex) — Cloud blob with terminal prompt face
#define DEX_BODY    RGB565(235, 235, 237)
#define DEX_LEG     RGB565(178, 178, 184)
#define DEX_PROMPT  0x0000
#define DEX_ALERT   RGB565(255, 140, 0)
#define DEX_KB_BASE RGB565(46, 46, 51)
#define DEX_KB_KEY  RGB565(102, 102, 107)
#define DEX_KB_HI   0xFFFF
#define DEX_PROMPT_DIM RGB565(70, 70, 72)

static void drawDexBody(float dy, float squashX = 1.0f, float squashY = 1.0f) {
  float cx = 7.5f;
  auto rx = [&](float x) { return cx + (x - cx) * squashX; };
  auto rw = [&](float w) { return w * squashX; };
  auto ry = [&](float y) { return y * squashY + (1.0f - squashY) * 10.0f; };
  // Cloud shape: detailed pixel rows matching Swift
  gfx->fillRect(sx(rx(4)), sy(ry(14), dy), sw(rw(7)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(3)), sy(ry(13), dy), sw(rw(9)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(2)), sy(ry(12), dy), sw(rw(11)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(11), dy), sw(rw(13)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(10), dy), sw(rw(13)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(9), dy), sw(rw(13)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(2)), sy(ry(8), dy), sw(rw(11)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(2)), sy(ry(7), dy), sw(rw(11)), sh(1 * squashY), DEX_BODY);
  // Top bumps
  gfx->fillRect(sx(rx(3)), sy(ry(6), dy), sw(rw(3)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(6)), sy(ry(6), dy), sw(rw(3)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(9)), sy(ry(6), dy), sw(rw(3)), sh(1 * squashY), DEX_BODY);
  // Sub-bumps
  gfx->fillRect(sx(rx(4)), sy(ry(5), dy), sw(rw(2)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(6.5f)), sy(ry(5), dy), sw(rw(2)), sh(1 * squashY), DEX_BODY);
  gfx->fillRect(sx(rx(9)), sy(ry(5), dy), sw(rw(2)), sh(1 * squashY), DEX_BODY);
}

static void drawDexPrompt(float dy, uint16_t color, bool cursorOn) {
  gfx->fillRect(sx(3), sy(10, dy), sw(1), sh(1), color);
  gfx->fillRect(sx(4), sy(11, dy), sw(1), sh(1), color);
  gfx->fillRect(sx(3), sy(12, dy), sw(1), sh(1), color);
  if (cursorOn) gfx->fillRect(sx(6), sy(12, dy), sw(3), sh(1), color);
}

void dexSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float phase = fmodf(t, 4.0f) / 4.0f;
  float fl = sinf(phase * 2.0f * PI) * 0.8f;
  drawShadow(7.0f + fabsf(fl) * 0.3f);
  gfx->fillRect(sx(5), sy(14.5f), sw(1), sh(1.5f), DEX_LEG);
  gfx->fillRect(sx(9), sy(14.5f), sw(1), sh(1.5f), DEX_LEG);
  drawDexBody(fl);
  // Dim cursor bar only (mouth closed)
  float blinkPhase = fmodf(t, 1.2f);
  if (blinkPhase < 0.6f)
    gfx->fillRect(sx(6), sy(12, fl), sw(3), sh(1), DEX_PROMPT_DIM);
  drawZParticles(t);
}

void dexWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(8.0f, bounce, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(5), sy(14.5f), sw(1), sh(1.5f), DEX_LEG);
  gfx->fillRect(sx(9), sy(14.5f), sw(1), sh(1.5f), DEX_LEG);
  drawKeyboard(t, DEX_KB_BASE, DEX_KB_KEY, DEX_KB_HI);
  drawDexBody(bounce);
  float blinkPhase = fmodf(t, 0.3f);
  drawDexPrompt(bounce, DEX_PROMPT, blinkPhase < 0.15f);
}

void dexAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float squashX = jumpY > 0.5f ? 1.0f + jumpY * 0.03f : 1.0f;
  float squashY = jumpY > 0.5f ? 1.0f - jumpY * 0.02f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(8.0f, jumpY, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(5), sy(14.5f), sw(1), sh(1.5f), DEX_LEG);
  gfx->fillRect(sx(9), sy(14.5f), sw(1), sh(1.5f), DEX_LEG);
  setViewportShiftX(shakeX);
  drawDexBody(jumpY, squashX, squashY);
  bool flash = (pct > 0.03f && pct < 0.55f && sinf(pct * 25.0f) > 0.0f);
  uint16_t promptCol = flash ? DEX_ALERT : DEX_PROMPT;
  drawDexPrompt(jumpY, promptCol, true);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, DEX_ALERT);
}

void dexQuestion(float t) {
  _questionMode = true;
  dexAlert(t);
  _questionMode = false;
}
