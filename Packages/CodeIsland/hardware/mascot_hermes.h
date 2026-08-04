#pragma once
#include "mascot_common.h"

// Hermes — Purple hooded figure
#define HRM_BODY    RGB565(122, 88, 176)
#define HRM_DARK    RGB565(97, 66, 148)
#define HRM_HOOD    RGB565(101, 71, 158)
#define HRM_EYE     0xFFFF
#define HRM_ALERT   RGB565(255, 61, 0)
#define HRM_KB_BASE RGB565(31, 21, 48)
#define HRM_KB_KEY  RGB565(61, 46, 87)
#define HRM_KB_HI   RGB565(217, 217, 242)

static void drawHermesBody(float dy, float scale = 1.0f) {
  float cx = 7.5f, cy = 10.5f;
  float bw = 9.0f * scale, bh = 6.0f * scale;
  float x = cx - bw / 2.0f;
  float y = cy - bh / 2.0f + 1.0f;
  gfx->fillRoundRect(sx(x), sy(y, dy), sw(bw), sh(bh), sw(1.5f * scale), HRM_BODY);
  gfx->fillTriangle(
    sx(cx), sy(cy - bh / 2.0f - 3.0f * scale, dy),
    sx(cx - bw / 2.0f - 0.5f), sy(cy - bh / 2.0f + 2.0f, dy),
    sx(cx + bw / 2.0f + 0.5f), sy(cy - bh / 2.0f + 2.0f, dy),
    HRM_HOOD
  );
}

void hermesSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(HRM_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(HRM_DARK, 0.7f));
  drawHermesBody(fl, 0.9f);
  float blinkPhase = fmodf(t, 4.0f);
  float eyeH = fmaxf(0.2f, 1.2f * ((blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f));
  float eyeY = 10.5f + (1.2f - eyeH) / 2.0f;
  gfx->fillRoundRect(sx(5.1f), sy(eyeY, fl), sw(1.8f), sh(eyeH), sw(0.4f), HRM_EYE);
  gfx->fillRoundRect(sx(8.7f), sy(eyeY, fl), sw(1.8f), sh(eyeH), sw(0.4f), HRM_EYE);
  drawZParticles(t, 11.8f, 7.7f, HRM_EYE);
}

void hermesWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(HRM_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(HRM_DARK, 0.7f));
  drawKeyboard(t, HRM_KB_BASE, HRM_KB_KEY, HRM_KB_HI);
  drawHermesBody(bounce);
  float blinkPhase = fmodf(t, 2.5f);
  float eyeH = fmaxf(0.2f, 1.2f * ((blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.0f));
  float eyeY = 10.5f + (1.2f - eyeH) / 2.0f;
  gfx->fillRoundRect(sx(5.1f), sy(eyeY, bounce), sw(1.8f), sh(eyeH), sw(0.4f), HRM_EYE);
  gfx->fillRoundRect(sx(8.7f), sy(eyeY, bounce), sw(1.8f), sh(eyeH), sw(0.4f), HRM_EYE);
}

void hermesAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(HRM_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(HRM_DARK, 0.7f));
  setViewportShiftX(shakeX);
  drawHermesBody(jumpY);
  float eyeH = 1.2f * ((pct > 0.03f && pct < 0.15f) ? 1.3f : 1.0f);
  float eyeY = 10.5f + (1.2f - eyeH) / 2.0f;
  gfx->fillRoundRect(sx(5.1f), sy(eyeY, jumpY), sw(1.8f), sh(eyeH), sw(0.4f), HRM_EYE);
  gfx->fillRoundRect(sx(8.7f), sy(eyeY, jumpY), sw(1.8f), sh(eyeH), sw(0.4f), HRM_EYE);
  setViewportShiftX(0.0f);
  drawBang(bangOp, 1.0f, jumpY, jumpY, HRM_ALERT);
}

void hermesQuestion(float t) {
  _questionMode = true;
  hermesAlert(t);
  _questionMode = false;
}
