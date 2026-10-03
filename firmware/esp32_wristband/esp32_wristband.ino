/*
 * SENSE — Assistive Wearable Wristband (ESP32)
 *
 * Hardware:
 *  - ESP32 Development Board
 *  - Left Vibration Motor (e.g., GPIO 18 via NPN/MOSFET driver)
 *  - Right Vibration Motor (e.g., GPIO 19 via NPN/MOSFET driver)
 *  - Optional ToF Sensor (VL53L0X on I2C SDA:21, SCL:22)
 *
 * BLE Architecture:
 *  - Advertises as: "SENSE-Wristband"
 *  - Service UUID: 0000FEED-0000-1000-8000-00805F9B34FB
 *  - Command Char (Write): 0000BEEF-0000-1000-8000-00805F9B34FB
 *  - Telemetry Char (Notify): 0000CAFE-0000-1000-8000-00805F9B34FB
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>

// Pin definitions (adjust according to your wiring)
#define MOTOR_LEFT_PIN   18
#define MOTOR_RIGHT_PIN  19
#define STATUS_LED_PIN   2

// BLE UUIDs
#define SERVICE_UUID        "0000FEED-0000-1000-8000-00805F9B34FB"
#define CHAR_COMMAND_UUID   "0000BEEF-0000-1000-8000-00805F9B34FB"
#define CHAR_TELEMETRY_UUID "0000CAFE-0000-1000-8000-00805F9B34FB"

BLEServer* pServer = NULL;
BLECharacteristic* pCommandChar = NULL;
BLECharacteristic* pTelemetryChar = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Vibration State Machine
enum VibrationPattern {
  PATTERN_OFF,
  PATTERN_LEFT,
  PATTERN_RIGHT,
  PATTERN_CENTER,
  PATTERN_NEAR
};

VibrationPattern currentPattern = PATTERN_OFF;
unsigned long patternStartTime = 0;
int nearPulseCount = 0;

void setMotors(bool left, bool right) {
  digitalWrite(MOTOR_LEFT_PIN, left ? HIGH : LOW);
  digitalWrite(MOTOR_RIGHT_PIN, right ? HIGH : LOW);
}

void triggerHaptic(String cmd) {
  cmd.trim();
  cmd.toUpperCase();
  Serial.print("Received Haptic Command: ");
  Serial.println(cmd);

  patternStartTime = millis();

  if (cmd == "LEFT" || cmd == "1") {
    currentPattern = PATTERN_LEFT;
    setMotors(true, false);
  } else if (cmd == "RIGHT" || cmd == "2") {
    currentPattern = PATTERN_RIGHT;
    setMotors(false, true);
  } else if (cmd == "CENTER" || cmd == "3") {
    currentPattern = PATTERN_CENTER;
    setMotors(true, true);
  } else if (cmd == "NEAR" || cmd == "4") {
    currentPattern = PATTERN_NEAR;
    nearPulseCount = 0;
    setMotors(true, true);
  } else if (cmd == "STOP" || cmd == "0") {
    currentPattern = PATTERN_OFF;
    setMotors(false, false);
  }
}

// BLE Server Callbacks
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    digitalWrite(STATUS_LED_PIN, HIGH);
    Serial.println("Phone connected via BLE!");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    digitalWrite(STATUS_LED_PIN, LOW);
    setMotors(false, false);
    Serial.println("Phone disconnected. Advertising restarted.");
  }
};

// Command Characteristic Callbacks
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    if (value.length() > 0) {
      triggerHaptic(value);
    }
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(MOTOR_LEFT_PIN, OUTPUT);
  pinMode(MOTOR_RIGHT_PIN, OUTPUT);
  pinMode(STATUS_LED_PIN, OUTPUT);
  setMotors(false, false);

  // Initialize BLE
  BLEDevice::init("SENSE-Wristband");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create Service
  BLEService* pService = pServer->createService(SERVICE_UUID);

  // Create Command Characteristic (Phone writes to ESP32)
  pCommandChar = pService->createCharacteristic(
    CHAR_COMMAND_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pCommandChar->setCallbacks(new CommandCallbacks());

  // Create Telemetry Characteristic (ESP32 notifies Phone)
  pTelemetryChar = pService->createCharacteristic(
    CHAR_TELEMETRY_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pTelemetryChar->addDescriptor(new BLE2902());

  pService->start();

  // Start Advertising
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("SENSE Wristband BLE Server is ready and advertising.");
}

void loop() {
  unsigned long now = millis();

  // Non-blocking vibration timing handler
  switch (currentPattern) {
    case PATTERN_LEFT:
    case PATTERN_RIGHT:
    case PATTERN_CENTER:
      // Single 250ms pulse
      if (now - patternStartTime > 250) {
        setMotors(false, false);
        currentPattern = PATTERN_OFF;
      }
      break;

    case PATTERN_NEAR:
      // Rapid double pulse (100ms ON, 80ms OFF, 100ms ON)
      if (nearPulseCount == 0 && (now - patternStartTime > 100)) {
        setMotors(false, false);
        nearPulseCount = 1;
      } else if (nearPulseCount == 1 && (now - patternStartTime > 180)) {
        setMotors(true, true);
        nearPulseCount = 2;
      } else if (nearPulseCount == 2 && (now - patternStartTime > 280)) {
        setMotors(false, false);
        currentPattern = PATTERN_OFF;
      }
      break;

    case PATTERN_OFF:
    default:
      break;
  }

  // Handle reconnect advertising
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->startAdvertising();
    oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  delay(20);
}
