#pragma once
#include "mascot_common.h"

// Claude (Clawd) — Orange crab with keyboard
#define CLAWD_BODY    RGB565(222, 136, 109)

static const float kfArmLClawd[] = {
  0,0, 0.03f,0, 0.10f,25, 0.15f,30, 0.20f,155, 0.25f,115,
  0.30f,140, 0.35f,100, 0.40f,115, 0.45f,80, 0.50f,80,
  0.55f,40, 0.62f,0, 1.0f,0
};
static const float kfArmRClawd[] = {
  0,0, 0.03f,0, 0.10f,30, 0.15f,30, 0.20f,155, 0.25f,115,
  0.30f,140, 0.35f,100, 0.40f,115, 0.45f,80, 0.50f,80,
  0.55f,40, 0.62f,0, 1.0f,0
};
#define CLAWD_EYE     0x0000
#define CLAWD_ALERT   RGB565(255, 61, 0)
#define CLAWD_KB_BASE RGB565(97, 112, 128)
#define CLAWD_KB_KEY  RGB565(153, 168, 184)
#define CLAWD_KB_HI   0xFFFF

void clawdSleep(float t) {
  useViewport(17.0f, 7.0f, 9.0f);
  float phase = fmodf(t, 4.5f) / 4.5f;
  float breathe = (phase < 0.4f) ? sinf(phase / 0.4f * PI) : 0.0f;
  float puff = fmaxf(0.0f, breathe) * 0.25f;
  float torsoH = 5.0f * (1.0f + breathe * 0.25f);
  float torsoW = 13.0f * (1.0f + breathe * 0.015f);
  float torsoX = 1.0f - (torsoW - 13.0f) / 2.0f;
  float torsoY = 15.0f - torsoH;
  float shadowW = 17.0f * (1.0f + breathe * 0.03f);
  gfx->fillRect(sx(-1), sy(15), sw(shadowW), sh(1), RGB565(40,40,40));
  float legPos[] = {3, 5, 9, 11};
  for (int i = 0; i < 4; i++)
    gfx->fillRect(sx(legPos[i]), sy(8.5f), sw(1), sh(1.5f), CLAWD_BODY);
  gfx->fillRect(sx(torsoX), sy(torsoY), sw(torsoW), sh(torsoH), CLAWD_BODY);
  gfx->fillRect(sx(-1), sy(13), sw(2), sh(2), CLAWD_BODY);
  gfx->fillRect(sx(14), sy(13), sw(2), sh(2), CLAWD_BODY);
  float eyeY = 12.2f - puff * 2.5f;
  float eyeOff = globalBoredEyeOffsetX * 0.5f;
  gfx->fillRect(sx(3 + eyeOff), sy(eyeY), sw(2.5f), sh(1.0f), CLAWD_EYE);
  gfx->fillRect(sx(9.5f + eyeOff), sy(eyeY), sw(2.5f), sh(1.0f), CLAWD_EYE);
  drawBoredYawn(t, 6.0f, 13.5f);
  drawZParticles(t);
}

void clawdWork(float t) {
  useViewport(16.0f, 11.0f, 5.5f);
  float bounce = sinf(t * 2.0f * PI / 0.35f) * 1.2f;
  float breathe = sinf(t * 2.0f * PI / 3.2f);
  float armLRaw = sinf(t * 2.0f * PI / 0.15f);
  float armRRaw = sinf(t * 2.0f * PI / 0.12f);
  float armL = armLRaw * 22.5f - 32.5f;
  float armR = armRRaw * 22.5f + 32.5f;
  bool leftHit = armLRaw > 0.3f;
  bool rightHit = armRRaw > 0.3f;
  int leftKeyCol = ((int)(t / 0.15f)) % 3;
  int rightKeyCol = 3 + ((int)(t / 0.12f)) % 3;
  float scanPhase = fmodf(t, 10.0f);
  float eyeScale = (scanPhase > 5.7f && scanPhase < 6.9f) ? 1.0f : 0.5f;
  float eyeDY = (eyeScale < 0.8f) ? 1.0f : -0.5f;
  float blinkPhase = fmodf(t, 3.5f);
  float finalEyeScale = (blinkPhase > 1.4f && blinkPhase < 1.55f) ? 0.1f : eyeScale;
  float dy = bounce;
  float torsoW = 11.0f * (1.0f + breathe * 0.015f);
  float shadowW = 9.0f - fabsf(dy) * 0.3f;
  float shadowOp = 0.1f + (1.0f - fabsf(dy) / 1.2f) * 0.3f;
  if (shadowOp < 0) shadowOp = 0;
  uint8_t sg = (uint8_t)(40 * shadowOp);
  gfx->fillRect(sx(3 + (9-shadowW)/2), sy(15), sw(shadowW), sh(1), RGB565(sg,sg,sg));
  float legX[] = {3, 5, 9, 11};
  for (int i = 0; i < 4; i++)
    gfx->fillRect(sx(legX[i]), sy(13), sw(1), sh(2), CLAWD_BODY);
  gfx->fillRect(sx(2 - (torsoW - 11) / 2), sy(6, dy), sw(torsoW), sh(7), CLAWD_BODY);
  float eyeH = 2.0f * finalEyeScale;
  float eyeY = 8.0f + (2.0f - eyeH) / 2.0f + eyeDY;
  gfx->fillRect(sx(4), sy(eyeY, dy), sw(1), sh(eyeH), CLAWD_EYE);
  gfx->fillRect(sx(10), sy(eyeY, dy), sw(1), sh(eyeH), CLAWD_EYE);
  gfx->fillRect(sx(-0.5f), sy(11.8f), sw(16), sh(3.5f), CLAWD_KB_BASE);
  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 6; col++) {
      float kx = 0.3f + col * 2.5f;
      float ky = 12.2f + row * 1.0f;
      float kw = 2.0f;
      if (row == 1 && col == 2) kw = 4.5f;
      gfx->fillRect(sx(kx), sy(ky), sw(kw), sh(0.7f), CLAWD_KB_KEY);
    }
  }
  if (leftHit) {
    int r = leftKeyCol % 3;
    gfx->fillRect(sx(0.3f + leftKeyCol * 2.5f), sy(12.2f + r * 1.0f), sw(2.0f), sh(0.7f), CLAWD_KB_HI);
  }
  if (rightHit) {
    int r = (rightKeyCol - 3) % 3;
      gfx->fillRect(sx(0.3f + rightKeyCol * 2.5f), sy(12.2f + r * 1.0f), sw(2.0f), sh(0.7f), CLAWD_KB_HI);
  }
  fillRotatedRect(0, 9, 2, 2, 2, 10, armL, dy, CLAWD_BODY);
  fillRotatedRect(13, 9, 2, 2, 13, 10, armR, dy, CLAWD_BODY);
}

void clawdAlert(float t) {
  useViewport(15.0f, 12.0f, 4.0f);
  float cycle = 3.5f;
  float pct = fmodf(t, cycle) / cycle;
  float jumpY = lerpKF(kfJumpCommon, 18, pct);
  float aL = lerpKF(kfArmLClawd, 14, pct);
  float aR = -lerpKF(kfArmRClawd, 14, pct);
  float eScale = lerpKF(kfEyeSCommon, 6, pct);
  float bangOp = lerpKF(kfBangOpCommon, 6, pct);
  float bangSc = lerpKF(kfBangScCommon, 6, pct);
  float dy = jumpY;
  drawShadow(9.0f, jumpY);
  float legX[] = {3, 5, 9, 11};
  for (int i = 0; i < 4; i++)
    gfx->fillRect(sx(legX[i]), sy(11), sw(1), sh(4), CLAWD_BODY);
  float scX = (jumpY > 0.5f) ? 1.0f + jumpY * 0.05f : 1.0f;
  float scY = (jumpY > 0.5f) ? 1.0f - jumpY * 0.04f : 1.0f;
  float tW = 11.0f * scX;
  float tH = 7.0f * scY;
  gfx->fillRect(sx(2 - (tW - 11)/2), sy(6 + (7 - tH), dy), sw(tW), sh(tH), CLAWD_BODY);
  float eyeH = 2.0f * eScale;
  float eyeDY = (pct > 0.03f && pct < 0.15f) ? -0.5f : 0.0f;
  float eyeY = 8.0f + (2.0f - eyeH)/2.0f + eyeDY;
  gfx->fillRect(sx(4), sy(eyeY, dy), sw(1), sh(eyeH), CLAWD_EYE);
  gfx->fillRect(sx(10), sy(eyeY, dy), sw(1), sh(eyeH), CLAWD_EYE);
  fillRotatedRect(0, 9, 2, 2, 2, 10, aL, dy, CLAWD_BODY);
  fillRotatedRect(13, 9, 2, 2, 13, 10, aR, dy, CLAWD_BODY);
  drawBang(bangOp, bangSc, jumpY, dy, CLAWD_ALERT, 4.5f);
}

void clawdQuestion(float t) {
  _questionMode = true;
  clawdAlert(t);
  _questionMode = false;
}
