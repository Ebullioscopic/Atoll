#pragma once
#include "mascot_common.h"

// StepFun — Teal blocky rectangle with step accent
#define STP_BODY    RGB565(46, 191, 179)
#define STP_DARK    RGB565(30, 153, 143)
#define STP_LIGHT   RGB565(76, 222, 209)
#define STP_FACE    0xFFFF
#define STP_ALERT   RGB565(255, 61, 0)
#define STP_KB_BASE RGB565(31, 46, 43)
#define STP_KB_KEY  RGB565(56, 82, 77)
#define STP_KB_HI   0xFFFF

static void drawStepBody(float dy, float squashX = 1.0f, float squashY = 1.0f) {
  float cx = 7.5f;
  float bw = 9.0f * squashX, bh = 7.0f * squashY;
  float bx = cx - bw / 2.0f;
  float by = 7.0f + (7.0f - bh) / 2.0f;
  gfx->fillRect(sx(bx), sy(by, dy), sw(bw), sh(bh), STP_BODY);
  // Step accent blocks (side by side, above body)
  gfx->fillRect(sx(bx + bw - 2.5f * squashX), sy(by - 1.5f * squashY, dy), sw(2.5f * squashX), sh(1.5f * squashY), STP_LIGHT);
  gfx->fillRect(sx(bx + bw - 5.0f * squashX), sy(by - 1.5f * squashY, dy), sw(2.5f * squashX), sh(1.5f * squashY), STP_DARK);
}

void stepfunSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(STP_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(STP_DARK, 0.7f));
  drawStepBody(fl, 1.0f, 0.95f);
  float blinkPhase = fmodf(t, 4.0f);
  float blink = (blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f;
  float eyeH = fmaxf(0.3f, 1.5f * blink);
  float eyeY = 10.0f + (1.5f - eyeH) / 2.0f;
  gfx->fillRect(sx(5.2f), sy(eyeY, fl), sw(1.3f), sh(eyeH), STP_FACE);
  gfx->fillRect(sx(8.5f), sy(eyeY, fl), sw(1.3f), sh(eyeH), STP_FACE);
  drawZParticles(t);
}

void stepfunWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(STP_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(STP_DARK, 0.7f));
  drawKeyboard(t, STP_KB_BASE, STP_KB_KEY, STP_KB_HI);
  drawStepBody(bounce);
  float blinkPhase = fmodf(t, 2.5f);
  float eyeH = fmaxf(0.3f, 1.5f * ((blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.0f));
  gfx->fillRect(sx(5.2f), sy(10.0f + (1.5f - eyeH)/2.0f, bounce), sw(1.3f), sh(eyeH), STP_FACE);
  gfx->fillRect(sx(8.5f), sy(10.0f + (1.5f - eyeH)/2.0f, bounce), sw(1.3f), sh(eyeH), STP_FACE);
}

void stepfunAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(STP_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(STP_DARK, 0.7f));
  setViewportShiftX(shakeX);
  drawStepBody(jumpY);
  float eScale = (pct > 0.03f && pct < 0.15f) ? 1.3f : 1.0f;
  float eyeH = 1.5f * eScale;
  gfx->fillRect(sx(5.2f), sy(10.0f + (1.5f - eyeH)/2.0f, jumpY), sw(1.3f), sh(eyeH), STP_FACE);
  gfx->fillRect(sx(8.5f), sy(10.0f + (1.5f - eyeH)/2.0f, jumpY), sw(1.3f), sh(eyeH), STP_FACE);
  setViewportShiftX(0.0f);
  drawBang(bangOp, 1.0f, jumpY, jumpY, STP_ALERT);
}

void stepfunQuestion(float t) {
  _questionMode = true;
  stepfunAlert(t);
  _questionMode = false;
}
