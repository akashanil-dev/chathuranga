/*
 * SENSE — Assistive Wearable Wristband (ESP32)
 *
 * Hardware:
 *  - ESP32 Development Board (ESP32 Dev Module)
 *  - 1 vibration motor on GPIO 18 via NPN transistor / logic-level MOSFET (+ flyback diode)
 *  - HC-SR04 ultrasonic sensor: VCC=5V(VIN), GND, TRIG=GPIO 5,
 *    ECHO=GPIO 17 THROUGH A VOLTAGE DIVIDER (1k series, 2k to GND) — echo is 5 V
 *  - Status LED on GPIO 2 (on-board), lit while the phone is connected
 *
 * BLE Architecture (must match mobile/lib/core/constants/app_constants.dart):
 *  - Advertises as: "SENSE-Wristband"
 *  - Service UUID: 0000FEED-0000-1000-8000-00805F9B34FB
 *  - Command Char (Write): 0000BEEF-...  phone -> ESP32, ASCII: LEFT/RIGHT/CENTER/NEAR/TOUCHING/STOP
 *  - Telemetry Char (Notify): 0000CAFE-... ESP32 -> phone, ASCII distance in cm, e.g. "42.5"
 *
 * Haptic patterns (single motor):
 *  LEFT 1 short | RIGHT 2 short | CENTER 1 long | NEAR 3 rapid | TOUCHING continuous | STOP off
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Pin definitions (adjust according to your wiring)
#define MOTOR_PIN       18
#define TRIG_PIN        5
#define ECHO_PIN        17
#define STATUS_LED_PIN  2

// BLE UUIDs
#define DEVICE_NAME         "SENSE-Wristband"
#define SERVICE_UUID        "0000FEED-0000-1000-8000-00805F9B34FB"
#define CHAR_COMMAND_UUID   "0000BEEF-0000-1000-8000-00805F9B34FB"
#define CHAR_TELEMETRY_UUID "0000CAFE-0000-1000-8000-00805F9B34FB"

// Timing
const uint32_t SAMPLE_MS          = 60;     // HC-SR04 ping interval (>= 60 ms avoids echo overlap)
const uint32_t NOTIFY_MS          = 150;    // distance notification interval
const uint32_t ECHO_TIMEOUT_US    = 25000;  // ~4 m max range
const float    MAX_RANGE_CM       = 400.0;
const uint32_t TOUCHING_REFRESH_MS = 3000;  // continuous buzz stops if the phone stops confirming
const uint32_t SERIAL_LOG_MS      = 500;

BLEServer* pServer = NULL;
BLECharacteristic* pCommandChar = NULL;
BLECharacteristic* pTelemetryChar = NULL;
volatile bool deviceConnected = false;
bool oldDeviceConnected = false;

// ---------- Vibration pattern player (non-blocking) ----------
// Each pattern is a list of ON/OFF durations in ms, starting with ON.
struct Pattern { const uint16_t* steps; uint8_t count; };
const uint16_t P_LEFT[]   = {150};
const uint16_t P_RIGHT[]  = {150, 150, 150};
const uint16_t P_CENTER[] = {600};
const uint16_t P_NEAR[]   = {80, 70, 80, 70, 80};

const Pattern* activePattern = NULL;
Pattern currentPattern;
uint8_t stepIndex = 0;
uint32_t stepStart = 0;
bool continuousBuzz = false;
uint32_t continuousSince = 0;

// Command written from the BLE callback, consumed in loop() (keeps the BLE task short)
volatile bool pendingCommand = false;
String pendingValue;
portMUX_TYPE cmdMux = portMUX_INITIALIZER_UNLOCKED;

void motor(bool on) { digitalWrite(MOTOR_PIN, on ? HIGH : LOW); }

void playPattern(const uint16_t* steps, uint8_t count) {
  continuousBuzz = false;
  currentPattern = {steps, count};
  activePattern = &currentPattern;
  stepIndex = 0;
  stepStart = millis();
  motor(true);
}

void stopAll() {
  activePattern = NULL;
  continuousBuzz = false;
  motor(false);
}

void triggerHaptic(String cmd) {
  cmd.trim();
  cmd.toUpperCase();
  Serial.print("Received Haptic Command: ");
  Serial.println(cmd);

  if (cmd == "LEFT" || cmd == "1") {
    playPattern(P_LEFT, sizeof(P_LEFT) / sizeof(P_LEFT[0]));
  } else if (cmd == "RIGHT" || cmd == "2") {
    playPattern(P_RIGHT, sizeof(P_RIGHT) / sizeof(P_RIGHT[0]));
  } else if (cmd == "CENTER" || cmd == "3") {
    playPattern(P_CENTER, sizeof(P_CENTER) / sizeof(P_CENTER[0]));
  } else if (cmd == "NEAR" || cmd == "4") {
    playPattern(P_NEAR, sizeof(P_NEAR) / sizeof(P_NEAR[0]));
  } else if (cmd == "TOUCHING" || cmd == "5") {
    activePattern = NULL;
    continuousBuzz = true;
    continuousSince = millis();
    motor(true);
  } else if (cmd == "STOP" || cmd == "0") {
    stopAll();
  } else {
    Serial.println("  (unknown command ignored)");
  }
}

void updateMotor(uint32_t now) {
  if (continuousBuzz) {
    if (now - continuousSince > TOUCHING_REFRESH_MS) {
      Serial.println("TOUCHING timed out -> motor off");
      stopAll();
    }
    return;
  }
  if (!activePattern) return;
  if (now - stepStart < activePattern->steps[stepIndex]) return;
  stepIndex++;
  stepStart = now;
  if (stepIndex >= activePattern->count) {
    stopAll();
    return;
  }
  motor(stepIndex % 2 == 0);  // even steps ON, odd steps OFF
}

// ---------- HC-SR04 distance (median of last 3 readings) ----------
float samples[3] = {-1, -1, -1};
uint8_t sampleIdx = 0;
float distanceCm = -1;  // -1 = no echo / out of range

float readDistanceOnce() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  unsigned long duration = pulseIn(ECHO_PIN, HIGH, ECHO_TIMEOUT_US);
  if (duration == 0) return -1;
  float cm = duration * 0.0343f / 2.0f;
  return (cm < 2.0f || cm > MAX_RANGE_CM) ? -1 : cm;
}

float median3(float a, float b, float c) {
  if (a > b) { float t = a; a = b; b = t; }
  if (b > c) { float t = b; b = c; c = t; }
  if (a > b) { float t = a; a = b; b = t; }
  return b;
}

void sampleDistance() {
  samples[sampleIdx] = readDistanceOnce();
  sampleIdx = (sampleIdx + 1) % 3;
  int valid = 0;
  float v[3];
  for (int i = 0; i < 3; i++) if (samples[i] > 0) v[valid++] = samples[i];
  if (valid == 3) distanceCm = median3(v[0], v[1], v[2]);
  else if (valid == 2) distanceCm = (v[0] + v[1]) / 2.0f;
  else if (valid == 1) distanceCm = v[0];
  else distanceCm = -1;
}

// ---------- BLE callbacks ----------
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    deviceConnected = true;
    digitalWrite(STATUS_LED_PIN, HIGH);
    Serial.println("Phone connected via BLE!");
  }

  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    digitalWrite(STATUS_LED_PIN, LOW);
    Serial.println("Phone disconnected. Advertising restarted.");
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    String value = pCharacteristic->getValue().c_str();
    if (value.length() == 0) return;
    portENTER_CRITICAL(&cmdMux);
    pendingValue = value;
    pendingCommand = true;
    portEXIT_CRITICAL(&cmdMux);
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(MOTOR_PIN, OUTPUT);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(STATUS_LED_PIN, OUTPUT);
  motor(false);
  digitalWrite(TRIG_PIN, LOW);

  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCommandChar = pService->createCharacteristic(
    CHAR_COMMAND_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pCommandChar->setCallbacks(new CommandCallbacks());

  pTelemetryChar = pService->createCharacteristic(
    CHAR_TELEMETRY_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pTelemetryChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  // Boot self-test: one short buzz so you can feel the motor works.
  playPattern(P_LEFT, 1);
  Serial.println("SENSE Wristband BLE Server is ready and advertising.");
  Serial.println("Wiring: MOTOR=GPIO18 TRIG=GPIO5 ECHO=GPIO17(divider) LED=GPIO2");
  Serial.println("Tip: type LEFT/RIGHT/CENTER/NEAR/TOUCHING/STOP here to test the motor without the phone.");
}

uint32_t lastSample = 0, lastNotify = 0, lastLog = 0;
String serialLine;

void loop() {
  uint32_t now = millis();

  if (pendingCommand) {
    portENTER_CRITICAL(&cmdMux);
    String value = pendingValue;
    pendingCommand = false;
    portEXIT_CRITICAL(&cmdMux);
    triggerHaptic(value);
  }

  // Serial Monitor test commands (115200 baud, newline)
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n' || ch == '\r') {
      if (serialLine.length()) triggerHaptic(serialLine);
      serialLine = "";
    } else if (serialLine.length() < 16) {
      serialLine += ch;
    }
  }

  updateMotor(now);

  if (now - lastSample >= SAMPLE_MS) {
    lastSample = now;
    sampleDistance();
  }

  if (deviceConnected && distanceCm > 0 && now - lastNotify >= NOTIFY_MS) {
    lastNotify = now;
    char buf[12];
    snprintf(buf, sizeof(buf), "%.1f", distanceCm);
    pTelemetryChar->setValue((uint8_t*)buf, strlen(buf));
    pTelemetryChar->notify();
  }

  if (now - lastLog >= SERIAL_LOG_MS) {
    lastLog = now;
    Serial.print("Distance: ");
    if (distanceCm > 0) { Serial.print(distanceCm, 1); Serial.print(" cm"); }
    else Serial.print("-- (no echo)");
    Serial.println(deviceConnected ? "  [BLE connected]" : "  [advertising]");
  }

  // Handle reconnect advertising
  if (!deviceConnected && oldDeviceConnected) {
    stopAll();
    delay(300);
    pServer->startAdvertising();
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }

  delay(5);
}
