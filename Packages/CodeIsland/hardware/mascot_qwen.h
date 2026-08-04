#pragma once
#include "mascot_common.h"

// Qwen — Purple 6-pointed star (hexagram)
#define QWN_BODY    RGB565(124, 58, 237)
#define QWN_LIGHT   RGB565(139, 92, 246)
#define QWN_DARK    RGB565(109, 40, 217)
#define QWN_FACE    0xFFFF
#define QWN_ALERT   RGB565(255, 61, 0)
#define QWN_KB_BASE RGB565(51, 38, 77)
#define QWN_KB_KEY  RGB565(97, 77, 133)
#define QWN_KB_HI   0xFFFF

static void drawQwenStar(float cx, float cy, float dy, float scale, float rotateDeg = 0.0f) {
  float outerR = 4.8f * scale;
  float innerR = 2.5f * scale;
  float rot = rotateDeg * PI / 180.0f;
  float vx[12], vy[12];
  for (int i = 0; i < 12; i++) {
    float a = i * PI / 6.0f - PI / 2.0f + rot;
    float r = (i % 2 == 0) ? outerR : innerR;
    vx[i] = cx + cosf(a) * r;
    vy[i] = cy + sinf(a) * r;
  }
  uint16_t cols[12] = { QWN_LIGHT, QWN_LIGHT, QWN_BODY, QWN_BODY, QWN_DARK, QWN_DARK,
                        QWN_DARK, QWN_BODY, QWN_BODY, QWN_LIGHT, QWN_LIGHT, QWN_BODY };
  for (int i = 0; i < 12; i++) {
    int j = (i + 1) % 12;
    gfx->fillTriangle(sx(cx), sy(cy, dy), sx(vx[i]), sy(vy[i], dy), sx(vx[j]), sy(vy[j], dy), cols[i]);
  }
  float hiR = 2.0f * scale;
  gfx->fillTriangle(
    sx(cx + cosf(-PI / 2.0f + rot + PI / 6.0f) * hiR), sy(cy + sinf(-PI / 2.0f + rot + PI / 6.0f) * hiR, dy),
    sx(cx + cosf(PI * 2.0f / 3.0f - PI / 2.0f + rot + PI / 6.0f) * hiR), sy(cy + sinf(PI * 2.0f / 3.0f - PI / 2.0f + rot + PI / 6.0f) * hiR, dy),
    sx(cx + cosf(PI * 4.0f / 3.0f - PI / 2.0f + rot + PI / 6.0f) * hiR), sy(cy + sinf(PI * 4.0f / 3.0f - PI / 2.0f + rot + PI / 6.0f) * hiR, dy),
    dim565(QWN_LIGHT, 0.35f)
  );
}

static void drawQwenFace(float dy, float eyeScale = 1.0f, float blink = 1.0f) {
  float eyeH = fmaxf(0.3f, 1.5f * eyeScale * blink);
  float eyeY = 9.5f + (1.5f - eyeH) / 2.0f;
  gfx->fillRect(sx(5.5f), sy(eyeY, dy), sw(1.2f), sh(eyeH), QWN_FACE);
  gfx->fillRect(sx(8.3f), sy(eyeY, dy), sw(1.2f), sh(eyeH), QWN_FACE);
}

void qwenSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float phase = fmodf(t, 4.0f) / 4.0f;
  float fl = sinf(phase * 2.0f * PI) * 0.8f;
  float spin = sinf(phase * 2.0f * PI) * 8.0f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(QWN_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(QWN_DARK, 0.7f));
  drawQwenStar(7.5f, 10.0f, fl, 0.9f, spin);
  float blinkPhase = fmodf(t, 4.0f);
  float blink = (blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f;
  drawQwenFace(fl, 1.0f, blink);
  drawZParticles(t);
}

void qwenWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  float spin = sinf(t * 2.0f * PI / 1.2f) * 12.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(QWN_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(QWN_DARK, 0.7f));
  drawKeyboard(t, QWN_KB_BASE, QWN_KB_KEY, QWN_KB_HI);
  drawQwenStar(7.5f, 10.0f, bounce, 1.0f, spin);
  float blinkPhase = fmodf(t, 2.5f);
  float blink = (blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.0f;
  drawQwenFace(bounce, 1.0f, blink);
}

void qwenAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float pulse = (pct > 0.03f && pct < 0.55f) ? 1.0f + sinf(pct * 20.0f) * 0.15f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(QWN_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(QWN_DARK, 0.7f));
  setViewportShiftX(shakeX);
  drawQwenStar(7.5f, 10.0f, jumpY, pulse);
  drawQwenFace(jumpY, pct > 0.03f && pct < 0.15f ? 1.3f : 1.0f);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, QWN_ALERT);
}

void qwenQuestion(float t) {
  _questionMode = true;
  qwenAlert(t);
  _questionMode = false;
}
