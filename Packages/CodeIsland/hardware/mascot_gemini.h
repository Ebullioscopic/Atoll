#pragma once
#include "mascot_common.h"

// Gemini — Four-pointed sparkle star with gradient
#define GEM_BLUE    RGB565(71, 150, 228)
#define GEM_PURPLE  RGB565(132, 122, 206)
#define GEM_ROSE    RGB565(195, 103, 127)
#define GEM_EYE     0xFFFF
#define GEM_ALERT   RGB565(255, 61, 0)
#define GEM_KB_BASE RGB565(56, 64, 96)
#define GEM_KB_KEY  RGB565(102, 112, 148)
#define GEM_KB_HI   0xFFFF

static void drawGemStar(float cx, float cy, float dy, float scale, float rotateDeg = 0.0f) {
  float outerR = 4.5f * scale;
  float innerR = 1.8f * scale;
  float rot = rotateDeg * PI / 180.0f;
  float vx[8], vy[8];
  for (int i = 0; i < 8; i++) {
    float a = i * PI / 4.0f - PI / 2.0f + rot;
    float r = (i % 2 == 0) ? outerR : innerR;
    vx[i] = cx + cosf(a) * r;
    vy[i] = cy + sinf(a) * r;
  }
  uint16_t cols[8] = { GEM_BLUE, GEM_BLUE, GEM_PURPLE, GEM_PURPLE, GEM_PURPLE, GEM_ROSE, GEM_ROSE, GEM_BLUE };
  for (int i = 0; i < 8; i++) {
    int j = (i + 1) % 8;
    gfx->fillTriangle(sx(cx), sy(cy, dy), sx(vx[i]), sy(vy[i], dy), sx(vx[j]), sy(vy[j], dy), cols[i]);
  }
}

static void drawGemFace(float dy, float eyeScale = 1.0f, float blink = 1.0f, uint16_t col = GEM_EYE) {
  float eyeH = fmaxf(0.3f, 1.5f * eyeScale * blink);
  float eyeY = 9.5f + (1.5f - eyeH) / 2.0f;
  gfx->fillRect(sx(5.5f), sy(eyeY, dy), sw(1.2f), sh(eyeH), col);
  gfx->fillRect(sx(8.3f), sy(eyeY, dy), sw(1.2f), sh(eyeH), col);
}

void geminiSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float phase = fmodf(t, 4.0f) / 4.0f;
  float fl = sinf(phase * 2.0f * PI) * 0.8f;
  float spin = sinf(phase * 2.0f * PI) * 5.0f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(GEM_PURPLE, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(GEM_PURPLE, 0.7f));
  drawGemStar(7.5f, 10.0f, fl, 0.9f, spin);
  float blinkPhase = fmodf(t, 4.0f);
  float blink = (blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f;
  drawGemFace(fl, 1.0f, blink);
  drawZParticles(t);
}

void geminiWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  float spin = sinf(t * 2.0f * PI / 1.2f) * 15.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(GEM_PURPLE, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(GEM_PURPLE, 0.7f));
  drawKeyboard(t, GEM_KB_BASE, GEM_KB_KEY, GEM_KB_HI);
  drawGemStar(7.5f, 10.0f, bounce, 1.0f, spin);
  float blinkPhase = fmodf(t, 2.5f);
  float blink = (blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.0f;
  drawGemFace(bounce, 1.0f, blink);
}

void geminiAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float pulse = (pct > 0.03f && pct < 0.55f) ? 1.0f + sinf(pct * 20.0f) * 0.15f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(GEM_PURPLE, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(GEM_PURPLE, 0.7f));
  setViewportShiftX(shakeX);
  drawGemStar(7.5f, 10.0f, jumpY, pulse);
  drawGemFace(jumpY, pct > 0.03f && pct < 0.15f ? 1.3f : 1.0f);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, GEM_ALERT);
}

void geminiQuestion(float t) {
  _questionMode = true;
  geminiAlert(t);
  _questionMode = false;
}
