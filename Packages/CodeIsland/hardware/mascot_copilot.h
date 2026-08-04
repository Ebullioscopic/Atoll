#pragma once
#include "mascot_common.h"

// Copilot — Rose robot head with ear loops and gold eyes
#define COP_EARS    RGB565(51, 51, 51)
#define COP_BODY    RGB565(204, 51, 102)
#define COP_FACE    RGB565(34, 34, 40)
#define COP_EYE     RGB565(255, 215, 0)
#define COP_ALERT   RGB565(254, 76, 37)
#define COP_KB_BASE RGB565(31, 20, 26)
#define COP_KB_KEY  RGB565(89, 38, 56)
#define COP_KB_HI   0xFFFF

static void drawCopilotBody(float dy, uint16_t earCol = COP_EARS,
                            uint16_t shellCol = COP_BODY, bool signal = false) {
  // Ear loops (hollow rectangles)
  // Left ear
  gfx->fillRect(sx(3), sy(5, dy), sw(3), sh(1), earCol);  // top
  gfx->fillRect(sx(3), sy(6, dy), sw(1), sh(1), earCol);  // left wall
  gfx->fillRect(sx(5), sy(6, dy), sw(1), sh(1), earCol);  // right wall
  gfx->fillRect(sx(3), sy(7, dy), sw(3), sh(1), earCol);  // bottom
  // Right ear
  gfx->fillRect(sx(9), sy(5, dy), sw(3), sh(1), earCol);  // top
  gfx->fillRect(sx(9), sy(6, dy), sw(1), sh(1), earCol);  // left wall
  gfx->fillRect(sx(11), sy(6, dy), sw(1), sh(1), earCol); // right wall
  gfx->fillRect(sx(9), sy(7, dy), sw(3), sh(1), earCol);  // bottom
  // Ear stems
  gfx->fillRect(sx(4), sy(8, dy), sw(1), sh(1), earCol);
  gfx->fillRect(sx(10), sy(8, dy), sw(1), sh(1), earCol);
  if (signal) {
    gfx->fillRect(sx(4), sy(6, dy), sw(1), sh(1), dim565(COP_EYE, 0.5f));
    gfx->fillRect(sx(10), sy(6, dy), sw(1), sh(1), dim565(COP_EYE, 0.5f));
  }
  // Rose shell frame
  gfx->fillRect(sx(2), sy(9, dy), sw(11), sh(1), shellCol);
  gfx->fillRect(sx(2), sy(10, dy), sw(2), sh(3), shellCol);
  gfx->fillRect(sx(11), sy(10, dy), sw(2), sh(3), shellCol);
  // Face screen (dark inset)
  gfx->fillRect(sx(4), sy(10, dy), sw(7), sh(3), COP_FACE);
  gfx->fillRect(sx(2), sy(13, dy), sw(11), sh(1), shellCol);
  gfx->fillRect(sx(4), sy(14, dy), sw(7), sh(1), shellCol);
}

void copilotSleep(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float phase = fmodf(t, 4.0f) / 4.0f;
  float fl = sinf(phase * 2.0f * PI) * 0.8f;
  drawShadow(7.0f + fabsf(fl) * 0.3f);
  gfx->fillRect(sx(6), sy(14.5f), sw(1), sh(1.5f), dim565(COP_BODY, 0.6f));
  gfx->fillRect(sx(8), sy(14.5f), sw(1), sh(1.5f), dim565(COP_BODY, 0.6f));
  drawCopilotBody(fl, COP_EARS, dim565(COP_BODY, 0.4f));
  // Screen off (no eyes)
  drawZParticles(t);
}

void copilotWork(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float bounce = sinf(t * 2.0f * PI / 0.4f) * 1.0f;
  drawShadow(8.0f, bounce, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(6), sy(14.5f), sw(1), sh(1.5f), dim565(COP_BODY, 0.6f));
  gfx->fillRect(sx(8), sy(14.5f), sw(1), sh(1.5f), dim565(COP_BODY, 0.6f));
  drawKeyboard(t, COP_KB_BASE, COP_KB_KEY, COP_KB_HI);
  float sigPhase = fmodf(t, 2.5f);
  bool earSignal = sigPhase > 2.0f && sigPhase < 2.3f;
  drawCopilotBody(bounce, COP_EARS, COP_BODY, earSignal);
  float blinkPhase = fmodf(t, 3.2f);
  if (!(blinkPhase > 1.5f && blinkPhase < 1.6f)) {
    gfx->fillRect(sx(5), sy(10, bounce), sw(1), sh(1), COP_EYE);
    gfx->fillRect(sx(9), sy(10, bounce), sw(1), sh(1), COP_EYE);
  }
}

void copilotAlert(float t) {
  useViewport(16.0f, 14.0f, 3.0f);
  float pct = fmodf(t, 3.5f) / 3.5f;
  float jumpY = lerpKF(kfJumpSoft, 18, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float shakeX = (pct > 0.15f && pct < 0.55f) ? sinf(pct * 80.0f) * 0.6f : 0.0f;
  bool flash = (pct > 0.03f && pct < 0.55f && sinf(pct * 25.0f) > 0.0f);
  uint16_t earCol = flash ? COP_ALERT : COP_EARS;
  uint16_t shellCol = flash ? COP_ALERT : COP_BODY;
  drawShadow(8.0f, jumpY, 16.0f, 4.0f, 8.0f);
  gfx->fillRect(sx(6), sy(14.5f), sw(1), sh(1.5f), dim565(COP_BODY, 0.6f));
  gfx->fillRect(sx(8), sy(14.5f), sw(1), sh(1.5f), dim565(COP_BODY, 0.6f));
  setViewportShiftX(shakeX);
  drawCopilotBody(jumpY, earCol, shellCol);
  float eyeH = (pct > 0.03f && pct < 0.55f) ? 2.0f : 1.0f;
  gfx->fillRect(sx(5), sy(10, jumpY), sw(1), sh(eyeH), COP_EYE);
  gfx->fillRect(sx(9), sy(10, jumpY), sw(1), sh(eyeH), COP_EYE);
  setViewportShiftX(0.0f);
  drawBang(bangOp, bangSc, jumpY, jumpY, COP_ALERT);
}

void copilotQuestion(float t) {
  _questionMode = true;
  copilotAlert(t);
  _questionMode = false;
}
