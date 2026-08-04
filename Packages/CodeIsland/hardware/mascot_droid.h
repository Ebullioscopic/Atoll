#pragma once
#include "mascot_common.h"

// Droid (Factory) — Industrial robot with antenna
#define DRD_BODY    RGB565(213, 106, 38)
#define DRD_DARK    RGB565(166, 82, 30)
#define DRD_METAL   RGB565(102, 101, 94)
#define DRD_EYE     RGB565(227, 153, 42)
#define DRD_ALERT   RGB565(255, 61, 0)
#define DRD_KB_BASE RGB565(39, 33, 31)
#define DRD_KB_KEY  RGB565(82, 74, 68)
#define DRD_KB_HI   RGB565(213, 106, 38)

static void drawDroidBody(float dy, float squashX = 1.0f, float squashY = 1.0f) {
  float cx = 7.5f;
  float bw = 9.0f * squashX, bh = 6.0f * squashY;
  float bx = cx - bw / 2.0f;
  float by = 9.0f + (6.0f - bh);
  float hw = 7.0f * squashX, hh = 3.0f * squashY;
  float hx = cx - hw / 2.0f;
  float hy = by - hh + 0.5f;
  // Antenna
  gfx->fillRect(sx(cx - 0.5f), sy(hy - 2.0f, dy), sw(1), sh(2), DRD_METAL);
  gfx->fillRect(sx(cx - 1.0f), sy(hy - 2.5f, dy), sw(2), sh(1), DRD_EYE);
  // Head and body
  gfx->fillRect(sx(hx), sy(hy, dy), sw(hw), sh(hh), DRD_BODY);
  gfx->fillRect(sx(bx), sy(by, dy), sw(bw), sh(bh), DRD_BODY);
  // Chest plate
  float pw = 5.0f * squashX, ph = 3.0f * squashY;
  gfx->fillRect(sx(cx - pw / 2.0f), sy(by + 1.0f, dy), sw(pw), sh(ph), DRD_DARK);
  // Rivets
  gfx->fillRect(sx(cx - pw / 2.0f + 0.5f), sy(by + 1.5f, dy), sw(0.8f), sh(0.8f), DRD_METAL);
  gfx->fillRect(sx(cx + pw / 2.0f - 1.3f), sy(by + 1.5f, dy), sw(0.8f), sh(0.8f), DRD_METAL);
  // Side arms (metal)
  gfx->fillRect(sx(bx - 1.5f), sy(by + 1.0f, dy), sw(1.5f), sh(4 * squashY), DRD_METAL);
  gfx->fillRect(sx(bx + bw), sy(by + 1.0f, dy), sw(1.5f), sh(4 * squashY), DRD_METAL);
}

void droidSleep(float t) {
  useViewport(16.0f, 16.0f, 2.0f);
  float phase = fmodf(t, 5.0f) / 5.0f;
  float breathe = sinf(phase * 2.0f * PI) * 0.4f;
  gfx->fillRect(sx(7.5f - 8.0f / 2.0f), sy(16), sw(8), sh(1), RGB565(50, 50, 50));
  gfx->fillRect(sx(4.5f), sy(15), sw(2), sh(1.5f), DRD_DARK);
  gfx->fillRect(sx(8.5f), sy(15), sw(2), sh(1.5f), DRD_DARK);
  drawDroidBody(breathe);
  // Eye flicker (powering down)
  float flickerPhase = fmodf(t, 3.0f);
  if (flickerPhase < 2.5f) {
    gfx->fillRect(sx(4.8f), sy(8.0f, breathe), sw(1.5f), sh(0.5f), dim565(DRD_EYE, 0.3f));
    gfx->fillRect(sx(8.7f), sy(8.0f, breathe), sw(1.5f), sh(0.5f), dim565(DRD_EYE, 0.3f));
  }
  drawZParticles(t);
}

void droidWork(float t) {
  useViewport(16.0f, 16.0f, 2.0f);
  float bounce = sinf(t * 2.0f * PI / 0.5f) * 0.8f;
  float shadowW = 9.0f - fabsf(bounce) * 0.3f;
  gfx->fillRect(sx(3.5f + (9.0f - shadowW) / 2.0f), sy(17), sw(shadowW), sh(1), RGB565(70, 70, 70));
  gfx->fillRect(sx(4.5f), sy(15), sw(2), sh(1.5f), DRD_DARK);
  gfx->fillRect(sx(8.5f), sy(15), sw(2), sh(1.5f), DRD_DARK);
  drawKeyboard(t, DRD_KB_BASE, DRD_KB_KEY, DRD_KB_HI, 15.0f, 0.12f);
  drawDroidBody(bounce);
  // Eyes with blink
  float blinkPhase = fmodf(t, 2.0f);
  float eyeH = (blinkPhase > 1.7f && blinkPhase < 1.85f) ? 0.1f : 1.2f;
  gfx->fillRect(sx(4.8f), sy(8.0f + (1.2f - eyeH)/2.0f, bounce), sw(1.5f), sh(eyeH), DRD_EYE);
  gfx->fillRect(sx(8.7f), sy(8.0f + (1.2f - eyeH)/2.0f, bounce), sw(1.5f), sh(eyeH), DRD_EYE);
}

void droidAlert(float t) {
  useViewport(16.0f, 16.0f, 2.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float squashX = jumpY > 0.5f ? 1.0f + jumpY * 0.03f : 1.0f;
  float squashY = jumpY > 0.5f ? 1.0f - jumpY * 0.02f : 1.0f;
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  float shadowW = 9.0f * (1.0f - fabsf(fminf(0.0f, jumpY)) * 0.04f);
  gfx->fillRect(sx(3.5f + (9.0f - shadowW) / 2.0f), sy(17), sw(shadowW), sh(1), RGB565(80, 80, 80));
  gfx->fillRect(sx(4.5f), sy(15), sw(2), sh(1.5f), DRD_DARK);
  gfx->fillRect(sx(8.5f), sy(15), sw(2), sh(1.5f), DRD_DARK);
  setViewportShiftX(shakeX);
  drawDroidBody(jumpY, squashX, squashY);
  // Eye flash
  bool flash = sinf(pct * 20) > 0;
  uint16_t eyeCol = (pct > 0.03f && pct < 0.55f && flash) ? DRD_ALERT : DRD_EYE;
  float eScale = lerpKF(kfEyeSCommon, 6, pct);
  float eyeH = eScale * 1.2f;
  gfx->fillRect(sx(4.8f), sy(8.0f + (1.2f - eyeH)/2.0f, jumpY), sw(1.5f), sh(eyeH), eyeCol);
  gfx->fillRect(sx(8.7f), sy(8.0f + (1.2f - eyeH)/2.0f, jumpY), sw(1.5f), sh(eyeH), eyeCol);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, DRD_ALERT, 3.0f);
}

void droidQuestion(float t) {
  _questionMode = true;
  droidAlert(t);
  _questionMode = false;
}
