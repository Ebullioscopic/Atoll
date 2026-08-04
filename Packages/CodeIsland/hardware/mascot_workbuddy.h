#pragma once
#include "mascot_common.h"

// WorkBuddy — Purple circle body with antenna
#define WB_BODY    RGB565(121, 97, 222)
#define WB_DARK    RGB565(97, 74, 191)
#define WB_LIGHT   RGB565(148, 122, 240)
#define WB_FACE    0xFFFF
#define WB_ALERT   RGB565(255, 61, 0)
#define WB_KB_BASE RGB565(26, 46, 43)
#define WB_KB_KEY  RGB565(46, 82, 74)
#define WB_KB_HI   0xFFFF

static void drawWBBody(float dy, float scale = 1.0f) {
  // Circle body (approximated with stacked rects)
  float cx = 7.5f, cy = 10.5f, r = 4.5f * scale;
  for (int row = 0; row < 9; row++) {
    float frac = (float)row / 8.0f;
    float y = cy - r + frac * r * 2;
    float halfW = sqrtf(r * r - (y - cy) * (y - cy));
    if (halfW < 0.5f) halfW = 0.5f;
    gfx->fillRect(sx(cx - halfW), sy(y, dy), sw(halfW * 2), sh(r * 2 / 9 + 0.1f), WB_BODY);
  }
  // Antenna stem + tip
  gfx->fillRect(sx(7), sy(cy - r - 2.0f, dy), sw(1), sh(2), WB_DARK);
  gfx->fillRect(sx(6.2f), sy(cy - r - 3.2f, dy), sw(2.6f), sh(2), WB_LIGHT);
}

void workbuddySleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(WB_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(WB_DARK, 0.7f));
  drawWBBody(fl, 0.9f);
  float blinkPhase = fmodf(t, 4.0f);
  float eyeH = fmaxf(0.3f, 1.8f * ((blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f));
  float eyeY = 10.0f + (1.8f - eyeH) / 2.0f;
  gfx->fillRect(sx(5), sy(eyeY, fl), sw(1.5f), sh(eyeH), WB_FACE);
  gfx->fillRect(sx(8.5f), sy(eyeY, fl), sw(1.5f), sh(eyeH), WB_FACE);
  drawZParticles(t);
}

void workbuddyWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(WB_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(WB_DARK, 0.7f));
  drawKeyboard(t, WB_KB_BASE, WB_KB_KEY, WB_KB_HI);
  drawWBBody(bounce);
  float blinkPhase = fmodf(t, 2.5f);
  float eyeH = fmaxf(0.3f, 1.8f * ((blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.0f));
  float eyeY = 10.0f + (1.8f - eyeH) / 2.0f;
  gfx->fillRect(sx(5), sy(eyeY, bounce), sw(1.5f), sh(eyeH), WB_FACE);
  gfx->fillRect(sx(8.5f), sy(eyeY, bounce), sw(1.5f), sh(eyeH), WB_FACE);
}

void workbuddyAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(WB_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(WB_DARK, 0.7f));
  setViewportShiftX(shakeX);
  drawWBBody(jumpY);
  float eyeH = fmaxf(0.3f, 1.8f * ((pct > 0.03f && pct < 0.15f) ? 1.3f : 1.0f));
  float eyeY = 10.0f + (1.8f - eyeH) / 2.0f;
  gfx->fillRect(sx(5), sy(eyeY, jumpY), sw(1.5f), sh(eyeH), WB_FACE);
  gfx->fillRect(sx(8.5f), sy(eyeY, jumpY), sw(1.5f), sh(eyeH), WB_FACE);
  setViewportShiftX(0.0f);
  drawBang(bangOp, 1.0f, jumpY, jumpY, WB_ALERT);
}

void workbuddyQuestion(float t) {
  _questionMode = true;
  workbuddyAlert(t);
  _questionMode = false;
}
