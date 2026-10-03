# SENSE

**AI-Powered Object Finder with BLE Smart Wristband**

> SENSE is an AI-powered assistive object-finding system that uses smartphone vision for directional guidance and a BLE-connected ESP32 wristband for proximity-aware haptic feedback.

---

## 1. Problem

For individuals who are blind or have low vision, locating small, misplaced personal items (such as a smartphone, cup, or water bottle) in indoor environments remains an everyday challenge. Standard audio cues (like ringing a lost phone) only work when an item can emit sound and is powered on, while manual tactile sweeping of tables and counters is slow, frustrating, and risks knocking fragile items onto the floor. 

Visual assistant apps that rely entirely on speech cues can overload the user's auditory channel and cause disorientation. Visually impaired users need an intuitive, unobtrusive, multimodal approach that combines directional orientation with direct physical tactile feedback.

---

## 2. Solution

SENSE decouples coarse directional orientation from fine contact proximity:
1. The **smartphone's camera** scans the room and runs an on-device neural network to visually locate the target object.
2. Spatial reasoning calculates the horizontal angle and directs the user left or right.
3. The phone transmits compact 3-byte packets over **Bluetooth Low Energy (BLE)** to a custom **ESP32 smart wristband**.
4. Left and right **vibration motors** guide the user's orientation without speech clutter.
5. An onboard **ultrasonic sensor** on the wrist measures physical hand-to-object distance, increasing vibration pulse frequency until contact is made.

```text
Smartphone Camera
        ↓
AI Object Detection (TFLite)
        ↓
Spatial Reasoning (Left / Center / Right)
        ↓
BLE (3-Byte Wire Protocol)
        ↓
ESP32 Wristband
        ↓
Directional Haptic Feedback (Left / Right Motors)
        ↓
Ultrasonic Proximity (Pulse Cadence Modulation)
```

---

## 3. Features

- **On-Device AI Object Detection**: Runs 100% offline using a bundled, quantized SSD MobileNet v1 model with zero cloud calls, zero latency, and complete privacy.
- **Directional Spatial Guidance**: Translates visual bounding box centroids into Left, Centered, and Right spatial instructions.
- **Flutter Mobile Application**: Clean, accessible Android application featuring high-contrast UI, TalkBack compatibility, and Text-to-Speech (TTS).
- **Ultra-Low Latency BLE Communication**: Asynchronous GATT communication using compact 3-byte command and telemetry packets.
- **ESP32 Wearable Wristband**: Lightweight embedded firmware managing ultrasonic ranging and haptic generation.
- **Ultrasonic Proximity Sensing**: HC-SR04 sonar sensor with a 3-sample median filter measuring real-time hand-to-target distance.
- **Dual Directional Vibration Motors**: Independent left and right ERM vibration motors driven via transistor switches.
- **Adaptive Haptic Cadence**: Vibration frequency automatically scales from relaxed pulses (900 ms period) to urgent buzzing (160 ms period) as the user closes in.
- **Graceful Offline Demo Mode**: Fully testable simulated finding interface for evaluating the app without physical wristband hardware.

---

## 4. Demo Workflow

```text
Select Target (PHONE / BOTTLE / CUP)
        ↓
AI detects target in camera view
        ↓
Direction = RIGHT (normalizedX > 0.65)
        ↓
BLE sends direction packet to wristband
        ↓
Right wrist motor vibrates
        ↓
User turns toward center & moves forward
        ↓
Ultrasonic distance decreases (< 100 cm → < 60 cm)
        ↓
Haptic feedback becomes faster and more frequent
        ↓
Target centered + near (< 60 cm for 600 ms)
        ↓
Solid 700 ms arrival buzz & voice: "Your phone is here."
```

For the complete testing steps, see [`docs/demo-script.md`](docs/demo-script.md).

---

## 5. Technology Stack

Only implemented, functional technologies are included:

- **Mobile Framework**: Flutter 3.x / Dart
- **Microcontroller**: ESP32 (Tensilica Xtensa Dual-Core 32-bit)
- **Firmware Environment**: Arduino ESP32 Core (C++)
- **Wireless Protocol**: Bluetooth Low Energy (BLE 4.2 / 5.0 GATT)
- **Computer Vision**: TensorFlow Lite (SSD MobileNet v1 quantized uint8)
- **Camera Pipeline**: Flutter Camera Plugin (YUV420 to RGB preprocessing)
- **Sensor**: HC-SR04 Ultrasonic Distance Sensor (with 5V-to-3.3V protection)
- **Haptics**: Dual ERM coin vibration motors with 2N2222 transistor drivers
- **Audio / Speech**: `flutter_tts` (Text-to-Speech)

---

## 6. Repository Layout

```text
chathuranga/
│
├── mobile/                   # Complete Flutter SENSE Android application
│   ├── android/              # Native Android configuration (permissions, Gradle 9)
│   ├── assets/models/        # Bundled TFLite model and COCO labels
│   ├── lib/                  # Application source code
│   │   ├── core/             # Protocol enums and system constants
│   │   ├── services/         # BLE, Guidance Engine, TFLite Detector, Speech
│   │   └── ui/               # Accessible high-contrast Flutter screens
│   ├── test/                 # Core protocol and unit tests
│   └── pubspec.yaml          # Flutter dependencies
│
├── firmware/                 # ESP32 smart wristband firmware
│   └── sense_wrist/
│       └── sense_wrist.ino   # BLE GATT server, sonar ranging, and motor drivers
│
├── ai/                       # AI models, label sets, and vision documentation
│   ├── models/               # SSD MobileNet v1 quantized TFLite model
│   └── README.md             # Vision pipeline and inference specifications
│
├── docs/                     # System documentation
│   ├── architecture.md       # End-to-end architecture and dataflow
│   ├── ble-protocol.md       # 3-byte GATT wire protocol specification
│   ├── hardware.md           # Schematic, pin assignments, and driver circuits
│   ├── calibration.md        # Distance thresholds and haptic timing specs
│   └── demo-script.md        # Live demonstration walkthrough
│
├── README.md                 # Project overview and guide
├── .gitignore                # Git ignore rules
└── LICENSE                   # MIT License
```

---

## 7. Getting Started

### Prerequisites
- **Mobile**: Flutter SDK 3.x, Android SDK (API 23+)
- **Firmware**: Arduino IDE or `arduino-cli` with ESP32 board support package

### Running the Mobile App
```bash
cd mobile
flutter pub get
flutter test
flutter run
```

### Flashing the ESP32 Wristband
1. Open [`firmware/sense_wrist/sense_wrist.ino`](firmware/sense_wrist/sense_wrist.ino) in Arduino IDE.
2. Select Board: **ESP32 Dev Module**.
3. Wire the components according to [`docs/hardware.md`](docs/hardware.md).
4. Upload to the ESP32 and open Serial Monitor at **115200 baud**.
5. The device will run its boot self-test (buzz left, buzz right) and begin advertising as `SENSE-WRIST-01`.

---

## 8. Honest Engineering Statement

SENSE is designed as an assistive tool to aid in locating common indoor personal objects. It is **not** a mobility aid, navigation system, medical device, or replacement for a white cane or guide dog. It does not provide guaranteed obstacle avoidance or spatial mapping beyond direct line-of-sight sensor readings.

---

## 9. License

This project is open-source under the [MIT License](LICENSE).
