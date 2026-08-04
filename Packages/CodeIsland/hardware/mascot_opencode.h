#pragma once
#include "mascot_common.h"

// OpenCode — Gray square with { } bracket face
#define OPC_BODY    RGB565(56, 56, 61)
#define OPC_FRAME   RGB565(140, 140, 145)
#define OPC_FACE    RGB565(217, 217, 222)
#define OPC_LEG     RGB565(89, 89, 94)
#define OPC_ALERT   RGB565(255, 140, 0)  // Amber (not red!)
#define OPC_KB_BASE RGB565(31, 31, 36)
#define OPC_KB_KEY  RGB565(77, 77, 82)
#define OPC_KB_HI   0xFFFF

static void drawOpenCodeBody(float dy, float squashX = 1.0f, float squashY = 1.0f) {
  float cx = 7.5f;
  auto rx = [&](float x) { return cx + (x - cx) * squashX; };
  auto ry = [&](float y) { return y * squashY + (1.0f - squashY) * 10.0f; };
  float rows[][3] = {
    {5,3,9},{6,2,11},{7,2,11},{8,2,11},{9,2,11},
    {10,2,11},{11,2,11},{12,2,11},{13,3,9}
  };
  for (int i = 0; i < 9; i++) {
    gfx->fillRect(sx(rx(rows[i][1])), sy(ry(rows[i][0]), dy), sw(rows[i][2] * squashX), sh(1 * squashY), OPC_BODY);
  }
  gfx->fillRect(sx(rx(3)), sy(ry(6), dy), sw(9 * squashX), sh(0.7f * squashY), dim565(OPC_FRAME, 0.6f));
  gfx->fillRect(sx(rx(3)), sy(ry(12), dy), sw(9 * squashX), sh(0.7f * squashY), dim565(OPC_FRAME, 0.6f));
  for (int yi = 7; yi < 12; yi++) {
    gfx->fillRect(sx(rx(3)), sy(ry((float)yi), dy), sw(0.7f * squashX), sh(1 * squashY), dim565(OPC_FRAME, 0.4f));
    gfx->fillRect(sx(rx(11.3f)), sy(ry((float)yi), dy), sw(0.7f * squashX), sh(1 * squashY), dim565(OPC_FRAME, 0.4f));
  }
}

static void drawBrackets(float dy, float scale, uint16_t col) {
  float eyeH = fmaxf(0.3f, 2.0f * scale);
  float eyeY = 8.5f + (2.0f - eyeH) / 2.0f;
  // Left bracket {
  gfx->fillRect(sx(4.5f), sy(eyeY, dy), sw(0.8f), sh(eyeH), col);
  gfx->fillRect(sx(4.0f), sy(eyeY + eyeH * 0.3f, dy), sw(0.7f), sh(fmaxf(0.3f, eyeH * 0.4f)), col);
  // Right bracket }
  gfx->fillRect(sx(9.7f), sy(eyeY, dy), sw(0.8f), sh(eyeH), col);
  gfx->fillRect(sx(10.2f), sy(eyeY + eyeH * 0.3f, dy), sw(0.7f), sh(fmaxf(0.3f, eyeH * 0.4f)), col);
  // Center cursor dot
  if (scale > 0.5f) gfx->fillRect(sx(7.1f), sy(9.2f, dy), sw(0.8f), sh(0.8f), dim565(col, 0.8f));
}

void opencodeSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.8f;
  drawShadow(7.0f + fabsf(fl) * 0.3f, 0.0f, 14.5f, 4.0f, 7.0f);
  gfx->fillRect(sx(4), sy(13.5f), sw(1), sh(1.5f), OPC_LEG);
  gfx->fillRect(sx(10), sy(13.5f), sw(1), sh(1.5f), OPC_LEG);
  drawOpenCodeBody(fl);
  drawBrackets(fl, 0.3f, dim565(OPC_FACE, 0.4f));
  drawZParticles(t);
}

void opencodeWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(8.0f, bounce, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(4), sy(13.5f), sw(1), sh(1.5f), OPC_LEG);
  gfx->fillRect(sx(10), sy(13.5f), sw(1), sh(1.5f), OPC_LEG);
  drawKeyboard(t, OPC_KB_BASE, OPC_KB_KEY, OPC_KB_HI);
  drawOpenCodeBody(bounce);
  float blinkPhase = fmodf(t, 3.0f);
  float scale = (blinkPhase > 2.6f && blinkPhase < 2.75f) ? 0.1f : 1.0f;
  drawBrackets(bounce, scale, OPC_FACE);
}

void opencodeAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float squashX = jumpY > 0.5f ? 1.0f + jumpY * 0.03f : 1.0f;
  float squashY = jumpY > 0.5f ? 1.0f - jumpY * 0.02f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(8.0f, jumpY, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(4), sy(13.5f), sw(1), sh(1.5f), OPC_LEG);
  gfx->fillRect(sx(10), sy(13.5f), sw(1), sh(1.5f), OPC_LEG);
  setViewportShiftX(shakeX);
  drawOpenCodeBody(jumpY, squashX, squashY);
  float eScale = (pct > 0.03f && pct < 0.15f) ? 1.3f : 1.0f;
  drawBrackets(jumpY, eScale, OPC_FACE);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, OPC_ALERT);
}

void opencodeQuestion(float t) {
  _questionMode = true;
  opencodeAlert(t);
  _questionMode = false;
}
