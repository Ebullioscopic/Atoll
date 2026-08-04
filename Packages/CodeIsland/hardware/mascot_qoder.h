#pragma once
#include "mascot_common.h"

// Qoder — Green chat bubble with Q face
#define QOD_BODY    RGB565(42, 219, 92)
#define QOD_DARK    RGB565(30, 166, 71)
#define QOD_FACE    0x0000
#define QOD_FACE_DIM RGB565(20, 90, 35)
#define QOD_ALERT   RGB565(255, 61, 0)
#define QOD_KB_BASE RGB565(26, 46, 31)
#define QOD_KB_KEY  RGB565(51, 97, 61)
#define QOD_KB_HI   RGB565(42, 219, 92)

static void drawQoderBubble(float dy, float squashX = 1.0f, float squashY = 1.0f) {
  float cx = 7.5f;
  auto rx = [&](float x) { return cx + (x - cx) * squashX; };
  auto ry = [&](float y) { return y * squashY + (1.0f - squashY) * 10.0f; };
  // Chat bubble shape (pixel rows)
  gfx->fillRect(sx(rx(4)), sy(ry(14), dy), sw(7 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(2)), sy(ry(13), dy), sw(11 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(12), dy), sw(13 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(11), dy), sw(13 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(10), dy), sw(13 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(9), dy), sw(13 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(1)), sy(ry(8), dy), sw(13 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(2)), sy(ry(7), dy), sw(11 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(3)), sy(ry(6), dy), sw(9 * squashX), sh(1 * squashY), QOD_BODY);
  gfx->fillRect(sx(rx(4)), sy(ry(5), dy), sw(7 * squashX), sh(1 * squashY), QOD_BODY);
}

static void drawQoderFace(float dy, uint16_t col, float eyeScale = 1.0f, bool smile = true) {
  float eyeH = fmaxf(0.3f, 1.5f * eyeScale);
  float eyeY = 9.0f + (1.5f - eyeH) / 2.0f;
  gfx->fillRect(sx(4), sy(eyeY, dy), sw(1.2f), sh(eyeH), col);
  gfx->fillRect(sx(9.8f), sy(eyeY, dy), sw(1.2f), sh(eyeH), col);
  if (smile) {
    gfx->fillRect(sx(5), sy(11.5f, dy), sw(1), sh(0.8f), col);
    gfx->fillRect(sx(6), sy(12, dy), sw(3), sh(0.8f), col);
    gfx->fillRect(sx(9), sy(11.5f, dy), sw(1), sh(0.8f), col);
  }
}

void qoderSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(7.0f + fabsf(fl) * 0.3f, 0.0f, 15.5f, 4.0f, 7.0f);
  gfx->fillRect(sx(5), sy(14.5f), sw(1), sh(1.5f), QOD_DARK);
  gfx->fillRect(sx(9), sy(14.5f), sw(1), sh(1.5f), QOD_DARK);
  drawQoderBubble(fl);
  drawQoderFace(fl, QOD_FACE_DIM, 0.3f, false);
  drawZParticles(t);
}

void qoderWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(8.0f, bounce, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(5), sy(14.5f), sw(1), sh(1.5f), QOD_DARK);
  gfx->fillRect(sx(9), sy(14.5f), sw(1), sh(1.5f), QOD_DARK);
  drawKeyboard(t, QOD_KB_BASE, QOD_KB_KEY, QOD_KB_HI);
  drawQoderBubble(bounce);
  float blinkPhase = fmodf(t, 3.0f);
  float blink = (blinkPhase > 2.6f && blinkPhase < 2.75f) ? 0.1f : 1.0f;
  drawQoderFace(bounce, QOD_FACE, blink, true);
}

void qoderAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float squashX = jumpY > 0.5f ? 1.0f + jumpY * 0.03f : 1.0f;
  float squashY = jumpY > 0.5f ? 1.0f - jumpY * 0.02f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(8.0f, jumpY, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(5), sy(14.5f), sw(1), sh(1.5f), QOD_DARK);
  gfx->fillRect(sx(9), sy(14.5f), sw(1), sh(1.5f), QOD_DARK);
  setViewportShiftX(shakeX);
  drawQoderBubble(jumpY, squashX, squashY);
  drawQoderFace(jumpY, QOD_FACE, pct > 0.03f && pct < 0.15f ? 1.3f : 1.0f, true);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, QOD_ALERT);
}

void qoderQuestion(float t) {
  _questionMode = true;
  qoderAlert(t);
  _questionMode = false;
}
