// SENSE wristband firmware: ESP32 + HC-SR04 + 2 vibration motors + BLE
// Uses the ESP32 Arduino core's built-in BLE library (no extra installs).
// Phase 1-3 scope: distance -> pulse rate, LEFT/RIGHT motor control, BLE link.

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ---------- BLE (must match mobile/lib/core/constants.dart) ----------
#define DEVICE_NAME  "SENSE-WRIST-01"
#define SERVICE_UUID "5e45a001-1000-4a5e-9e5e-5e45e5e5e5e5"
#define SENSOR_UUID  "5e45a002-1000-4a5e-9e5e-5e45e5e5e5e5"  // ESP32 -> phone: [distLo, distHi, closeness]
#define HAPTIC_UUID  "5e45a003-1000-4a5e-9e5e-5e45e5e5e5e5"  // phone -> ESP32: [direction, closeness, state]

// ---------- Pins ----------
const int PIN_TRIG    = 5;
const int PIN_ECHO    = 18;  // through a 1k/2k divider! HC-SR04 echo is 5 V
const int PIN_MOTOR_L = 25;  // via transistor driver
const int PIN_MOTOR_R = 26;  // via transistor driver

// ---------- Calibration: INITIAL VALUES ONLY. Measure with your real objects. ----------
// Keep in sync with mobile/lib/core/constants.dart
const int T_VERY_NEAR = 30;   // cm
const int T_NEAR      = 60;
const int T_MID       = 100;
const uint32_t PERIOD_MS[4] = {900, 520, 300, 160};  // far, mid, near, very near
const uint32_t ON_MS         = 80;    // must be < smallest period
const uint32_t REACHED_MS    = 700;   // one long buzz when target reached
const uint32_t CMD_TIMEOUT_MS = 1500; // no command for this long -> motors off (failsafe)
const uint32_t SAMPLE_MS     = 60;
const uint32_t NOTIFY_MS     = 100;

enum Dir : uint8_t { D_NONE, D_LEFT, D_RIGHT, D_UP, D_DOWN, D_CENTERED };
enum St  : uint8_t { S_SEARCHING, S_APPROACHING, S_REACHED };

BLECharacteristic* sensorChar = nullptr;
volatile uint8_t  cmdDir = D_NONE;
volatile uint8_t  cmdState = S_SEARCHING;
volatile uint32_t cmdAt = 0;
volatile bool     reachedEdge = false;
volatile bool     clientConnected = false;

int samples[3] = {999, 999, 999};
int sampleIdx = 0;
int distCm = 999;
uint8_t closeness = 0;
uint32_t reachedUntil = 0;

class ServerCb : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { clientConnected = true; }
  void onDisconnect(BLEServer*) override {
    clientConnected = false;
    BLEDevice::startAdvertising();  // allow reconnect
  }
};

class HapticCb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    auto v = c->getValue();
    if (v.length() < 3) return;
    uint8_t d = (uint8_t)v[0];
    uint8_t st = (uint8_t)v[2];
    if (st == S_REACHED && cmdState != S_REACHED) reachedEdge = true;  // edge-triggered
    cmdDir = d;
    cmdState = st;
    cmdAt = millis();
  }
};

// Blocks at most ~25 ms per read (pulseIn timeout). Fine at a 60 ms cadence.
int readCm() {
  digitalWrite(PIN_TRIG, LOW);  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  unsigned long us = pulseIn(PIN_ECHO, HIGH, 25000);
  if (us == 0) return 999;  // no echo
  return (int)(us / 58);
}

int median3() {
  int a = samples[0], b = samples[1], c = samples[2];
  if (a > b) { int t = a; a = b; b = t; }
  if (b > c) { int t = b; b = c; c = t; }
  if (a > b) { int t = a; a = b; b = t; }
  return b;
}

uint8_t classify(int cm) {
  if (cm <= 0 || cm >= 400) return 0;
  if (cm < T_VERY_NEAR) return 3;
  if (cm < T_NEAR) return 2;
  if (cm < T_MID) return 1;
  return 0;
}

void updateMotors(uint32_t now) {
  bool l = false, r = false;
  if (now < reachedUntil) {
    l = r = true;  // solid buzz = reached
  } else if (cmdAt != 0 && (now - cmdAt) <= CMD_TIMEOUT_MS && cmdState != S_REACHED) {
    bool pulseOn = (now % PERIOD_MS[closeness]) < ON_MS;
    switch (cmdDir) {
      case D_LEFT:     l = pulseOn; break;            // left motor = move/orient left
      case D_RIGHT:    r = pulseOn; break;            // right motor = move/orient right
      case D_CENTERED: l = r = pulseOn; break;        // both = centered
      default: break;                                 // UP/DOWN not used in MVP
    }
  }
  digitalWrite(PIN_MOTOR_L, l ? HIGH : LOW);
  digitalWrite(PIN_MOTOR_R, r ? HIGH : LOW);
}

void selfTest() {  // wiring check on every boot: left buzz, then right buzz
  digitalWrite(PIN_MOTOR_L, HIGH); delay(250); digitalWrite(PIN_MOTOR_L, LOW); delay(150);
  digitalWrite(PIN_MOTOR_R, HIGH); delay(250); digitalWrite(PIN_MOTOR_R, LOW);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_MOTOR_L, OUTPUT);
  pinMode(PIN_MOTOR_R, OUTPUT);
  digitalWrite(PIN_MOTOR_L, LOW);
  digitalWrite(PIN_MOTOR_R, LOW);
  selfTest();

  BLEDevice::init(DEVICE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCb());
  BLEService* svc = server->createService(SERVICE_UUID);

  sensorChar = svc->createCharacteristic(SENSOR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  sensorChar->addDescriptor(new BLE2902());

  BLECharacteristic* hapticChar = svc->createCharacteristic(HAPTIC_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  hapticChar->setCallbacks(new HapticCb());

  svc->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("SENSE wristband ready: advertising as " DEVICE_NAME);
}

void loop() {
  uint32_t now = millis();

  static uint32_t lastSample = 0;
  if (now - lastSample >= SAMPLE_MS) {
    lastSample = now;
    samples[sampleIdx] = readCm();
    sampleIdx = (sampleIdx + 1) % 3;
    distCm = median3();
    closeness = classify(distCm);  // the ESP32's own value always wins over the phone's
  }

  if (reachedEdge) { reachedEdge = false; reachedUntil = now + REACHED_MS; }

  static uint32_t lastNotify = 0;
  if (clientConnected && now - lastNotify >= NOTIFY_MS) {
    lastNotify = now;
    uint8_t pkt[3] = { (uint8_t)(distCm & 0xFF), (uint8_t)((distCm >> 8) & 0xFF), closeness };
    sensorChar->setValue(pkt, 3);
    sensorChar->notify();
  }

  static uint32_t lastPrint = 0;
  if (now - lastPrint >= 500) {
    lastPrint = now;
    Serial.printf("dist=%d cm  closeness=%u  cmdDir=%u  cmdState=%u  client=%d\n",
                  distCm, closeness, (unsigned)cmdDir, (unsigned)cmdState, (int)clientConnected);
  }

  updateMotors(now);
}
