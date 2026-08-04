#pragma once
#include "mascot_common.h"

// Trae — Green rounded rectangle with screen
#define TRAE_BODY   RGB565(34, 197, 94)
#define TRAE_DARK   RGB565(16, 143, 81)
#define TRAE_SCREEN RGB565(36, 56, 36)
#define TRAE_EYE    RGB565(34, 197, 94)
#define TRAE_ALERT  RGB565(255, 61, 0)
#define TRAE_KB_BASE RGB565(26, 36, 26)
#define TRAE_KB_KEY  RGB565(51, 77, 51)
#define TRAE_KB_HI   RGB565(34, 197, 94)

static void drawTraeBody(float dy, float squashX = 1.0f, float squashY = 1.0f) {
  float cx = 7.5f;
  float bw = 10.0f * squashX;
  float bh = 7.0f * squashY;
  float bx = cx - bw / 2.0f;
  float by = 7.0f + (7.0f - bh) / 2.0f;
  gfx->fillRoundRect(sx(bx), sy(by, dy), sw(bw), sh(bh), sw(1.5f), TRAE_BODY);
  gfx->fillRoundRect(sx(bx + 1.2f), sy(by + 1.2f, dy), sw(bw - 2.4f), sh(bh - 2.4f), sw(0.8f), TRAE_SCREEN);
}

static void drawTraeFace(float dy, float eyeScale = 1.0f, float blink = 1.0f) {
  float eyeH = fmaxf(0.3f, 1.8f * eyeScale * blink);
  float eyeW = 1.8f * eyeScale;
  float eyeY = 10.0f + (1.8f - eyeH) / 2.0f;
  if (blink > 0.3f) {
    gfx->fillRoundRect(sx(4.5f), sy(eyeY - 0.5f, dy), sw(eyeW + 1.0f), sh(eyeH + 1.0f), sw(0.5f), dim565(TRAE_EYE, 0.2f));
    gfx->fillRoundRect(sx(8.2f), sy(eyeY - 0.5f, dy), sw(eyeW + 1.0f), sh(eyeH + 1.0f), sw(0.5f), dim565(TRAE_EYE, 0.2f));
  }
  gfx->fillRoundRect(sx(5.0f), sy(eyeY, dy), sw(eyeW), sh(eyeH), sw(0.4f), TRAE_EYE);
  gfx->fillRoundRect(sx(8.7f), sy(eyeY, dy), sw(eyeW), sh(eyeH), sw(0.4f), TRAE_EYE);
}

void traeSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(6.0f + fabsf(fl) * 0.3f, 0.0f, 15.0f, 4.5f, 6.0f);
  gfx->fillRect(sx(5.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(TRAE_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, fl * 0.3f), sw(1), sh(2), dim565(TRAE_DARK, 0.7f));
  drawTraeBody(fl, 1.0f, 0.95f);
  float blinkPhase = fmodf(t, 4.0f);
  float blink = (blinkPhase > 3.5f && blinkPhase < 3.7f) ? 0.15f : 0.5f;
  drawTraeFace(fl, 1.0f, blink);
  drawZParticles(t, 11.8f, 7.7f, TRAE_BODY);
}

void traeWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(7.0f, bounce, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(TRAE_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, bounce * 0.3f), sw(1), sh(2), dim565(TRAE_DARK, 0.7f));
  drawKeyboard(t, TRAE_KB_BASE, TRAE_KB_KEY, TRAE_KB_HI);
  drawTraeBody(bounce);
  float blinkPhase = fmodf(t, 2.5f);
  float blink = (blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.0f;
  drawTraeFace(bounce, 1.0f, blink);
}

void traeAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float pulse = (pct > 0.03f && pct < 0.55f) ? 1.0f + sinf(pct * 20.0f) * 0.08f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(7.0f, jumpY, 16.0f, 4.0f, 7.0f);
  gfx->fillRect(sx(5.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(TRAE_DARK, 0.7f));
  gfx->fillRect(sx(8.5f), sy(14, jumpY * 0.3f), sw(1), sh(2), dim565(TRAE_DARK, 0.7f));
  setViewportShiftX(shakeX);
  drawTraeBody(jumpY, pulse, pulse);
  drawTraeFace(jumpY, pct > 0.03f && pct < 0.15f ? 1.3f : 1.0f);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, TRAE_ALERT);
}

void traeQuestion(float t) {
  _questionMode = true;
  traeAlert(t);
  _questionMode = false;
}
