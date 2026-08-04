#pragma once
#include "mascot_common.h"

// Buddy (CodeBuddy) — Purple cat astronaut with cyan glow
#define BUD_BODY    RGB565(108, 77, 255)
#define BUD_DARK    RGB565(88, 62, 211)
#define BUD_GLOW    RGB565(50, 230, 185)
#define BUD_FACE    0xFFFF
#define BUD_ALERT   RGB565(255, 61, 0)
#define BUD_KB_BASE RGB565(46, 39, 77)
#define BUD_KB_KEY  RGB565(89, 77, 140)
#define BUD_KB_HI   RGB565(50, 230, 185)

static void drawBuddyBody(float dy, float squashX = 1.0f, float squashY = 1.0f) {
  float cx = 7.5f;
  auto rx = [&](float x) { return cx + (x - cx) * squashX; };
  auto ry = [&](float y) { return y * squashY + (1.0f - squashY) * 10.0f; };
  float rows[][3] = {
    {14,3,9}, {13,2,11}, {12,2,11}, {11,2,11}, {10,3,9},
    {9,3,9}, {8,3,9}, {7,3,9}, {6,4,7}
  };
  for (int i = 0; i < 9; i++) {
    gfx->fillRect(sx(rx(rows[i][1])), sy(ry(rows[i][0]), dy), sw(rows[i][2] * squashX), sh(1 * squashY), BUD_BODY);
  }
  float earY = 4.0f * squashY + (1.0f - squashY) * 10.0f;
  gfx->fillRect(sx(rx(2.5f)), sy(earY, dy), sw(2.5f * squashX), sh(2 * squashY), BUD_BODY);
  gfx->fillRect(sx(rx(10.0f)), sy(earY, dy), sw(2.5f * squashX), sh(2 * squashY), BUD_BODY);
  gfx->fillRect(sx(rx(3.0f)), sy(earY + 0.5f * squashY, dy), sw(1.5f * squashX), sh(1.2f * squashY), dim565(BUD_GLOW, 0.6f));
  gfx->fillRect(sx(rx(10.5f)), sy(earY + 0.5f * squashY, dy), sw(1.5f * squashX), sh(1.2f * squashY), dim565(BUD_GLOW, 0.6f));
  gfx->fillRect(sx(rx(3.5f)), sy(7.0f * squashY + (1.0f - squashY) * 10.0f, dy), sw(8 * squashX), sh(2.5f * squashY), BUD_DARK);
  gfx->fillRect(sx(rx(7.0f)), sy(8.8f * squashY + (1.0f - squashY) * 10.0f, dy), sw(1), sh(0.8f * squashY), dim565(BUD_GLOW, 0.4f));
  gfx->fillRect(sx(rx(12.0f)), sy(12.0f * squashY + (1.0f - squashY) * 10.0f, dy), sw(2 * squashX), sh(1 * squashY), BUD_BODY);
  gfx->fillRect(sx(rx(13.0f)), sy(11.0f * squashY + (1.0f - squashY) * 10.0f, dy), sw(1 * squashX), sh(1 * squashY), BUD_BODY);
}

void buddySleep(float t) {
  useViewport(15.0f, 13.0f, 3.0f);
  float fl = sinf(fmodf(t, 4.0f) / 4.0f * 2.0f * PI) * 0.6f;
  drawShadow(7.0f + fabsf(fl) * 0.3f, 0.0f, 15.5f, 4.0f, 7.0f);
  gfx->fillRect(sx(4), sy(14.5f), sw(1.5f), sh(1.5f), BUD_DARK);
  gfx->fillRect(sx(9.5f), sy(14.5f), sw(1.5f), sh(1.5f), BUD_DARK);
  drawBuddyBody(fl);
  gfx->fillRect(sx(5), sy(8.0f, fl), sw(1.2f), sh(0.3f), dim565(BUD_GLOW, 0.3f));
  gfx->fillRect(sx(8.8f), sy(8.0f, fl), sw(1.2f), sh(0.3f), dim565(BUD_GLOW, 0.3f));
  drawZParticles(t);
}

void buddyWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(8.0f, bounce, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(4), sy(14.5f), sw(1.5f), sh(1.5f), BUD_DARK);
  gfx->fillRect(sx(9.5f), sy(14.5f), sw(1.5f), sh(1.5f), BUD_DARK);
  drawKeyboard(t, BUD_KB_BASE, BUD_KB_KEY, BUD_KB_HI);
  drawBuddyBody(bounce);
  float blinkPhase = fmodf(t, 2.5f);
  float eyeH = (blinkPhase > 2.2f && blinkPhase < 2.35f) ? 0.1f : 1.2f;
  gfx->fillRect(sx(5), sy(7.5f + (1.2f - eyeH)/2.0f, bounce), sw(1.2f), sh(eyeH), BUD_GLOW);
  gfx->fillRect(sx(8.8f), sy(7.5f + (1.2f - eyeH)/2.0f, bounce), sw(1.2f), sh(eyeH), BUD_GLOW);
}

void buddyAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float squashX = jumpY > 0.5f ? 1.0f + jumpY * 0.03f : 1.0f;
  float squashY = jumpY > 0.5f ? 1.0f - jumpY * 0.02f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  drawShadow(8.0f, jumpY, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(4), sy(14.5f), sw(1.5f), sh(1.5f), BUD_DARK);
  gfx->fillRect(sx(9.5f), sy(14.5f), sw(1.5f), sh(1.5f), BUD_DARK);
  setViewportShiftX(shakeX);
  drawBuddyBody(jumpY, squashX, squashY);
  // Eye flash cyan/red
  bool flash = sinf(pct * 25) > 0;
  uint16_t eyeCol = (pct > 0.03f && pct < 0.55f && flash) ? BUD_ALERT : BUD_GLOW;
  float eScale = lerpKF(kfEyeSCommon, 6, pct);
  float eyeH = 1.2f * eScale;
  gfx->fillRect(sx(5), sy(7.5f + (1.2f - eyeH)/2.0f, jumpY), sw(1.2f), sh(eyeH), eyeCol);
  gfx->fillRect(sx(8.8f), sy(7.5f + (1.2f - eyeH)/2.0f, jumpY), sw(1.2f), sh(eyeH), eyeCol);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, BUD_ALERT);
}

void buddyQuestion(float t) {
  _questionMode = true;
  buddyAlert(t);
  _questionMode = false;
}
