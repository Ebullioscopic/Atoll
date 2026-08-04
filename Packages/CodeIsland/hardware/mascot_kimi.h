#pragma once
#include "mascot_common.h"

// Kimi — Blue rounded cube with antenna
#define KIM_BODY    RGB565(74, 144, 255)
#define KIM_DARK    RGB565(51, 107, 230)
#define KIM_LIGHT   RGB565(107, 174, 255)
#define KIM_EYE     0xFFFF
#define KIM_ALERT   RGB565(255, 61, 0)
#define KIM_KB_BASE RGB565(46, 61, 87)
#define KIM_KB_KEY  RGB565(97, 128, 163)
#define KIM_KB_HI   0xFFFF

static void drawKimiBody(float dy, float scale = 1.0f) {
  float cx = 7.5f, cy = 9.0f;
  float w = 9.0f * scale, h = 7.0f * scale;
  float x = cx - w / 2.0f;
  float y = cy - h / 2.0f;
  gfx->fillRoundRect(sx(x), sy(y, dy), sw(w), sh(h), sw(2.0f * scale), KIM_BODY);
  gfx->fillRoundRect(sx(x + 0.8f), sy(y + 0.5f, dy), sw(w - 1.6f), sh(1.3f * scale), sw(1.0f), KIM_LIGHT);
  gfx->fillRoundRect(sx(x + 0.8f), sy(y + h - 1.3f, dy), sw(w - 1.6f), sh(1.0f * scale), sw(1.0f), KIM_DARK);
  // Antenna
  gfx->fillRect(sx(cx - 0.5f), sy(y - 2.5f, dy), sw(1), sh(2.5f), KIM_DARK);
  gfx->fillRect(sx(cx - 1.0f), sy(y - 3.5f, dy), sw(2), sh(1.5f), KIM_LIGHT);
}

void kimiSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5), sy(13.5f, fl * 0.3f), sw(1), sh(2), dim565(KIM_DARK, 0.7f));
  gfx->fillRect(sx(9), sy(13.5f, fl * 0.3f), sw(1), sh(2), dim565(KIM_DARK, 0.7f));
  drawKimiBody(fl, 0.9f);
  float blinkPhase = fmodf(t, 4.0f);
  float eyeH = fmaxf(0.3f, 1.8f * ((blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f));
  float eyeY = 8.5f + (1.8f - eyeH) / 2.0f;
  gfx->fillRect(sx(5.0f), sy(eyeY, fl), sw(1.3f), sh(eyeH), KIM_EYE);
  gfx->fillRect(sx(8.7f), sy(eyeY, fl), sw(1.3f), sh(eyeH), KIM_EYE);
  drawZParticles(t);
}

void kimiWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5), sy(13.5f, bounce * 0.3f), sw(1), sh(2), dim565(KIM_DARK, 0.7f));
  gfx->fillRect(sx(9), sy(13.5f, bounce * 0.3f), sw(1), sh(2), dim565(KIM_DARK, 0.7f));
  drawKeyboard(t, KIM_KB_BASE, KIM_KB_KEY, KIM_KB_HI);
  drawKimiBody(bounce, 1.0f);
  float blinkPhase = fmodf(t, 2.5f);
  float eyeH = (blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.8f;
  gfx->fillRect(sx(5.0f), sy(8.5f + (1.8f - eyeH)/2.0f, bounce), sw(1.3f), sh(eyeH), KIM_EYE);
  gfx->fillRect(sx(8.7f), sy(8.5f + (1.8f - eyeH)/2.0f, bounce), sw(1.3f), sh(eyeH), KIM_EYE);
}

void kimiAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float pulse = (pct > 0.03f && pct < 0.55f) ? 1.0f + sinf(pct * 20.0f) * 0.15f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5), sy(13.5f, jumpY * 0.3f), sw(1), sh(2), dim565(KIM_DARK, 0.7f));
  gfx->fillRect(sx(9), sy(13.5f, jumpY * 0.3f), sw(1), sh(2), dim565(KIM_DARK, 0.7f));
  setViewportShiftX(shakeX);
  drawKimiBody(jumpY, pulse);
  float eyeH2 = 1.8f * ((pct > 0.03f && pct < 0.15f) ? 1.3f : 1.0f);
  gfx->fillRect(sx(5.0f), sy(8.5f + (1.8f - eyeH2)/2.0f, jumpY), sw(1.3f), sh(eyeH2), KIM_EYE);
  gfx->fillRect(sx(8.7f), sy(8.5f + (1.8f - eyeH2)/2.0f, jumpY), sw(1.3f), sh(eyeH2), KIM_EYE);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, KIM_ALERT);
}

void kimiQuestion(float t) {
  _questionMode = true;
  kimiAlert(t);
  _questionMode = false;
}
