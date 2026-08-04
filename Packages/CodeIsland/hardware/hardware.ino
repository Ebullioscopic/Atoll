#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <SPI.h>
#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <pgmspace.h>
#include <Preferences.h>
#ifdef BUDDY_OTA_ENABLED
#include <WiFi.h>
#include <ArduinoOTA.h>
#endif

// =========================================================
//  Buddy — Multi-mascot Bluetooth Pet
//  Receives agent status over BLE, displays matching mascot
//  Button: short=next mascot, long=toggle demo mode
// =========================================================

// --- LCD pins (board-fixed) ---
#define TFT_MOSI 6
#define TFT_SCLK 7
#define TFT_CS   14
#define TFT_DC   15
#define TFT_RST  21
#define TFT_BL   22

// --- Button ---
#define BTN_PIN  9

// --- Display ---
#define BACKLIGHT_ACTIVE_HIGH true
#define LCD_W    172
#define LCD_H    320
#define LCD_ROT  0
#define DEBOUNCE_MS 30
#define LONG_PRESS_MS 600

// --- Backlight PWM (reduce heat) ---
#define BL_PWM_CHANNEL  0
#define BL_PWM_FREQ     5000
#define BL_PWM_BITS     8
#define BL_BRIGHT_ACTIVE  180   // 0-255, lower = cooler (default was 255)
#define BL_BRIGHT_SLEEP    80   // dimmer in sleep scene
#define BL_BRIGHT_IDLE     40   // very dim after idle timeout
#define BL_IDLE_TIMEOUT_MS 30000UL

// --- Frame rate control ---
#define FPS_ACTIVE  25
#define FPS_SLEEP   10
#define FRAME_MS_ACTIVE (1000 / FPS_ACTIVE)
#define FRAME_MS_SLEEP  (1000 / FPS_SLEEP)

Adafruit_ST7789 tft(TFT_CS, TFT_DC, TFT_RST);
GFXcanvas16 canvas(LCD_W, LCD_H);
GFXcanvas16* gfx = &canvas;

// --- BLE UUIDs ---
// Device name is generated at runtime as "Buddy-XXXXXX" using the lower
// 24 bits of the eFuse MAC, so multiple Buddies can be distinguished.
#define BLE_DEVICE_NAME_PREFIX "Buddy-"
#define BLE_DEVICE_NAME_LEN  16   // "Buddy-" + 6 hex + NUL + headroom
static char bleDeviceName[BLE_DEVICE_NAME_LEN] = "Buddy";
#define SERVICE_UUID         "0000beef-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID  "0000beef-0001-1000-8000-00805f9b34fb"
#define NOTIFY_CHAR_UUID     "0000beef-0002-1000-8000-00805f9b34fb"

// --- Buddy config frames ---
#define BUDDY_BRIGHTNESS_FRAME          0xFE
#define BUDDY_ORIENTATION_FRAME         0xFD
#define BUDDY_BRIGHTNESS_MIN_PERCENT    10
#define BUDDY_BRIGHTNESS_MAX_PERCENT    100
#define BUDDY_BRIGHTNESS_DEFAULT_PERCENT 70
#define BUDDY_SCREEN_UP                 0
#define BUDDY_SCREEN_DOWN               1

// --- Pairing protocol ---
#define PAIR_REQUEST_MARKER    0xE0
#define UNPAIR_MARKER          0xE1
#define PAIR_ACCEPTED_MARKER   0xE0
#define PAIR_REJECTED_MARKER   0xE1
#define PAIR_PENDING_MARKER    0xE2
#define HOST_ID_LENGTH         6
#define PAIR_CONFIRM_TIMEOUT_MS 30000UL
#define PAIR_REJECT_DELAY_MS   500UL
#define SUPER_LONG_PRESS_MS    3000

// QR code for https://github.com/wxtsky/CodeIsland (version 3, ECC M, border 2).
#define CODEISLAND_QR_SIZE 33
#define CODEISLAND_QR_SCALE 4
static const char CODEISLAND_QR[CODEISLAND_QR_SIZE][CODEISLAND_QR_SIZE + 1] PROGMEM = {
  "000000000000000000000000000000000",
  "000000000000000000000000000000000",
  "001111111011101101000110111111100",
  "001000001010010100000010100000100",
  "001011101001110000001110101110100",
  "001011101011100011010010101110100",
  "001011101001001011100100101110100",
  "001000001001110100110100100000100",
  "001111111010101010101010111111100",
  "000000000011111001111010000000000",
  "001011011101110101111010100101100",
  "000110100100110110110110111000100",
  "000100111011111100110001010011000",
  "001111000001000000101011101000100",
  "000001011111010011011010000110000",
  "001010110011111011100100100011100",
  "001000101010000100111110100011100",
  "000000010000001011100111111001000",
  "000011101101011011011110001101000",
  "000001000111010011000000010111000",
  "001010001110111111111010111010000",
  "000011000101110111011000111010000",
  "000111011001111110011011111110000",
  "000000000010001000111010001111100",
  "001111111011001010101110101101000",
  "001000001011011110101010001100100",
  "001011101001000000010011111010000",
  "001011101010001100110101011100100",
  "001011101011010100001010010010100",
  "001000001000010111101011010101000",
  "001111111010101100001111100001000",
  "000000000000000000000000000000000",
  "000000000000000000000000000000000",
};

// --- Agent state from BLE ---
volatile uint8_t  bleSourceId = 0;    // 0=claude, 1=codex, ...
volatile uint8_t  bleStatusId = 0;    // 0=idle, 1=processing, 2=running, 3=waitApproval, 4=waitQuestion
volatile bool     bleConnected = false;
volatile uint16_t bleConnId = 0;
volatile bool     bleConnIdValid = false;
volatile unsigned long lastBleData = 0;
volatile uint8_t  buddyBrightnessPercent = BUDDY_BRIGHTNESS_DEFAULT_PERCENT;
volatile uint8_t  buddyScreenOrientation = BUDDY_SCREEN_UP;
volatile bool     buddyOrientationDirty = false;
char              bleToolName[18] = {0};
char              bleWorkspaceName[20] = {0};
char              bleModelName[20] = {0};
BLECharacteristic* pNotifyChar = nullptr;
portMUX_TYPE      bleMux = portMUX_INITIALIZER_UNLOCKED;

// --- Session stats from BLE ---
uint8_t bleActiveSessionCount = 0;
uint8_t bleTotalSessionCount = 0;
uint16_t bleToolCallCount = 0;
uint8_t bleSessionDurationMin = 0;

// --- Subagent count ---
uint8_t bleSubagentCount = 0;

// --- Progress-aware animation ---
volatile unsigned long lastBleWriteTime = 0;
volatile unsigned long bleWriteInterval = 5000;

// --- Transient animation ---
enum TransientAnim { ANIM_NONE, ANIM_CELEBRATE, ANIM_FRUSTRATED };
TransientAnim pendingAnim = ANIM_NONE;
unsigned long animStartTime = 0;
#define ANIM_DURATION_MS 2000

// --- Tool history ---
#define MAX_TOOL_HISTORY 10
struct ToolHistEntry {
    char name[12];
    bool success;
};
ToolHistEntry toolHistory[MAX_TOOL_HISTORY];
uint8_t toolHistCount = 0;

// --- Activity heatmap ---
uint8_t heatmap[24] = {0};
uint8_t heatmapSlot = 0;
uint8_t bleCurrentHour = 255;
bool heatmapStatsBaselineReady = false;

// --- Global bored flag (checked by mascot sleep functions) ---
bool globalBored = false;
float globalBoredEyeOffsetX = 0.0f;

// --- Activity-based time scale for work animations ---
float globalWorkTimeScale = 1.0f;

// --- NVS persistence ---
Preferences prefs;
unsigned long lastNvsSave = 0;
volatile bool nvsDirty = false;
#define NVS_DEBOUNCE_MS 5000

#ifdef BUDDY_OTA_ENABLED
// --- OTA state ---
bool otaEnabled = false;
volatile bool otaPending = false;
char otaSsid[33] = {0};
char otaPassword[65] = {0};
#endif

// --- Dirty flags for partial screen refresh ---
volatile bool headerDirty = true;
volatile bool infoDirty = true;
// Track previous values for dirty detection
uint8_t prevSourceId = 0xFF;
uint8_t prevStatusId = 0xFF;
char prevToolName[18] = {0};
char prevWorkspaceName[20] = {0};

// --- Scenes ---
enum Scene { SCENE_SLEEP, SCENE_WORK, SCENE_ALERT, SCENE_QUESTION, SCENE_COUNT };

// --- App mode ---
enum AppMode { MODE_ONBOARD, MODE_DEMO, MODE_AGENT, MODE_PAIR_CONFIRM };
volatile AppMode appMode = MODE_ONBOARD;
bool hasEverConnected = false;

// --- Pairing state ---
// These are accessed from both BLE callbacks (may run on BLE task) and loop().
// Use volatile + bleMux for compound reads/writes.
volatile bool isPaired = false;
uint8_t pairedHostId[HOST_ID_LENGTH] = {0};
uint8_t pendingHostId[HOST_ID_LENGTH] = {0};
volatile unsigned long pairRequestTime = 0;
volatile bool pairRejectPending = false;
volatile unsigned long pairRejectTime = 0;
volatile bool pairAuthenticated = false;
bool superLongPressFired = false;

// --- Include all mascot headers ---
#include "mascot_common.h"
#include "mascot_clawd.h"
#include "mascot_dex.h"
#include "mascot_gemini.h"
#include "mascot_cursor.h"
#include "mascot_copilot.h"
#include "mascot_trae.h"
#include "mascot_qoder.h"
#include "mascot_droid.h"
#include "mascot_buddy.h"
#include "mascot_stepfun.h"
#include "mascot_opencode.h"
#include "mascot_qwen.h"
#include "mascot_antigrav.h"
#include "mascot_workbuddy.h"
#include "mascot_hermes.h"
#include "mascot_kimi.h"

// --- Mascot function pointer table ---
typedef void (*DrawFunc)(float t);

struct Mascot {
  DrawFunc sleep;
  DrawFunc work;
  DrawFunc alert;
  DrawFunc question;
  const char* name;
};

#define NUM_MASCOTS 16

Mascot mascots[NUM_MASCOTS] = {
  { clawdSleep,     clawdWork,     clawdAlert,     clawdQuestion,     "Claude"      },  // 0
  { dexSleep,       dexWork,       dexAlert,       dexQuestion,       "Codex"       },  // 1
  { geminiSleep,    geminiWork,    geminiAlert,    geminiQuestion,    "Gemini"      },  // 2
  { cursorSleep,    cursorWork,    cursorAlert,    cursorQuestion,    "Cursor"      },  // 3
  { copilotSleep,   copilotWork,   copilotAlert,   copilotQuestion,   "Copilot"     },  // 4
  { traeSleep,      traeWork,      traeAlert,      traeQuestion,      "Trae"        },  // 5
  { qoderSleep,     qoderWork,     qoderAlert,     qoderQuestion,     "Qoder"       },  // 6
  { droidSleep,     droidWork,     droidAlert,     droidQuestion,     "Factory"     },  // 7
  { buddySleep,     buddyWork,     buddyAlert,     buddyQuestion,     "CodeBuddy"   },  // 8
  { stepfunSleep,   stepfunWork,   stepfunAlert,   stepfunQuestion,   "StepFun"     },  // 9
  { opencodeSleep,  opencodeWork,  opencodeAlert,  opencodeQuestion,  "OpenCode"    },  // 10
  { qwenSleep,      qwenWork,      qwenAlert,      qwenQuestion,      "Qwen"        },  // 11
  { antigravSleep,  antigravWork,  antigravAlert,  antigravQuestion,  "AntiGravity" },  // 12
  { workbuddySleep, workbuddyWork, workbuddyAlert, workbuddyQuestion, "WorkBuddy"  },  // 13
  { hermesSleep,    hermesWork,    hermesAlert,    hermesQuestion,    "Hermes"      },  // 14
  { kimiSleep,      kimiWork,      kimiAlert,      kimiQuestion,      "Kimi"        },  // 15
};

// --- Mode ---
uint8_t currentMascotIdx = 0;
Scene currentScene = SCENE_SLEEP;
#define AUTO_CYCLE_MS 8000UL
#define BLE_TIMEOUT_MS 60000UL
unsigned long lastSceneChange = 0;
unsigned long lastInteraction = 0;
unsigned long lastFrameTime = 0;
uint8_t currentBrightness = BL_BRIGHT_ACTIVE;

// --- Logging ---
#define LOG_INTERVAL_MS 2000UL
unsigned long lastLogTime = 0;
unsigned long frameCount = 0;
unsigned long loopCount = 0;
unsigned long lastFpsCalcTime = 0;
float currentFps = 0;

static const char* sceneStr(Scene s) {
  switch (s) {
    case SCENE_SLEEP:    return "SLEEP";
    case SCENE_WORK:     return "WORK";
    case SCENE_ALERT:    return "ALERT";
    case SCENE_QUESTION: return "QUESTION";
    default:             return "?";
  }
}

static const char* appModeStr(AppMode m) {
  switch (m) {
    case MODE_ONBOARD:       return "ONBOARD";
    case MODE_DEMO:          return "DEMO";
    case MODE_AGENT:         return "AGENT";
    case MODE_PAIR_CONFIRM:  return "PAIR_CONFIRM";
    default:                 return "?";
  }
}

static const char* statusStr(uint8_t s) {
  switch (s) {
    case 0: return "idle";
    case 1: return "processing";
    case 2: return "running";
    case 3: return "waitApproval";
    case 4: return "waitQuestion";
    default: return "unknown";
  }
}

uint8_t clampBuddyBrightness(uint8_t percent) {
  if (percent < BUDDY_BRIGHTNESS_MIN_PERCENT) return BUDDY_BRIGHTNESS_MIN_PERCENT;
  if (percent > BUDDY_BRIGHTNESS_MAX_PERCENT) return BUDDY_BRIGHTNESS_MAX_PERCENT;
  return percent;
}

uint8_t clampBuddyOrientation(uint8_t orientation) {
  return orientation == BUDDY_SCREEN_DOWN ? BUDDY_SCREEN_DOWN : BUDDY_SCREEN_UP;
}

uint8_t tftRotationForBuddyOrientation(uint8_t orientation) {
  return orientation == BUDDY_SCREEN_DOWN ? (uint8_t)((LCD_ROT + 2) % 4) : LCD_ROT;
}

const char* buddyOrientationStr(uint8_t orientation) {
  return orientation == BUDDY_SCREEN_DOWN ? "down" : "up";
}

void applyBuddyScreenOrientation(uint8_t orientation) {
  uint8_t clamped = clampBuddyOrientation(orientation);
  tft.setRotation(tftRotationForBuddyOrientation(clamped));
  tft.fillScreen(0x0000);
}

uint8_t scaledBrightness(uint8_t base) {
  uint8_t percent = buddyBrightnessPercent;
  uint16_t scaled = (uint16_t)base * percent / BUDDY_BRIGHTNESS_DEFAULT_PERCENT;
  if (scaled > 255) return 255;
  if (scaled < 1) return 1;
  return (uint8_t)scaled;
}

uint8_t activeBrightness() {
  return scaledBrightness(BL_BRIGHT_ACTIVE);
}

uint8_t sleepBrightness() {
  return scaledBrightness(BL_BRIGHT_SLEEP);
}

uint8_t idleBrightness() {
  return scaledBrightness(BL_BRIGHT_IDLE);
}

void drawCenteredText(const char* text, int y, uint8_t textSize, uint16_t color) {
  gfx->setTextSize(textSize);
  gfx->setTextColor(color);
  int16_t tw = strlen(text) * 6 * textSize;
  gfx->setCursor((LCD_W - tw) / 2, y);
  gfx->print(text);
}

void drawCodeIslandQR(int x, int y, uint8_t scale) {
  int qrPixels = CODEISLAND_QR_SIZE * scale;
  gfx->fillRect(x - 4, y - 4, qrPixels + 8, qrPixels + 8, RGB565(245, 245, 245));
  for (int row = 0; row < CODEISLAND_QR_SIZE; row++) {
    for (int col = 0; col < CODEISLAND_QR_SIZE; col++) {
      char bit = (char)pgm_read_byte(&CODEISLAND_QR[row][col]);
      if (bit == '1') {
        gfx->fillRect(x + col * scale, y + row * scale, scale, scale, RGB565(10, 10, 14));
      }
    }
  }
}

// --- Button state ---
bool   btnStable   = HIGH;
bool   btnLastRead = HIGH;
unsigned long btnLastChange  = 0;
unsigned long btnPressStart  = 0;
bool   btnPressed  = false;
bool   btnLongFired = false;

int pollButton(unsigned long now) {
  bool raw = digitalRead(BTN_PIN);
  if (raw != btnLastRead) { btnLastRead = raw; btnLastChange = now; }
  if ((now - btnLastChange) < DEBOUNCE_MS) return 0;
  if (btnStable == btnLastRead) {
    if (btnPressed && !btnLongFired && (now - btnPressStart) >= LONG_PRESS_MS) {
      btnLongFired = true;
      return 2;
    }
    return 0;
  }
  btnStable = btnLastRead;
  if (btnStable == LOW) { btnPressed = true; btnLongFired = false; btnPressStart = now; return 0; }
  btnPressed = false;
  return btnLongFired ? 0 : 1;
}

static void rememberBleConnection(uint16_t connId) {
  portENTER_CRITICAL(&bleMux);
  bleConnId = connId;
  bleConnIdValid = true;
  portEXIT_CRITICAL(&bleMux);
}

static void clearBleConnection() {
  portENTER_CRITICAL(&bleMux);
  bleConnIdValid = false;
  portEXIT_CRITICAL(&bleMux);
}

static bool currentBleConnectionId(uint16_t* outConnId) {
  portENTER_CRITICAL(&bleMux);
  bool valid = bleConnIdValid;
  uint16_t connId = bleConnId;
  portEXIT_CRITICAL(&bleMux);
  if (!valid) return false;
  *outConnId = connId;
  return true;
}

static void disconnectCurrentClient(const char* reason) {
  uint16_t connId = 0;
  if (!currentBleConnectionId(&connId)) {
    Serial.printf("[BLE]  Cannot disconnect client (%s): no active connId\n", reason);
    return;
  }
  BLEServer* server = BLEDevice::getServer();
  if (!server) {
    Serial.printf("[BLE]  Cannot disconnect client (%s): server unavailable\n", reason);
    return;
  }
  server->disconnect(connId);
  Serial.printf("[BLE]  Disconnecting client (%s, connId=%u)\n", reason, connId);
}

// --- BLE Callbacks ---
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    rememberBleConnection(pServer->getConnId());
    bleConnected = true;
    pairAuthenticated = false;
    Serial.println("[BLE] Connected, waiting for pair handshake...");
  }
  void onDisconnect(BLEServer* pServer) override {
    bleConnected = false;
    clearBleConnection();
    pairAuthenticated = false;
    if (appMode == MODE_PAIR_CONFIRM) {
      appMode = MODE_ONBOARD;
      Serial.println("[BLE] Disconnected during pairing, back to ONBOARD");
    }
    Serial.println("[BLE] Disconnected, re-advertising...");
    BLEDevice::startAdvertising();
  }
#if defined(CONFIG_BLUEDROID_ENABLED)
  void onConnect(BLEServer* pServer, esp_ble_gatts_cb_param_t* param) override {
    rememberBleConnection(param->connect.conn_id);
  }
  void onDisconnect(BLEServer* pServer, esp_ble_gatts_cb_param_t* param) override {
    clearBleConnection();
  }
#endif
};

// --- Pairing helpers (called from BLE callback context) ---
static void sendPairNotify(uint8_t marker) {
  if (pNotifyChar) {
    pNotifyChar->setValue(&marker, 1);
    pNotifyChar->notify();
  }
}

static void savePairedHost(const uint8_t* hostId) {
  memcpy(pairedHostId, hostId, HOST_ID_LENGTH);
  isPaired = true;
  prefs.putBytes("ph", pairedHostId, HOST_ID_LENGTH);
  prefs.putBool("ps", true);
  Serial.printf("[PAIR] Saved paired host: %02X%02X%02X%02X%02X%02X\n",
    pairedHostId[0], pairedHostId[1], pairedHostId[2],
    pairedHostId[3], pairedHostId[4], pairedHostId[5]);
}

static void clearPairedHost() {
  memset(pairedHostId, 0, HOST_ID_LENGTH);
  isPaired = false;
  prefs.remove("ph");
  prefs.putBool("ps", false);
  Serial.println("[PAIR] Cleared paired host");
}

static bool hostIdMatches(const uint8_t* a, const uint8_t* b) {
  return memcmp(a, b, HOST_ID_LENGTH) == 0;
}

class CharCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    uint8_t* data = pChar->getData();
    size_t len = pChar->getLength();
    Serial.printf("[BLE] Write received, len=%d, raw hex:", len);
    for (size_t i = 0; i < len && i < 24; i++) Serial.printf(" %02X", data[i]);
    Serial.println();

    // --- Pair Request (0xE0) — always processed regardless of auth state ---
    if (len >= 1 + HOST_ID_LENGTH && data[0] == PAIR_REQUEST_MARKER) {
      uint8_t incomingId[HOST_ID_LENGTH];
      memcpy(incomingId, data + 1, HOST_ID_LENGTH);
      Serial.printf("[PAIR] Request from host: %02X%02X%02X%02X%02X%02X\n",
        incomingId[0], incomingId[1], incomingId[2],
        incomingId[3], incomingId[4], incomingId[5]);

      portENTER_CRITICAL(&bleMux);
      bool localIsPaired = isPaired;
      bool hostMatch = localIsPaired && hostIdMatches(pairedHostId, incomingId);
      bool alreadyConfirming = (appMode == MODE_PAIR_CONFIRM);
      portEXIT_CRITICAL(&bleMux);

      if (hostMatch) {
        portENTER_CRITICAL(&bleMux);
        pairAuthenticated = true;
        hasEverConnected = true;
        appMode = MODE_AGENT;
        lastBleData = millis();
        portEXIT_CRITICAL(&bleMux);
        sendPairNotify(PAIR_ACCEPTED_MARKER);
        Serial.println("[PAIR] Accepted (known host)");
      } else if (!localIsPaired && !alreadyConfirming) {
        portENTER_CRITICAL(&bleMux);
        memcpy(pendingHostId, incomingId, HOST_ID_LENGTH);
        pairRequestTime = millis();
        appMode = MODE_PAIR_CONFIRM;
        portEXIT_CRITICAL(&bleMux);
        sendPairNotify(PAIR_PENDING_MARKER);
        Serial.println("[PAIR] Pending — waiting for button confirmation");
      } else if (!localIsPaired && alreadyConfirming) {
        sendPairNotify(PAIR_REJECTED_MARKER);
        pairRejectPending = true;
        pairRejectTime = millis();
        Serial.println("[PAIR] Rejected (already confirming another host)");
      } else {
        sendPairNotify(PAIR_REJECTED_MARKER);
        pairRejectPending = true;
        pairRejectTime = millis();
        Serial.println("[PAIR] Rejected (already paired to different host)");
      }
      return;
    }

    // --- Unpair (0xE1) — always processed regardless of auth state ---
    if (len >= 1 + HOST_ID_LENGTH && data[0] == UNPAIR_MARKER) {
      uint8_t incomingId[HOST_ID_LENGTH];
      memcpy(incomingId, data + 1, HOST_ID_LENGTH);
      Serial.printf("[PAIR] Unpair from host: %02X%02X%02X%02X%02X%02X\n",
        incomingId[0], incomingId[1], incomingId[2],
        incomingId[3], incomingId[4], incomingId[5]);

      portENTER_CRITICAL(&bleMux);
      bool shouldUnpair = isPaired && hostIdMatches(pairedHostId, incomingId);
      portEXIT_CRITICAL(&bleMux);

      if (shouldUnpair) {
        clearPairedHost();
        portENTER_CRITICAL(&bleMux);
        pairAuthenticated = false;
        appMode = MODE_ONBOARD;
        portEXIT_CRITICAL(&bleMux);
        Serial.println("[PAIR] Unpaired successfully");
      } else {
        Serial.println("[PAIR] Unpair ignored (host mismatch or not paired)");
      }
      return;
    }

    // --- All other frames require successful pairing ---
    if (!pairAuthenticated) {
      Serial.println("[BLE] WARN: data frame rejected (not paired/authenticated)");
      return;
    }

    if (len == 2 && data[0] == BUDDY_BRIGHTNESS_FRAME) {
      uint8_t percent = clampBuddyBrightness(data[1]);
      portENTER_CRITICAL(&bleMux);
      buddyBrightnessPercent = percent;
      nvsDirty = true;
      portEXIT_CRITICAL(&bleMux);
      lastInteraction = millis();
      Serial.printf("[BLE] Brightness config: %d%%\n", percent);
      return;
    }

    if (len == 2 && data[0] == BUDDY_ORIENTATION_FRAME) {
      uint8_t orientation = clampBuddyOrientation(data[1]);
      portENTER_CRITICAL(&bleMux);
      if (buddyScreenOrientation != orientation) {
        buddyScreenOrientation = orientation;
        buddyOrientationDirty = true;
        nvsDirty = true;
      }
      portEXIT_CRITICAL(&bleMux);
      lastInteraction = millis();
      Serial.printf("[BLE] Screen orientation config: %s\n", buddyOrientationStr(orientation));
      return;
    }

    // Workspace frame (0xFC)
    if (len >= 2 && data[0] == 0xFC) {
      uint8_t wsLen = data[1];
      if (wsLen > 18) wsLen = 18;
      portENTER_CRITICAL(&bleMux);
      memset(bleWorkspaceName, 0, sizeof(bleWorkspaceName));
      if (wsLen > 0 && len >= 2u + wsLen) {
        memcpy(bleWorkspaceName, data + 2, wsLen);
      }
      bleWorkspaceName[wsLen] = '\0';
      lastBleData = millis();
      portEXIT_CRITICAL(&bleMux);
      infoDirty = true;
      Serial.printf("[BLE] Workspace: \"%s\"\n", bleWorkspaceName);
      return;
    }

    // Model info frame (0xF9)
    if (len >= 2 && data[0] == 0xF9) {
      uint8_t mLen = data[1];
      if (mLen > 18) mLen = 18;
      portENTER_CRITICAL(&bleMux);
      memset(bleModelName, 0, sizeof(bleModelName));
      if (mLen > 0 && len >= 2u + mLen) memcpy(bleModelName, data + 2, mLen);
      headerDirty = true;
      lastBleData = millis();
      portEXIT_CRITICAL(&bleMux);
      Serial.printf("[BLE] Model: \"%s\"\n", bleModelName);
      return;
    }

    // Session stats frame (0xFA)
    if (len >= 6 && data[0] == 0xFA) {
      uint8_t loggedActiveSessions;
      uint8_t loggedTotalSessions;
      uint16_t loggedToolCount;
      uint8_t loggedDuration;
      portENTER_CRITICAL(&bleMux);
      bleActiveSessionCount = data[1];
      bleTotalSessionCount = data[2];
      uint16_t newToolCount = ((uint16_t)data[3] << 8) | data[4];
      if (!heatmapStatsBaselineReady || bleCurrentHour == 255 || newToolCount < bleToolCallCount) {
        heatmapStatsBaselineReady = true;
      } else if (newToolCount > bleToolCallCount) {
        uint16_t delta = newToolCount - bleToolCallCount;
        uint16_t newVal = heatmap[heatmapSlot] + delta;
        heatmap[heatmapSlot] = (newVal > 255) ? 255 : (uint8_t)newVal;
      }
      bleToolCallCount = newToolCount;
      bleSessionDurationMin = data[5];
      lastBleData = millis();
      loggedActiveSessions = bleActiveSessionCount;
      loggedTotalSessions = bleTotalSessionCount;
      loggedToolCount = bleToolCallCount;
      loggedDuration = bleSessionDurationMin;
      portEXIT_CRITICAL(&bleMux);
      Serial.printf("[BLE] Stats: sessions=%d/%d tools=%d duration=%dm\n",
        loggedActiveSessions, loggedTotalSessions, loggedToolCount, loggedDuration);
      return;
    }

    // Subagent count frame (0xF8)
    if (len >= 2 && data[0] == 0xF8) {
      portENTER_CRITICAL(&bleMux);
      bleSubagentCount = data[1];
      lastBleData = millis();
      portEXIT_CRITICAL(&bleMux);
      Serial.printf("[BLE] Subagents: %d\n", bleSubagentCount);
      return;
    }

    // Event frame (0xF7) — transient animations
    if (len >= 2 && data[0] == 0xF7) {
      uint8_t eventId = data[1];
      portENTER_CRITICAL(&bleMux);
      lastBleData = millis();
      if (eventId == 1) { pendingAnim = ANIM_CELEBRATE; animStartTime = millis(); }
      else if (eventId == 2) { pendingAnim = ANIM_FRUSTRATED; animStartTime = millis(); }
      portEXIT_CRITICAL(&bleMux);
      Serial.printf("[BLE] Event: %d\n", eventId);
      return;
    }

    // Time hint frame (0xF6)
    if (len >= 2 && data[0] == 0xF6) {
      uint8_t newHour = data[1];
      uint8_t loggedHour;
      portENTER_CRITICAL(&bleMux);
      if (bleCurrentHour != 255 && newHour != bleCurrentHour) {
        heatmapSlot = newHour % 24;
        heatmap[heatmapSlot] = 0;
      } else if (bleCurrentHour == 255) {
        heatmapSlot = newHour % 24;
      }
      bleCurrentHour = newHour;
      lastBleData = millis();
      loggedHour = bleCurrentHour;
      portEXIT_CRITICAL(&bleMux);
      Serial.printf("[BLE] Hour: %d\n", loggedHour);
      return;
    }

#ifdef BUDDY_OTA_ENABLED
    // OTA SSID frame (0xF4)
    if (len >= 2 && data[0] == 0xF4) {
      uint8_t ssidLen = data[1];
      if (ssidLen > 31) ssidLen = 31;
      memset(otaSsid, 0, sizeof(otaSsid));
      if (ssidLen > 0 && len >= 2u + ssidLen) {
        memcpy(otaSsid, data + 2, ssidLen);
      }
      lastBleData = millis();
      #ifdef DEBUG
      Serial.printf("[BLE] OTA SSID: \"%s\"\n", otaSsid);
      #else
      Serial.println("[BLE] OTA SSID received");
      #endif
      return;
    }

    // OTA Password frame (0xF3)
    if (len >= 3 && data[0] == 0xF3) {
      uint8_t chunkIdx = data[1];
      uint8_t chunkLen = data[2];
      if (chunkLen > 17) chunkLen = 17;
      if (chunkIdx == 0) memset(otaPassword, 0, sizeof(otaPassword));
      size_t curLen = strlen(otaPassword);
      if (curLen + chunkLen < sizeof(otaPassword) - 1 && len >= 3u + chunkLen) {
        memcpy(otaPassword + curLen, data + 3, chunkLen);
        otaPassword[curLen + chunkLen] = '\0';
      }
      lastBleData = millis();
      #ifdef DEBUG
      Serial.printf("[BLE] OTA password chunk %d (%d bytes, total=%zu)\n", chunkIdx, chunkLen, strlen(otaPassword));
      #endif
      if (otaSsid[0] != '\0' && otaPassword[0] != '\0' && !otaEnabled) {
        otaPending = true;
      }
      return;
    }
#endif

    // Message preview frame (0xFB)
    if (len >= 4 && data[0] == 0xFB) {
      uint8_t msgIdx = data[1];
      uint8_t msgTotal = data[2];
      portENTER_CRITICAL(&bleMux);
      lastBleData = millis();
      portEXIT_CRITICAL(&bleMux);
      Serial.printf("[BLE] MsgPreview: idx=%d/%d\n", msgIdx, msgTotal);
      return;
    }

    // Tool history frame (0xF5)
    if (len >= 3 && data[0] == 0xF5) {
      uint8_t entryIdx = data[1];
      uint8_t flagsByte = data[2];
      bool success = (flagsByte & 0x80) != 0;
      uint8_t nameLen = flagsByte & 0x7F;
      if (nameLen > 11) nameLen = 11;
      portENTER_CRITICAL(&bleMux);
      if (entryIdx == 0) toolHistCount = 0;
      if (entryIdx == 0 && nameLen == 0) {
        lastBleData = millis();
        portEXIT_CRITICAL(&bleMux);
        Serial.println("[BLE] Tool history cleared");
        return;
      }
      if (toolHistCount < MAX_TOOL_HISTORY) {
        ToolHistEntry& entry = toolHistory[toolHistCount];
        memset(entry.name, 0, sizeof(entry.name));
        if (nameLen > 0 && len >= 3u + nameLen) {
          memcpy(entry.name, data + 3, nameLen);
        }
        entry.success = success;
        toolHistCount++;
      }
      lastBleData = millis();
      portEXIT_CRITICAL(&bleMux);
      return;
    }

    if (len < 3) {
      Serial.println("[BLE] WARN: payload too short (<3), ignored");
      return;
    }

    portENTER_CRITICAL(&bleMux);
    if (bleSourceId != data[0]) headerDirty = true;
    if (bleStatusId != data[1]) infoDirty = true;
    bleSourceId = data[0];
    bleStatusId = data[1];
    uint8_t toolLen = data[2];
    if (toolLen > 17) toolLen = 17;
    memset(bleToolName, 0, sizeof(bleToolName));
    if (toolLen > 0 && len >= 3u + toolLen) {
      memcpy(bleToolName, data + 3, toolLen);
    }
    bleToolName[toolLen] = '\0';
    lastBleData = millis();
    appMode = MODE_AGENT;
    unsigned long now_write = millis();
    if (lastBleWriteTime > 0) {
      bleWriteInterval = now_write - lastBleWriteTime;
    }
    lastBleWriteTime = now_write;
    portEXIT_CRITICAL(&bleMux);

    const char* srcName = (bleSourceId < NUM_MASCOTS) ? mascots[bleSourceId].name : "?";
    Serial.printf("[BLE] Parsed: source=%d(%s) status=%d(%s) tool=\"%s\"\n",
      bleSourceId, srcName, bleStatusId, statusStr(bleStatusId), bleToolName);
  }
};

// --- Map BLE status to scene ---
Scene statusToScene(uint8_t status) {
  switch (status) {
    case 0: return SCENE_SLEEP;       // idle
    case 1: return SCENE_WORK;        // processing
    case 2: return SCENE_WORK;        // running
    case 3: return SCENE_ALERT;       // waitingApproval
    case 4: return SCENE_QUESTION;    // waitingQuestion
    default: return SCENE_SLEEP;
  }
}

// --- Draw tool name label ---
void drawToolLabel(int baseY = 240) {
  char localTool[18];
  uint8_t localStatus;
  portENTER_CRITICAL(&bleMux);
  memcpy(localTool, bleToolName, sizeof(localTool));
  localStatus = bleStatusId;
  portEXIT_CRITICAL(&bleMux);
  if (localTool[0] == '\0') return;
  if (localStatus < 1 || localStatus > 4) return;

  ToolIcon icon = classifyTool(localTool);
  int16_t tw = strlen(localTool) * 12;
  int16_t totalW = tw + (icon != ICON_NONE ? 12 : 0);
  int16_t startX = (LCD_W - totalW) / 2;

  if (icon != ICON_NONE) {
    drawToolIcon(icon, startX, baseY + 2, RGB565(80, 180, 220));
    startX += 12;
  }

  gfx->setTextColor(RGB565(120, 120, 130));
  gfx->setTextSize(2);
  gfx->setCursor(startX, baseY);
  gfx->print(localTool);
}

// --- Draw mascot name label (header area) ---
void drawMascotName(uint8_t idx) {
  if (idx >= NUM_MASCOTS) return;
  const char* name = mascots[idx].name;

  char localModel[20];
  portENTER_CRITICAL(&bleMux);
  memcpy(localModel, bleModelName, sizeof(localModel));
  portEXIT_CRITICAL(&bleMux);

  if (localModel[0] != '\0') {
    char headerBuf[40];
    snprintf(headerBuf, sizeof(headerBuf), "%s · %s", name, localModel);
    int16_t tw = strlen(headerBuf) * 6;
    gfx->setTextSize(1);
    gfx->setTextColor(RGB565(160, 160, 170));
    gfx->setCursor((LCD_W - tw) / 2, 8);
    gfx->print(headerBuf);
  } else {
    gfx->setTextSize(2);
    int16_t tw = strlen(name) * 12;
    gfx->setTextColor(RGB565(160, 160, 170));
    gfx->setCursor((LCD_W - tw) / 2, 6);
    gfx->print(name);
  }
}

// --- Draw workspace label ---
void drawWorkspaceLabel(int baseY = 224) {
  char localWs[20];
  portENTER_CRITICAL(&bleMux);
  memcpy(localWs, bleWorkspaceName, sizeof(localWs));
  portEXIT_CRITICAL(&bleMux);
  if (localWs[0] == '\0') return;
  gfx->setTextColor(RGB565(80, 180, 220));
  gfx->setTextSize(1);
  int16_t tw = strlen(localWs) * 6;
  gfx->setCursor((LCD_W - tw) / 2, baseY);
  gfx->print(localWs);
}

// --- Draw action hints for Alert/Question scenes (y=300) ---
void drawAlertActionHints(uint8_t status) {
  if (status == 3) {
    drawCenteredText("Press: Allow", LCD_H - 18, 1, RGB565(50, 200, 50));
    drawCenteredText("Hold:  Deny",  LCD_H - 8,  1, RGB565(200, 60, 60));
  } else if (status == 4) {
    drawCenteredText("Press: Open", LCD_H - 18, 1, RGB565(80, 180, 255));
    drawCenteredText("Hold:  Skip", LCD_H - 8,  1, RGB565(150, 150, 160));
  }
}

// --- Draw session stats panel (shown during idle, below workspace) ---
void drawStatsPanel() {
  uint8_t actS, totS, durM;
  uint16_t toolC;
  portENTER_CRITICAL(&bleMux);
  actS = bleActiveSessionCount;
  totS = bleTotalSessionCount;
  toolC = bleToolCallCount;
  durM = bleSessionDurationMin;
  portEXIT_CRITICAL(&bleMux);

  if (actS == 0 && totS == 0 && toolC == 0) return;

  int panelY = 236;
  char buf[32];
  gfx->setTextSize(1);
  gfx->setTextColor(RGB565(100, 100, 120));

  snprintf(buf, sizeof(buf), "S:%d/%d  T:%d  %dm", actS, totS, toolC, durM);
  int16_t tw = strlen(buf) * 6;
  gfx->setCursor((LCD_W - tw) / 2, panelY);
  gfx->print(buf);
}

// --- Draw tool history timeline (shown during idle, below stats) ---
void drawToolTimeline() {
  if (toolHistCount == 0) return;
  int startY = 248;
  gfx->setTextSize(1);
  uint8_t localCount;
  ToolHistEntry localHist[MAX_TOOL_HISTORY];
  portENTER_CRITICAL(&bleMux);
  localCount = toolHistCount;
  memcpy(localHist, toolHistory, sizeof(localHist));
  portEXIT_CRITICAL(&bleMux);

  uint8_t maxVisible = min(localCount, (uint8_t)5);
  for (uint8_t i = 0; i < maxVisible; i++) {
    int y = startY + i * 10;
    uint16_t markCol = localHist[i].success ? RGB565(50, 200, 50) : RGB565(200, 60, 60);
    gfx->fillRect(14, y + 2, 3, 3, markCol);
    gfx->setTextColor(RGB565(120, 120, 140));
    gfx->setCursor(22, y);
    gfx->print(localHist[i].name);
  }
}

// --- Draw heatmap bar (24h activity, bottom of idle screen) ---
void drawHeatmapBar() {
  uint8_t localHeatmap[24];
  uint8_t localSlot;
  portENTER_CRITICAL(&bleMux);
  memcpy(localHeatmap, heatmap, sizeof(localHeatmap));
  localSlot = heatmapSlot;
  portEXIT_CRITICAL(&bleMux);

  bool hasData = false;
  for (int i = 0; i < 24; i++) { if (localHeatmap[i] > 0) { hasData = true; break; } }
  if (!hasData) return;

  int barY = LCD_H - 24;
  int slotW = (LCD_W - 4) / 24;
  for (int i = 0; i < 24; i++) {
    uint8_t val = localHeatmap[(localSlot + 1 + i) % 24];
    float intensity = val / 255.0f;
    uint8_t r = (uint8_t)(20 + intensity * 30);
    uint8_t g = (uint8_t)(40 + intensity * 200);
    uint8_t b = (uint8_t)(80 + intensity * 50);
    gfx->fillRect(2 + i * slotW, barY, slotW - 1, 8, RGB565(r, g, b));
  }
}

// --- Draw celebration animation ---
void drawCelebration(float t, uint8_t mascotIdx, unsigned long animationStartTime) {
  float elapsed = (millis() - animationStartTime) / 1000.0f;
  mascots[mascotIdx].work(t);
  for (int i = 0; i < 5; i++) {
    float px = 3.0f + i * 2.5f + sinf(elapsed * 3 + i) * 1.5f;
    float py = 4.0f - elapsed * 3.0f + i * 0.5f;
    float op = fmaxf(0, 1.0f - elapsed * 0.5f);
    gfx->fillRect(sx(px), sy(py), sw(1), sh(1), dim565(RGB565(255, 220, 50), op));
  }
  drawCenteredText("Done!", LCD_H - 30, 2, dim565(RGB565(50, 230, 50), fmaxf(0, 1.0f - elapsed * 0.4f)));
}

// --- Draw frustrated animation ---
void drawFrustrated(float t, uint8_t mascotIdx, unsigned long animationStartTime) {
  float elapsed = (millis() - animationStartTime) / 1000.0f;
  float shakeX = sinf(elapsed * 30.0f) * (1.0f - elapsed * 0.5f) * 2.0f;
  setViewportShiftX(shakeX);
  mascots[mascotIdx].work(t);
  setViewportShiftX(0.0f);
  float op = fmaxf(0, 1.0f - elapsed * 0.5f);
  gfx->setTextSize(3);
  gfx->setTextColor(dim565(RGB565(255, 60, 60), op));
  gfx->setCursor(sx(12.0f), sy(4.0f));
  gfx->print("X");
}

// --- Draw connection status ---
void drawStatusBar() {
  uint16_t col = bleConnected ? RGB565(50, 230, 50) : RGB565(100, 100, 100);
  gfx->fillRect(LCD_W / 2 - 3, 0, 6, 3, col);
  if (appMode == MODE_DEMO) {
    gfx->setTextColor(RGB565(60, 60, 70));
    gfx->setTextSize(1);
    gfx->setCursor(2, 0);
    gfx->print("DEMO");
  }
}

// --- Draw pair confirmation screen ---
void drawPairConfirmScreen(float t) {
  drawCenteredText("Pair?", 40, 3, RGB565(235, 235, 245));

  char hostHex[18];
  snprintf(hostHex, sizeof(hostHex), "%02X%02X%02X-%02X%02X%02X",
    pendingHostId[0], pendingHostId[1], pendingHostId[2],
    pendingHostId[3], pendingHostId[4], pendingHostId[5]);
  drawCenteredText(hostHex, 80, 1, RGB565(120, 200, 255));

  float pulse = (sinf(t * 2.5f) + 1.0f) * 0.5f;
  uint8_t g = 140 + (uint8_t)(pulse * 60);
  drawCenteredText("Press BOOT", 140, 2, RGB565(50, (uint8_t)g, 50));
  drawCenteredText("to accept", 162, 2, RGB565(50, (uint8_t)g, 50));

  drawCenteredText("Hold BOOT", 210, 1, RGB565(180, 80, 80));
  drawCenteredText("to reject", 224, 1, RGB565(180, 80, 80));

  unsigned long elapsed = millis() - pairRequestTime;
  unsigned long remaining = 0;
  if (elapsed < PAIR_CONFIRM_TIMEOUT_MS) {
    remaining = (PAIR_CONFIRM_TIMEOUT_MS - elapsed) / 1000;
  }
  char timeBuf[8];
  snprintf(timeBuf, sizeof(timeBuf), "%lus", remaining);
  drawCenteredText(timeBuf, LCD_H - 30, 2, RGB565(100, 100, 120));
}

// --- Draw onboarding screen ---
void drawOnboardScreen(float t) {
  drawCenteredText("Buddy", 22, 3, RGB565(235, 235, 245));
  drawCenteredText(bleDeviceName, 50, 1, RGB565(120, 200, 255));
  drawCenteredText("Scan to get app", 64, 1, RGB565(130, 130, 150));

  int qrPixels = CODEISLAND_QR_SIZE * CODEISLAND_QR_SCALE;
  int qrX = (LCD_W - qrPixels) / 2;
  int qrY = 84;
  drawCodeIslandQR(qrX, qrY, CODEISLAND_QR_SCALE);

  int y = qrY + qrPixels + 16;
  drawCenteredText("Open CodeIsland", y, 1, RGB565(170, 170, 190));
  drawCenteredText("Settings > Buddy", y + 14, 1, RGB565(120, 200, 255));
  drawCenteredText("Connect by Bluetooth", y + 28, 1, RGB565(130, 130, 150));

  y += 50;
  if (bleConnected) {
    drawCenteredText("Bluetooth connected", y, 1, RGB565(50, 230, 50));
  } else {
    float pulse = (sinf(t * 3.0f) + 1.0f) * 0.5f;
    uint8_t g = 80 + (uint8_t)(pulse * 80);
    drawCenteredText("Waiting for Buddy...", y, 1, RGB565(g, g, (uint8_t)(g + 30)));
  }

  if (isPaired) {
    drawCenteredText("Paired", y + 14, 1, RGB565(80, 200, 80));
    drawCenteredText("Hold 3s: unpair", LCD_H - 18, 1, RGB565(60, 60, 80));
  } else {
    drawCenteredText("Long press: demo", LCD_H - 18, 1, RGB565(60, 60, 80));
  }
}

// ============================================================
//  Setup
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println();
  Serial.println("========================================");
  Serial.println("  Buddy — Multi-mascot Bluetooth Pet");
  Serial.println("========================================");

  // NVS — restore persisted settings
  prefs.begin("buddy", false);
  buddyBrightnessPercent = prefs.getUChar("bright", BUDDY_BRIGHTNESS_DEFAULT_PERCENT);
  buddyScreenOrientation = prefs.getUChar("orient", BUDDY_SCREEN_UP);
  Serial.printf("[NVS]  Restored brightness=%d%% orientation=%s\n",
    buddyBrightnessPercent, buddyOrientationStr(buddyScreenOrientation));

  // NVS — restore pairing state
  isPaired = prefs.getBool("ps", false);
  if (isPaired) {
    size_t readLen = prefs.getBytes("ph", pairedHostId, HOST_ID_LENGTH);
    if (readLen != HOST_ID_LENGTH) {
      memset(pairedHostId, 0, HOST_ID_LENGTH);
      isPaired = false;
    }
  }
  Serial.printf("[NVS]  Pairing: %s", isPaired ? "paired to " : "not paired\n");
  if (isPaired) {
    Serial.printf("%02X%02X%02X%02X%02X%02X\n",
      pairedHostId[0], pairedHostId[1], pairedHostId[2],
      pairedHostId[3], pairedHostId[4], pairedHostId[5]);
  }
  Serial.printf("[BOOT] Chip: %s  Rev: %d  Cores: %d\n",
    ESP.getChipModel(), ESP.getChipRevision(), ESP.getChipCores());
  Serial.printf("[BOOT] CPU freq: %d MHz\n", ESP.getCpuFreqMHz());
  Serial.printf("[BOOT] Free heap: %d bytes\n", ESP.getFreeHeap());
  Serial.printf("[BOOT] Flash: %d KB  Speed: %d MHz\n",
    ESP.getFlashChipSize() / 1024, ESP.getFlashChipSpeed() / 1000000);

  // LCD — PWM backlight for heat reduction
  Serial.println("[LCD]  Initializing...");
  Serial.printf("[LCD]  Pins: MOSI=%d SCLK=%d CS=%d DC=%d RST=%d BL=%d\n",
    TFT_MOSI, TFT_SCLK, TFT_CS, TFT_DC, TFT_RST, TFT_BL);
  Serial.printf("[LCD]  Size: %dx%d  Rotation: %d (%s)\n",
    LCD_W, LCD_H, tftRotationForBuddyOrientation(buddyScreenOrientation),
    buddyOrientationStr(buddyScreenOrientation));
  ledcAttach(TFT_BL, BL_PWM_FREQ, BL_PWM_BITS);
  currentBrightness = activeBrightness();
  ledcWrite(TFT_BL, currentBrightness);
  Serial.printf("[LCD]  Backlight PWM: freq=%dHz bits=%d brightness=%d/255 (%d%%)\n",
    BL_PWM_FREQ, BL_PWM_BITS, currentBrightness, buddyBrightnessPercent);
  pinMode(BTN_PIN, INPUT_PULLUP);
  Serial.printf("[BTN]  Pin=%d (INPUT_PULLUP)\n", BTN_PIN);
  SPI.begin(TFT_SCLK, -1, TFT_MOSI, TFT_CS);
  tft.init(LCD_W, LCD_H);
  applyBuddyScreenOrientation(buddyScreenOrientation);
  Serial.printf("[LCD]  Canvas buffer: %d bytes\n", LCD_W * LCD_H * 2);
  Serial.println("[LCD]  OK");

  // BLE — derive a unique name from the eFuse MAC so multiple Buddies
  // can co-exist and be distinguished from the macOS app.
  uint64_t mac = ESP.getEfuseMac();
  uint32_t suffix = (uint32_t)(mac & 0xFFFFFFULL);
  snprintf(bleDeviceName, BLE_DEVICE_NAME_LEN,
           BLE_DEVICE_NAME_PREFIX "%06X", (unsigned int)suffix);
  Serial.printf("[BLE]  Device name: %s\n", bleDeviceName);
  Serial.println("[BLE]  Initializing...");
  BLEDevice::init(bleDeviceName);
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  BLECharacteristic* pChar = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pChar->setCallbacks(new CharCallbacks());

  pNotifyChar = pService->createCharacteristic(
    NOTIFY_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pNotifyChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  Serial.printf("[BLE]  Service UUID: %s\n", SERVICE_UUID);
  Serial.printf("[BLE]  Write UUID:   %s\n", CHARACTERISTIC_UUID);
  Serial.printf("[BLE]  Notify UUID:  %s\n", NOTIFY_CHAR_UUID);
  Serial.printf("[BLE]  Advertising as: %s\n", bleDeviceName);

  Serial.printf("[MASCOT] Loaded %d mascots:", NUM_MASCOTS);
  for (int i = 0; i < NUM_MASCOTS; i++) Serial.printf(" %s", mascots[i].name);
  Serial.println();

  Serial.printf("[CFG]  FPS active=%d sleep=%d\n", FPS_ACTIVE, FPS_SLEEP);
  Serial.printf("[CFG]  Backlight active=%d sleep=%d idle=%d brightness=%d%%  idle_timeout=%lums\n",
    activeBrightness(), sleepBrightness(), idleBrightness(), buddyBrightnessPercent, BL_IDLE_TIMEOUT_MS);
  Serial.printf("[CFG]  Auto-cycle=%lums  BLE timeout=%lums\n", AUTO_CYCLE_MS, BLE_TIMEOUT_MS);

  lastSceneChange = millis();
  lastInteraction = millis();
  lastFrameTime = millis();
  lastFpsCalcTime = millis();

  Serial.printf("[BOOT] Setup complete, free heap: %d bytes\n", ESP.getFreeHeap());
  Serial.println("========================================");
  Serial.println("[LOOP] Starting main loop...");
}

// ============================================================
//  Loop
// ============================================================
void loop() {
  unsigned long now = millis();
  loopCount++;

  bool shouldApplyOrientation = false;
  uint8_t localOrientation = BUDDY_SCREEN_UP;
  portENTER_CRITICAL(&bleMux);
  if (buddyOrientationDirty) {
    buddyOrientationDirty = false;
    localOrientation = buddyScreenOrientation;
    shouldApplyOrientation = true;
  }
  portEXIT_CRITICAL(&bleMux);
  if (shouldApplyOrientation) {
    applyBuddyScreenOrientation(localOrientation);
    Serial.printf("[LCD]  Screen orientation applied: %s (rotation=%d)\n",
      buddyOrientationStr(localOrientation),
      tftRotationForBuddyOrientation(localOrientation));
  }

  // Frame rate limiter
  bool isSleepy = (appMode == MODE_DEMO && currentScene == SCENE_SLEEP)
               || (appMode == MODE_AGENT && statusToScene(bleStatusId) == SCENE_SLEEP)
               || (appMode == MODE_ONBOARD)
               || (appMode == MODE_PAIR_CONFIRM);
  unsigned long frameInterval = isSleepy ? FRAME_MS_SLEEP : FRAME_MS_ACTIVE;
  if ((now - lastFrameTime) < frameInterval) {
    delay(1);
    return;
  }
  lastFrameTime = now;
  frameCount++;

  // FPS calculation
  if ((now - lastFpsCalcTime) >= 1000) {
    currentFps = frameCount * 1000.0f / (now - lastFpsCalcTime);
    frameCount = 0;
    lastFpsCalcTime = now;
  }

  float t = now / 1000.0f;

  // Button handling
  int btn = pollButton(now);

  // Super-long-press detection (3s): clear pairing (factory reset) from
  // ONBOARD/DEMO/AGENT modes. MODE_PAIR_CONFIRM uses normal long press.
  if (btnPressed && !superLongPressFired &&
      (now - btnPressStart) >= SUPER_LONG_PRESS_MS &&
      appMode != MODE_PAIR_CONFIRM) {
    superLongPressFired = true;
    if (isPaired) {
      Serial.println("[BTN]  Super-long press -> factory reset pairing");
      clearPairedHost();
      portENTER_CRITICAL(&bleMux);
      pairAuthenticated = false;
      appMode = MODE_ONBOARD;
      portEXIT_CRITICAL(&bleMux);
      if (bleConnected) {
        disconnectCurrentClient("factory reset pairing");
      }
    }
  }
  if (!btnPressed) {
    superLongPressFired = false;
  }

  if (appMode == MODE_PAIR_CONFIRM) {
    if (btn == 1) {
      uint8_t localPending[HOST_ID_LENGTH];
      portENTER_CRITICAL(&bleMux);
      memcpy(localPending, pendingHostId, HOST_ID_LENGTH);
      portEXIT_CRITICAL(&bleMux);
      savePairedHost(localPending);
      portENTER_CRITICAL(&bleMux);
      pairAuthenticated = true;
      hasEverConnected = true;
      appMode = MODE_AGENT;
      lastBleData = now;
      portEXIT_CRITICAL(&bleMux);
      sendPairNotify(PAIR_ACCEPTED_MARKER);
      lastInteraction = now;
      Serial.println("[BTN]  Pairing accepted");
    } else if (btn == 2) {
      sendPairNotify(PAIR_REJECTED_MARKER);
      pairRejectPending = true;
      pairRejectTime = now;
      portENTER_CRITICAL(&bleMux);
      appMode = MODE_ONBOARD;
      portEXIT_CRITICAL(&bleMux);
      Serial.println("[BTN]  Pairing rejected");
    }
  } else if (appMode == MODE_AGENT) {
    Scene agentScene = statusToScene(bleStatusId);
    if ((agentScene == SCENE_ALERT || agentScene == SCENE_QUESTION) && bleConnected && pNotifyChar) {
      if (btn == 1) {
        uint8_t payload;
        if (bleStatusId == 3) {
          payload = 0xF0;
          Serial.println("[BTN]  Approve sent (0xF0)");
        } else {
          payload = bleSourceId;
          Serial.println("[BTN]  Focus request (question mode)");
        }
        pNotifyChar->setValue(&payload, 1);
        pNotifyChar->notify();
      } else if (btn == 2) {
        uint8_t payload = (bleStatusId == 3) ? 0xF1 : 0xF2;
        pNotifyChar->setValue(&payload, 1);
        pNotifyChar->notify();
        Serial.printf("[BTN]  %s sent (0x%02X)\n",
            bleStatusId == 3 ? "Deny" : "Skip", payload);
      }
    } else if (btn == 1 && bleConnected && pNotifyChar) {
      uint8_t focusPayload = bleSourceId;
      pNotifyChar->setValue(&focusPayload, 1);
      pNotifyChar->notify();
      const char* srcName = (bleSourceId < NUM_MASCOTS) ? mascots[bleSourceId].name : "?";
      Serial.printf("[BTN]  Focus request sent: sourceId=%d(%s)\n", bleSourceId, srcName);
    } else if (btn == 1) {
      Serial.println("[BTN]  Short press (AGENT mode, BLE not ready)");
    } else if (btn == 2) {
      Serial.println("[BTN]  Long press ignored (in AGENT mode)");
    }
  } else {
    // ONBOARD or DEMO mode
    if (btn == 1) {
      lastInteraction = now;
      if (appMode == MODE_DEMO) {
        currentMascotIdx = (currentMascotIdx + 1) % NUM_MASCOTS;
        lastSceneChange = now;
        Serial.printf("[BTN]  Short press -> next mascot: %s (#%d)\n",
          mascots[currentMascotIdx].name, currentMascotIdx);
      } else {
        Serial.println("[BTN]  Short press (onboard mode, no action)");
      }
    } else if (btn == 2) {
      lastInteraction = now;
      AppMode prevMode = appMode;
      if (appMode == MODE_ONBOARD) {
        appMode = MODE_DEMO;
        lastSceneChange = now;
      } else {
        appMode = MODE_ONBOARD;
      }
      Serial.printf("[BTN]  Long press -> %s -> %s\n", appModeStr(prevMode), appModeStr(appMode));
    }
  }

  // Pair confirm timeout
  if (appMode == MODE_PAIR_CONFIRM && (now - pairRequestTime) > PAIR_CONFIRM_TIMEOUT_MS) {
    sendPairNotify(PAIR_REJECTED_MARKER);
    pairRejectPending = true;
    pairRejectTime = now;
    appMode = MODE_ONBOARD;
    Serial.println("[PAIR] Confirmation timeout, rejected");
  }

  // Delayed disconnect after pair rejection
  if (pairRejectPending && (now - pairRejectTime) > PAIR_REJECT_DELAY_MS) {
    pairRejectPending = false;
    if (bleConnected) {
      disconnectCurrentClient("pair rejected");
    }
  }

  // BLE timeout: agent mode -> back to previous mode
  if (appMode == MODE_AGENT && (now - lastBleData) > BLE_TIMEOUT_MS) {
    appMode = hasEverConnected ? MODE_ONBOARD : MODE_ONBOARD;
    Serial.printf("[BLE]  Timeout (%lus no data), -> %s\n", BLE_TIMEOUT_MS / 1000, appModeStr(appMode));
  }

  // Dynamic backlight brightness (with night mode)
  uint8_t targetBright;
  if (appMode == MODE_PAIR_CONFIRM) {
    targetBright = activeBrightness();
  } else if (appMode == MODE_AGENT && bleConnected) {
    lastInteraction = now;
    Scene agentScene = statusToScene(bleStatusId);
    targetBright = (agentScene == SCENE_SLEEP) ? sleepBrightness() : activeBrightness();
  } else if ((now - lastInteraction) > BL_IDLE_TIMEOUT_MS) {
    targetBright = idleBrightness();
  } else if (appMode == MODE_ONBOARD) {
    targetBright = sleepBrightness();
  } else {
    targetBright = (currentScene == SCENE_SLEEP) ? sleepBrightness() : activeBrightness();
  }
  // Night mode: reduce brightness during late hours
  if (bleCurrentHour != 255) {
    if (bleCurrentHour >= 22 || bleCurrentHour < 6) {
      targetBright = min(targetBright, idleBrightness());
    } else if (bleCurrentHour >= 18) {
      targetBright = min(targetBright, sleepBrightness());
    }
  }
  if (currentBrightness != targetBright) {
    uint8_t prevBright = currentBrightness;
    if (currentBrightness < targetBright) currentBrightness += min((uint8_t)3, (uint8_t)(targetBright - currentBrightness));
    else currentBrightness -= min((uint8_t)3, (uint8_t)(currentBrightness - targetBright));
    ledcWrite(TFT_BL, currentBrightness);
    if (currentBrightness == targetBright) {
      Serial.printf("[LCD]  Backlight %d -> %d (target reached)\n", prevBright, currentBrightness);
    }
  }

  // ---- Render ----
  canvas.fillScreen(0x0000);

  if (appMode == MODE_PAIR_CONFIRM) {
    drawPairConfirmScreen(t);
  } else if (appMode == MODE_ONBOARD) {
    drawOnboardScreen(t);
  } else {
    uint8_t drawIdx;
    Scene drawScene;

    if (appMode == MODE_DEMO) {
      drawIdx = currentMascotIdx;
      if ((now - lastSceneChange) >= AUTO_CYCLE_MS) {
        Scene prevScene = currentScene;
        currentScene = (Scene)((currentScene + 1) % SCENE_COUNT);
        if (currentScene == SCENE_SLEEP) {
          uint8_t prevIdx = currentMascotIdx;
          currentMascotIdx = (currentMascotIdx + 1) % NUM_MASCOTS;
          Serial.printf("[DEMO] Cycle mascot: %s(#%d) -> %s(#%d)\n",
            mascots[prevIdx].name, prevIdx, mascots[currentMascotIdx].name, currentMascotIdx);
        }
        Serial.printf("[DEMO] Cycle scene: %s -> %s\n", sceneStr(prevScene), sceneStr(currentScene));
        lastSceneChange = now;
        drawIdx = currentMascotIdx;
      }
      drawScene = currentScene;
    } else {
      drawIdx = bleSourceId < NUM_MASCOTS ? bleSourceId : 0;
      drawScene = statusToScene(bleStatusId);
    }

    // Header area (y=0..16)
    drawStatusBar();
    drawMascotName(drawIdx);

    // Mascot animation area (y=16..220)
    Mascot& m = mascots[drawIdx];

    // Check transient animations
    bool playingTransient = false;
    TransientAnim localPendingAnim;
    unsigned long localAnimStartTime;
    portENTER_CRITICAL(&bleMux);
    localPendingAnim = pendingAnim;
    localAnimStartTime = animStartTime;
    portEXIT_CRITICAL(&bleMux);
    if (localPendingAnim != ANIM_NONE && (now - localAnimStartTime) < ANIM_DURATION_MS) {
      playingTransient = true;
      if (localPendingAnim == ANIM_CELEBRATE) {
        drawCelebration(t, drawIdx, localAnimStartTime);
      } else if (localPendingAnim == ANIM_FRUSTRATED) {
        drawFrustrated(t, drawIdx, localAnimStartTime);
      }
    } else {
      if (localPendingAnim != ANIM_NONE) {
        portENTER_CRITICAL(&bleMux);
        if (pendingAnim == localPendingAnim && animStartTime == localAnimStartTime) {
          pendingAnim = ANIM_NONE;
        }
        portEXIT_CRITICAL(&bleMux);
      }

      // Bored detection for idle mascots
      if (drawScene == SCENE_SLEEP) {
        unsigned long idleDuration = now - lastBleData;
        globalBored = (idleDuration > 300000UL);  // 5 minutes
        if (globalBored) {
          float boredCycle = fmodf(t, 8.0f);
          if (boredCycle < 1.0f) globalBoredEyeOffsetX = -1.0f;
          else if (boredCycle > 3.0f && boredCycle < 4.0f) globalBoredEyeOffsetX = 1.0f;
          else globalBoredEyeOffsetX = 0.0f;
        } else {
          globalBoredEyeOffsetX = 0.0f;
        }
      } else {
        globalBored = false;
        globalBoredEyeOffsetX = 0.0f;
      }

      // Compute activity-based time scale for work animations
      if (drawScene == SCENE_WORK) {
        globalWorkTimeScale = 1.0f;
        if (bleWriteInterval < 2000) globalWorkTimeScale = 1.5f;
        if (bleWriteInterval < 500)  globalWorkTimeScale = 2.0f;
      }

      switch (drawScene) {
        case SCENE_SLEEP:    m.sleep(t); break;
        case SCENE_WORK:     m.work(t * globalWorkTimeScale);  break;
        case SCENE_ALERT:    m.alert(t); break;
        case SCENE_QUESTION: m.question(t); break;
        default: break;
      }

      // Subagent dots during work scene
      if (drawScene == SCENE_WORK && bleSubagentCount > 0) {
        drawSubagentDots(bleSubagentCount, 0);
      }
    }

    // Info area (AGENT mode only)
    if (appMode == MODE_AGENT && !playingTransient) {
      if (drawScene == SCENE_SLEEP) {
        drawWorkspaceLabel(224);
        drawStatsPanel();
        drawToolTimeline();
        drawHeatmapBar();
      } else if (drawScene == SCENE_ALERT || drawScene == SCENE_QUESTION) {
        drawWorkspaceLabel(274);
        drawToolLabel(286);
        drawAlertActionHints(bleStatusId);
      } else {
        drawWorkspaceLabel(292);
        drawToolLabel(304);
      }
    }
  }

  tft.drawRGBBitmap(0, 0, canvas.getBuffer(), LCD_W, LCD_H);

  // NVS debounce write
  if ((now - lastNvsSave) > NVS_DEBOUNCE_MS) {
    bool shouldSaveNvs = false;
    uint8_t nvsBrightness = BUDDY_BRIGHTNESS_DEFAULT_PERCENT;
    uint8_t nvsOrientation = BUDDY_SCREEN_UP;
    portENTER_CRITICAL(&bleMux);
    if (nvsDirty) {
      nvsBrightness = buddyBrightnessPercent;
      nvsOrientation = buddyScreenOrientation;
      nvsDirty = false;
      shouldSaveNvs = true;
    }
    portEXIT_CRITICAL(&bleMux);
    if (shouldSaveNvs) {
      prefs.putUChar("bright", nvsBrightness);
      prefs.putUChar("orient", nvsOrientation);
      lastNvsSave = now;
      Serial.printf("[NVS]  Saved brightness=%d%% orientation=%s\n",
        nvsBrightness, buddyOrientationStr(nvsOrientation));
    }
  }

#ifdef BUDDY_OTA_ENABLED
  // OTA initialization (deferred from BLE callback to avoid blocking)
  if (otaPending && !otaEnabled) {
    otaPending = false;
    Serial.println("[OTA] Starting WiFi + OTA from main loop...");
    WiFi.begin(otaSsid, otaPassword);
    ArduinoOTA.setHostname(bleDeviceName);
    ArduinoOTA.onStart([]() {
      canvas.fillScreen(0x0000);
      drawCenteredText("OTA Update", 100, 2, RGB565(255, 200, 50));
      tft.drawRGBBitmap(0, 0, canvas.getBuffer(), LCD_W, LCD_H);
    });
    ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
      int pct = progress * 100 / total;
      char buf[16];
      snprintf(buf, sizeof(buf), "%d%%", pct);
      canvas.fillScreen(0x0000);
      drawCenteredText("OTA Update", 100, 2, RGB565(255, 200, 50));
      drawCenteredText(buf, 140, 2, RGB565(200, 200, 200));
      int barW = LCD_W * pct / 100;
      canvas.fillRect(0, 160, barW, 8, RGB565(50, 200, 50));
      canvas.fillRect(barW, 160, LCD_W - barW, 8, RGB565(40, 40, 40));
      tft.drawRGBBitmap(0, 0, canvas.getBuffer(), LCD_W, LCD_H);
    });
    ArduinoOTA.onEnd([]() {
      canvas.fillScreen(0x0000);
      drawCenteredText("Rebooting...", 120, 2, RGB565(50, 230, 50));
      tft.drawRGBBitmap(0, 0, canvas.getBuffer(), LCD_W, LCD_H);
    });
    ArduinoOTA.begin();
    otaEnabled = true;
  }

  // OTA handle
  if (otaEnabled) ArduinoOTA.handle();
#endif

  // Periodic status log
  if ((now - lastLogTime) >= LOG_INTERVAL_MS) {
    lastLogTime = now;
    unsigned long upSec = now / 1000;
    unsigned long idleSec = (now - lastInteraction) / 1000;

    Serial.printf("[STAT] up=%lus | fps=%.1f | heap=%d | bright=%d/255 (%d%%)\n",
      upSec, currentFps, ESP.getFreeHeap(), currentBrightness, buddyBrightnessPercent);
    Serial.printf("[STAT] mode=%s | ble=%s | paired=%s | auth=%s\n",
      appModeStr(appMode),
      bleConnected ? "CONNECTED" : "disconnected",
      isPaired ? "yes" : "no",
      pairAuthenticated ? "yes" : "no");

    if (appMode == MODE_AGENT) {
      char toolBuf[18];
      portENTER_CRITICAL(&bleMux);
      memcpy(toolBuf, bleToolName, sizeof(toolBuf));
      uint8_t localSrc = bleSourceId;
      uint8_t localSts = bleStatusId;
      portEXIT_CRITICAL(&bleMux);
      Serial.printf("[STAT] agent=%s(#%d) status=%s tool=\"%s\"\n",
        (localSrc < NUM_MASCOTS) ? mascots[localSrc].name : "?",
        localSrc, statusStr(localSts), toolBuf);
    } else if (appMode == MODE_DEMO) {
      Serial.printf("[STAT] mascot=%s(#%d) scene=%s idle=%lus next_cycle=%lus\n",
        mascots[currentMascotIdx].name, currentMascotIdx,
        sceneStr(currentScene), idleSec,
        (AUTO_CYCLE_MS - min(AUTO_CYCLE_MS, now - lastSceneChange)) / 1000);
    } else {
      Serial.printf("[STAT] onboard idle=%lus\n", idleSec);
    }
  }
}
