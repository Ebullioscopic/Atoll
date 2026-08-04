#pragma once
#include "mascot_common.h"

// AntiGravity — Rainbow gradient "A" triangle
#define AG_BLUE   RGB565(77, 127, 242)
#define AG_PURPLE RGB565(153, 89, 230)
#define AG_PINK   RGB565(230, 102, 140)
#define AG_ORANGE RGB565(242, 153, 77)
#define AG_FACE   0xFFFF
#define AG_ALERT  RGB565(255, 61, 0)
#define AG_KB_BASE RGB565(46, 41, 64)
#define AG_KB_KEY  RGB565(82, 72, 102)
#define AG_KB_HI   0xFFFF

static void drawAGBody(float dy, float scale = 1.0f) {
  // "A" triangle: gradient approximated with horizontal slices
  float cx = 7.5f, topY = 10.0f - 6.0f * scale, botY = 10.0f + 6.0f * 0.3f * scale;
  float halfW = 5.0f * scale;
  uint16_t colors[] = { AG_BLUE, AG_BLUE, AG_PURPLE, AG_PURPLE, AG_PINK, AG_PINK, AG_ORANGE, AG_ORANGE };
  int slices = 8;
  for (int i = 0; i < slices; i++) {
    float frac = (float)i / slices;
    float y = topY + frac * (botY - topY);
    float w = fmaxf(1.0f, halfW * frac * 2.0f);
    if (w < 1.0f) w = 1.0f;
    gfx->fillRect(sx(cx - w / 2), sy(y, dy), sw(w), sh((botY - topY) / slices + 0.1f), colors[i]);
  }
}

void antigravSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(AG_PURPLE, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(AG_PINK, 0.7f));
  drawAGBody(fl, 0.9f);
  float blinkPhase = fmodf(t, 4.0f);
  float eyeH = fmaxf(0.3f, 1.5f * ((blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f));
  float eyeY = 9.0f + (1.5f - eyeH) / 2.0f;
  gfx->fillRect(sx(5.5f), sy(eyeY, fl), sw(1.2f), sh(eyeH), AG_FACE);
  gfx->fillRect(sx(8.3f), sy(eyeY, fl), sw(1.2f), sh(eyeH), AG_FACE);
  drawZParticles(t);
}

void antigravWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(AG_PURPLE, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(AG_PINK, 0.7f));
  drawKeyboard(t, AG_KB_BASE, AG_KB_KEY, AG_KB_HI);
  drawAGBody(bounce);
  float blinkPhase = fmodf(t, 2.5f);
  float eyeH = fmaxf(0.3f, 1.5f * ((blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.0f));
  float eyeY = 9.0f + (1.5f - eyeH) / 2.0f;
  gfx->fillRect(sx(5.5f), sy(eyeY, bounce), sw(1.2f), sh(eyeH), AG_FACE);
  gfx->fillRect(sx(8.3f), sy(eyeY, bounce), sw(1.2f), sh(eyeH), AG_FACE);
}

void antigravAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(AG_PURPLE, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(AG_PINK, 0.7f));
  setViewportShiftX(shakeX);
  drawAGBody(jumpY);
  float eScale = (pct > 0.03f && pct < 0.15f) ? 1.3f : 1.0f;
  float eyeH = 1.5f * eScale;
  float eyeY = 9.0f + (1.5f - eyeH) / 2.0f;
  gfx->fillRect(sx(5.5f), sy(eyeY, jumpY), sw(1.2f), sh(eyeH), AG_FACE);
  gfx->fillRect(sx(8.3f), sy(eyeY, jumpY), sw(1.2f), sh(eyeH), AG_FACE);
  setViewportShiftX(0.0f);
  drawBang(bangOp, 1.0f, jumpY, jumpY, AG_ALERT);
}

void antigravQuestion(float t) {
  _questionMode = true;
  antigravAlert(t);
  _questionMode = false;
}
