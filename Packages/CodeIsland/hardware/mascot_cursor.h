#pragma once
#include "mascot_common.h"

// Cursor — Hexagonal gem with diagonal highlight
#define CUR_DARK    RGB565(20, 18, 11)
#define CUR_MID     RGB565(38, 37, 30)
#define CUR_LIGHT   RGB565(237, 236, 236)
#define CUR_EDGE    RGB565(77, 71, 61)
#define CUR_ALERT   RGB565(255, 61, 0)
#define CUR_KB_BASE RGB565(30, 28, 20)
#define CUR_KB_KEY  RGB565(77, 71, 61)
#define CUR_KB_HI   RGB565(237, 236, 236)

static void drawCursorHex(float cx, float cy, float dy, float shimmer = 0.0f) {
  float rx = 5.0f, ry = 4.5f;
  int xTop = sx(cx),       yTop = sy(cy - ry, dy);
  int xTR  = sx(cx + rx),  yTR  = sy(cy - ry * 0.45f, dy);
  int xBR  = sx(cx + rx),  yBR  = sy(cy + ry * 0.45f, dy);
  int xBot = sx(cx),       yBot = sy(cy + ry, dy);
  int xBL  = sx(cx - rx),  yBL  = sy(cy + ry * 0.45f, dy);
  int xTL  = sx(cx - rx),  yTL  = sy(cy - ry * 0.45f, dy);
  int xC   = sx(cx),       yC   = sy(cy, dy);
  gfx->fillTriangle(xTL, yTL, xTop, yTop, xC, yC, CUR_DARK);
  gfx->fillTriangle(xTL, yTL, xC, yC, xBL, yBL, CUR_DARK);
  gfx->fillTriangle(xTop, yTop, xTR, yTR, xBR, yBR, CUR_MID);
  gfx->fillTriangle(xTop, yTop, xBR, yBR, xC, yC, CUR_MID);
  gfx->fillTriangle(xBL, yBL, xC, yC, xBR, yBR, CUR_EDGE);
  gfx->fillTriangle(xBL, yBL, xBR, yBR, xBot, yBot, CUR_EDGE);
  uint16_t hi = dim565(CUR_LIGHT, 0.70f + shimmer * 0.30f);
  gfx->fillTriangle(sx(cx + 1.0f), sy(cy - ry + 0.5f, dy),
                    sx(cx + rx - 0.5f), sy(cy - ry * 0.45f + 0.3f, dy),
                    sx(cx + 0.5f), sy(cy + 0.5f, dy), hi);
  gfx->drawLine(xTop, yTop, xTR, yTR, dim565(CUR_LIGHT, 0.35f));
  gfx->drawLine(xTR, yTR, xBR, yBR, dim565(CUR_LIGHT, 0.35f));
  gfx->drawLine(xBR, yBR, xBot, yBot, dim565(CUR_LIGHT, 0.35f));
  gfx->drawLine(xBot, yBot, xBL, yBL, dim565(CUR_LIGHT, 0.35f));
  gfx->drawLine(xBL, yBL, xTL, yTL, dim565(CUR_LIGHT, 0.35f));
  gfx->drawLine(xTL, yTL, xTop, yTop, dim565(CUR_LIGHT, 0.35f));
}

void cursorSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float phase = fmodf(t, 4.0f) / 4.0f;
  float fl = sinf(phase * 2.0f * PI) * 0.6f;
  drawShadow(7.0f + fabsf(fl) * 0.2f, 0.0f, 15.5f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14.5f), sw(1), sh(1.5f), CUR_EDGE);
  gfx->fillRect(sx(8.5f), sy(14.5f), sw(1), sh(1.5f), CUR_EDGE);
  drawCursorHex(7.5f, 10.0f, fl);
  gfx->fillRect(sx(4.2f), sy(10.0f, fl), sw(1.3f), sh(0.3f), dim565(CUR_LIGHT, 0.4f));
  gfx->fillRect(sx(6.8f), sy(10.0f, fl), sw(1.3f), sh(0.3f), dim565(CUR_LIGHT, 0.4f));
  drawZParticles(t);
}

void cursorWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  float shimmer = sinf(t * 2.0f * PI / 1.5f) * 0.5f + 0.5f;
  drawShadow(8.0f, bounce, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(5.5f), sy(14.5f), sw(1), sh(1.5f), CUR_EDGE);
  gfx->fillRect(sx(8.5f), sy(14.5f), sw(1), sh(1.5f), CUR_EDGE);
  drawKeyboard(t, CUR_KB_BASE, CUR_KB_KEY, CUR_KB_HI);
  drawCursorHex(7.5f, 10.0f, bounce, shimmer);
  // Eyes with blink
  float blinkPhase = fmodf(t, 3.0f);
  float eyeH = (blinkPhase > 2.6f && blinkPhase < 2.75f) ? 0.1f : 1.3f;
  gfx->fillRect(sx(4.2f), sy(9.5f + (1.3f - eyeH)/2.0f, bounce), sw(1.3f), sh(eyeH), CUR_LIGHT);
  gfx->fillRect(sx(6.8f), sy(9.5f + (1.3f - eyeH)/2.0f, bounce), sw(1.3f), sh(eyeH), CUR_LIGHT);
}

void cursorAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  float shimmer = (pct > 0.03f && pct < 0.55f) ? sinf(pct * 30.0f) * 0.5f + 0.5f : 0.0f;
  drawShadow(8.0f, jumpY, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(5.5f), sy(14.5f), sw(1), sh(1.5f), CUR_EDGE);
  gfx->fillRect(sx(8.5f), sy(14.5f), sw(1), sh(1.5f), CUR_EDGE);
  setViewportShiftX(shakeX);
  drawCursorHex(7.5f, 10.0f, jumpY, shimmer);
  // Eye flash
  bool flash = sinf(pct * 30) > 0;
  uint16_t eyeCol = (pct > 0.03f && pct < 0.55f && flash) ? CUR_ALERT : CUR_LIGHT;
  float eScale = lerpKF(kfEyeSCommon, 6, pct);
  float eyeH2 = 1.3f * eScale;
  gfx->fillRect(sx(4.2f), sy(9.5f + (1.3f - eyeH2)/2.0f, jumpY), sw(1.3f), sh(eyeH2), eyeCol);
  gfx->fillRect(sx(6.8f), sy(9.5f + (1.3f - eyeH2)/2.0f, jumpY), sw(1.3f), sh(eyeH2), eyeCol);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, CUR_ALERT);
}

void cursorQuestion(float t) {
  _questionMode = true;
  cursorAlert(t);
  _questionMode = false;
}
