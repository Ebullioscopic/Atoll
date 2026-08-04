#pragma once
#include <Adafruit_GFX.h>

// Shared drawing context and helpers used by all mascot headers
extern GFXcanvas16* gfx;

#define RGB565(r, g, b) (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3))

#define LCD_W_  172
#define LCD_H_  320

static float vpS = LCD_W_ / 15.0f;
static float vpOX = 0.0f;
static float vpOY = (LCD_H_ - 10.0f * (LCD_W_ / 15.0f)) / 2.0f;
static float vpY0 = 6.0f;
static float vpShiftX = 0.0f;

inline void useViewport(float svgW, float svgH, float svgY0) {
  float sxScale = LCD_W_ / svgW;
  float syScale = LCD_H_ / svgH;
  vpS = fminf(sxScale, syScale);
  vpOX = (LCD_W_ - svgW * vpS) / 2.0f;
  vpOY = (LCD_H_ - svgH * vpS) / 2.0f;
  vpY0 = svgY0;
  vpShiftX = 0.0f;
}

inline void setViewportShiftX(float dx) { vpShiftX = dx; }

inline int sx(float x)              { return (int)roundf(vpOX + (x + vpShiftX) * vpS); }
inline int sy(float y, float dy=0)  { return (int)roundf(vpOY + (y - vpY0 + dy) * vpS); }
inline int sw(float w)              { return (int)roundf(w * vpS); }
inline int sh(float h)              { return (int)roundf(h * vpS); }

inline uint16_t dim565(uint16_t c, float k) {
  if (k <= 0.0f) return 0x0000;
  if (k > 1.0f) k = 1.0f;
  uint8_t r = (uint8_t)((((c >> 11) & 0x1F) * 255 / 31) * k);
  uint8_t g = (uint8_t)((((c >> 5) & 0x3F) * 255 / 63) * k);
  uint8_t b = (uint8_t)(((c & 0x1F) * 255 / 31) * k);
  return RGB565(r, g, b);
}

inline float lerpKF(const float* kf, int nPairs, float pct) {
  if (pct <= kf[0]) return kf[1];
  for (int i = 1; i < nPairs; i++) {
    int j = i * 2;
    if (pct <= kf[j]) {
      float t0 = kf[j-2], v0 = kf[j-1];
      float t1 = kf[j],   v1 = kf[j+1];
      float r = (pct - t0) / (t1 - t0);
      return v0 + (v1 - v0) * r;
    }
  }
  return kf[(nPairs-1)*2 + 1];
}

inline void fillRotatedRect(float rx, float ry, float rw, float rh,
                     float pivX, float pivY, float angleDeg, float dy,
                     uint16_t color) {
  float a = angleDeg * PI / 180.0f;
  float ca = cosf(a), sa = sinf(a);
  float cx[4] = { rx - pivX, rx + rw - pivX, rx + rw - pivX, rx - pivX };
  float cy[4] = { ry - pivY, ry - pivY, ry + rh - pivY, ry + rh - pivY };
  int16_t px[4], py[4];
  for (int i = 0; i < 4; i++) {
    float rotX = cx[i] * ca - cy[i] * sa + pivX;
    float rotY = cx[i] * sa + cy[i] * ca + pivY;
    px[i] = sx(rotX);
    py[i] = sy(rotY, dy);
  }
  gfx->fillTriangle(px[0],py[0], px[1],py[1], px[2],py[2], color);
  gfx->fillTriangle(px[0],py[0], px[2],py[2], px[3],py[3], color);
}

// Common alert jump keyframes (shared by most mascots)
static const float kfJumpCommon[] = {
  0,0, 0.03f,0, 0.10f,-1, 0.15f,1.5f, 0.175f,-10, 0.20f,-10,
  0.25f,1.5f, 0.275f,-8, 0.30f,-8, 0.35f,1.2f, 0.375f,-5, 0.40f,-5,
  0.45f,1.0f, 0.475f,-3, 0.50f,-3, 0.55f,0.5f, 0.62f,0, 1.0f,0
};
static const float kfJumpSoft[] = {
  0,0, 0.03f,0, 0.10f,-1, 0.15f,1.5f, 0.175f,-8, 0.20f,-8,
  0.25f,1.5f, 0.275f,-6, 0.30f,-6, 0.35f,1.0f, 0.375f,-4, 0.40f,-4,
  0.45f,0.8f, 0.475f,-2, 0.50f,-2, 0.55f,0.3f, 0.62f,0, 1.0f,0
};
static const float kfEyeSCommon[] = {
  0,1.0f, 0.03f,1.0f, 0.031f,1.3f, 0.15f,1.3f, 0.151f,1.0f, 1.0f,1.0f
};
static const float kfBangOpCommon[] = {
  0,0, 0.03f,1, 0.10f,1, 0.55f,1, 0.62f,0, 1.0f,0
};
static const float kfBangScCommon[] = {
  0,0.3f, 0.03f,1.3f, 0.10f,1.0f, 0.55f,1.0f, 0.62f,0.6f, 1.0f,0.6f
};

// Global bored state (set by main loop, read by mascot sleep functions)
extern bool globalBored;
extern float globalBoredEyeOffsetX;

// Draw yawn mouth for bored state
inline void drawBoredYawn(float t, float mouthX, float mouthY, float dy = 0) {
  if (!globalBored) return;
  float boredCycle = fmodf(t, 8.0f);
  if (boredCycle > 6.0f && boredCycle < 6.5f) {
    float openAmount = sinf((boredCycle - 6.0f) * PI * 2.0f);
    float mh = 1.0f + openAmount * 0.8f;
    gfx->fillRect(sx(mouthX), sy(mouthY, dy), sw(2.0f), sh(mh), RGB565(80, 60, 60));
  }
}

// Draw floating "z" particles (shared sleep element)
inline void drawZParticles(float t, float baseX = 11.8f, float baseY = 7.7f,
                           uint16_t baseColor = 0xFFFF) {
  for (int i = 0; i < 3; i++) {
    float period = 2.8f + i * 0.3f;
    float offset = i * 0.9f;
    float p = fmodf(t - offset, period);
    if (p < 0) p += period;
    p /= period;
    float baseOp = 0.70f - i * 0.10f;
    float opacity = (p < 0.8f) ? baseOp : (1.0f - p) * 3.5f * baseOp;
    if (opacity <= 0.05f) continue;
    float zx = baseX + i * 0.8f + sinf(p * PI * 2.0f) * 0.45f;
    float zy = baseY - p * 4.6f;
    int size = (p > 0.55f) ? 2 : 1;
    gfx->setTextColor(dim565(baseColor, opacity));
    gfx->setTextSize(size);
    gfx->setCursor(sx(zx), sy(zy));
    gfx->print("z");
  }
}

// Draw keyboard (shared work element)
inline void drawKeyboard(float t, uint16_t baseCol, uint16_t keyCol, uint16_t hiCol,
                         float y = 13.0f, float keyPeriod = 0.1f) {
  gfx->fillRect(sx(0.0f), sy(y), sw(15), sh(3), baseCol);
  int keyPhase = ((int)(t / keyPeriod)) % 6;
  for (int row = 0; row < 2; row++) {
    for (int col = 0; col < 6; col++) {
      float kx = 0.5f + col * 2.4f;
      float ky = y + 0.5f + row * 1.2f;
      gfx->fillRect(sx(kx), sy(ky), sw(1.8f), sh(0.7f), keyCol);
    }
  }
  int flashCol = keyPhase % 6;
  int flashRow = keyPhase / 3;
  gfx->fillRect(sx(0.5f + flashCol * 2.4f),
                sy(y + 0.5f + flashRow * 1.2f),
                sw(1.8f), sh(0.7f), hiCol);
}

// Global flag: when true, drawBang renders a "?" instead of "!"
static bool _questionMode = false;
static const uint16_t QUESTION_COLOR = RGB565(80, 160, 255);

// Draw question mark (shared question element — blue "?" instead of red "!")
inline void drawQuestionMark(float bangOp, float bangSc, float jumpY,
                              uint16_t questionCol, float baseY = 4.0f) {
  if (bangOp <= 0.05f) return;
  float bx = 12.5f;
  float by = baseY + jumpY * 0.15f;
  gfx->setTextSize(3);
  gfx->setTextColor(dim565(questionCol, bangOp));
  gfx->setCursor(sx(bx), sy(by));
  gfx->print("?");
}

// Draw exclamation bang (shared alert element)
inline void drawBang(float bangOp, float bangSc, float jumpY, float dy,
                     uint16_t alertCol, float baseY = 4.0f) {
  (void)dy;
  if (bangOp <= 0.05f) return;
  if (_questionMode) {
    drawQuestionMark(bangOp, bangSc, jumpY, QUESTION_COLOR, baseY);
    return;
  }
  float bx = 13.0f;
  float by = baseY + jumpY * 0.15f;
  float bw = 2.0f * bangSc;
  float bh1 = 3.5f * bangSc;
  float bh2 = 1.5f * bangSc;
  gfx->fillRect(sx(bx), sy(by), sw(bw), sh(bh1), alertCol);
  gfx->fillRect(sx(bx), sy(by + 4.0f * bangSc), sw(bw), sh(bh2), alertCol);
}

// Tool icon classification
enum ToolIcon { ICON_NONE, ICON_TERMINAL, ICON_FILE, ICON_WEB, ICON_AGENT, ICON_SEARCH };

inline ToolIcon classifyTool(const char* tool) {
  if (strcmp(tool, "Bash") == 0 || strcmp(tool, "Shell") == 0) return ICON_TERMINAL;
  if (strcmp(tool, "Read") == 0 || strcmp(tool, "Write") == 0 ||
      strcmp(tool, "Edit") == 0 || strcmp(tool, "Glob") == 0) return ICON_FILE;
  if (strcmp(tool, "WebSearch") == 0 || strcmp(tool, "WebFetch") == 0) return ICON_WEB;
  if (strcmp(tool, "Task") == 0 || strcmp(tool, "Agent") == 0) return ICON_AGENT;
  if (strcmp(tool, "Grep") == 0) return ICON_SEARCH;
  return ICON_NONE;
}

// 8x8 pixel icon bitmaps (stored in PROGMEM)
static const uint8_t ICON_TERMINAL_BMP[] PROGMEM = {
  0xFF, 0x81, 0xA1, 0x91, 0x89, 0x85, 0x81, 0xFF
};
static const uint8_t ICON_FILE_BMP[] PROGMEM = {
  0x3C, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x3C
};
static const uint8_t ICON_WEB_BMP[] PROGMEM = {
  0x3C, 0x42, 0xFF, 0x42, 0x42, 0xFF, 0x42, 0x3C
};
static const uint8_t ICON_AGENT_BMP[] PROGMEM = {
  0x3C, 0x42, 0xA5, 0x81, 0xA5, 0x99, 0x42, 0x3C
};
static const uint8_t ICON_SEARCH_BMP[] PROGMEM = {
  0x38, 0x44, 0x44, 0x44, 0x38, 0x0E, 0x07, 0x03
};

inline void drawToolIcon(ToolIcon icon, int px, int py, uint16_t color) {
  if (icon == ICON_NONE) return;
  const uint8_t* bmp = nullptr;
  switch (icon) {
    case ICON_TERMINAL: bmp = ICON_TERMINAL_BMP; break;
    case ICON_FILE:     bmp = ICON_FILE_BMP;     break;
    case ICON_WEB:      bmp = ICON_WEB_BMP;      break;
    case ICON_AGENT:    bmp = ICON_AGENT_BMP;    break;
    case ICON_SEARCH:   bmp = ICON_SEARCH_BMP;   break;
    default: return;
  }
  for (int row = 0; row < 8; row++) {
    uint8_t bits = pgm_read_byte(&bmp[row]);
    for (int col = 0; col < 8; col++) {
      if (bits & (0x80 >> col)) {
        gfx->drawPixel(px + col, py + row, color);
      }
    }
  }
}

// Subagent dots above mascot head
inline void drawSubagentDots(uint8_t count, float dy) {
  if (count == 0) return;
  uint8_t n = min(count, (uint8_t)5);
  float startX = 7.5f - n * 0.8f;
  for (uint8_t i = 0; i < n; i++) {
    gfx->fillCircle(sx(startX + i * 1.6f), sy(5.0f, dy), sw(0.4f),
                     RGB565(100, 220, 255));
  }
}

// Shadow helper
inline void drawShadow(float width, float jumpY = 0, float y = 15.0f,
                       float xBase = 3.0f, float baseWidth = 9.0f) {
  float sw_ = width * (1.0f - fabsf(fminf(0, jumpY)) * 0.04f);
  float op = fmaxf(0.08f, 0.40f - fabsf(fminf(0, jumpY)) * 0.04f);
  uint8_t sg = (uint8_t)(255.0f * op);
  gfx->fillRect(sx(xBase + (baseWidth - sw_)/2), sy(y), sw(sw_), sh(1), RGB565(sg, sg, sg));
}
