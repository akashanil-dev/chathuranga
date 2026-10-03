# SENSE System Calibration Guide

This guide describes the physical and algorithmic calibration parameters used across the SENSE system. To maintain synchronized behavior, these values are kept consistent between the ESP32 firmware ([`firmware/sense_wrist/sense_wrist.ino`](file:///C:/Users/nashw/.gemini/antigravity/scratch/sense/firmware/sense_wrist/sense_wrist.ino)) and the Flutter mobile application ([`mobile/lib/core/constants.dart`](file:///C:/Users/nashw/.gemini/antigravity/scratch/sense/mobile/lib/core/constants.dart)).

---

## 1. Ultrasonic Distance Thresholds

Distance measurements from the HC-SR04 are grouped into 4 distinct operational zones:

| Zone | Threshold (`distCm`) | Meaning | Haptic Sensation |
| :--- | :--- | :--- | :--- |
| **`FAR`** | $\ge 100\text{ cm}$ or no echo | Beyond close range; orientation only | Relaxed, slow heartbeat pulse |
| **`MID`** | $60\text{ cm} \le d < 100\text{ cm}$ | Target approached within 1 meter | Moderate pacing |
| **`NEAR`** | $30\text{ cm} \le d < 60\text{ cm}$ | Within arm's reach; prepare to touch | Rapid, urgent pulsing |
| **`VERY_NEAR`** | $< 30\text{ cm}$ | Immediate contact zone (< 1 foot) | Very high frequency buzzing |

---

## 2. Haptic Cadence & Pulse Modulation

The vibration motors operate in active-pulse mode to prevent tactile sensory adaptation (numbness caused by continuous vibration):

$$\text{Duty Cycle} = \frac{\text{ON\_MS}}{\text{PERIOD\_MS}[\text{closeness}]}$$

| Closeness | Period (`PERIOD_MS`) | On Time (`ON_MS`) | Duty Cycle | Sensation |
| :---: | :---: | :---: | :---: | :--- |
| **`FAR`** | 900 ms | 80 ms | 8.9% | Intermittent pacing |
| **`MID`** | 520 ms | 80 ms | 15.4% | Distinct guide pulse |
| **`NEAR`** | 300 ms | 80 ms | 26.7% | Fast guide pulse |
| **`VERY_NEAR`**| 160 ms | 80 ms | 50.0% | Intense proximity buzz |
| **`REACHED`** | Continuous | 700 ms | 100% (one-shot) | Solid completion confirmation |

---

## 3. Vision & Horizontal FOV Calibration

Smartphone camera frames are normalized between $0.0$ (left edge of screen) and $1.0$ (right edge of screen) in portrait mode.

$$\text{normalizedX} = \frac{x_{\min} + x_{\max}}{2}$$

```text
0.0                0.35                     0.65                1.0
 |<--- LEFT ZONE --->|<---- CENTER ZONE ---->|<--- RIGHT ZONE --->|
   Left Motor Buzz        Both Motors Buzz         Right Motor Buzz
```

- **`kLeftMax = 0.35`**: Centroids $< 0.35$ classify as `Dir.left`.
- **`kRightMin = 0.65`**: Centroids $> 0.65$ classify as `Dir.right`.
- **Center Deadband ($[0.35, 0.65]$)**: Prevents rapid alternating left/right steering jitter when walking toward a centered object.

---

## 4. Debouncing & Filtering Parameters

| Filter / Debounce | Window | Action |
| :--- | :--- | :--- |
| **Ultrasonic Median Filter** | 3 samples (60 ms cadence) | Rejects transient acoustic reflections, multipath, and dropouts |
| **Camera Direction Hysteresis** | 2 ticks (~400 ms) | Direction must persist for 2 consecutive ticks before updating UI/voice |
| **Target Miss Debounce** | 3 camera frames | Direction resets to `Dir.none` only after 3 consecutive frames with no target |
| **Target Reached Condition** | Centered + Near held for $\ge 3$ ticks (~600 ms) | Prevents premature "Reached" triggers from transient hand movements |
| **Command Watchdog** | 1500 ms without BLE write | Safety failsafe: ESP32 motors automatically power down |
