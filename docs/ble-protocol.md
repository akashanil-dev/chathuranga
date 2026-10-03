# SENSE Bluetooth Low Energy (BLE) Wire Protocol

This document details the communication protocol between the SENSE Flutter mobile application and the ESP32 wristband.

---

## 1. BLE Service & Characteristic Identifiers

Both endpoints use standard 128-bit custom UUIDs:

| Entity | UUID | Properties | Description |
| :--- | :--- | :--- | :--- |
| **Device Name** | `SENSE-WRIST-01` | — | Advertised local device name |
| **Primary Service** | `5e45a001-1000-4a5e-9e5e-5e45e5e5e5e5` | — | Root SENSE GATT service |
| **Sensor Characteristic** | `5e45a002-1000-4a5e-9e5e-5e45e5e5e5e5` | `READ`, `NOTIFY` | ESP32 $\rightarrow$ Phone telemetry |
| **Haptic Characteristic** | `5e45a003-1000-4a5e-9e5e-5e45e5e5e5e5` | `WRITE`, `WRITE_NR` | Phone $\rightarrow$ ESP32 haptic commands |

*(Note: `WRITE_WITHOUT_RESPONSE` (`WRITE_NR`) is preferred for lowest transmission latency).*

---

## 2. Packet Specifications

### A. Phone $\rightarrow$ ESP32 Haptic Command (3 Bytes)

Sent periodically (~200 ms) and immediately upon state transitions.

```text
+----------------+----------------+----------------+
|  Byte 0 (Dir)  | Byte 1 (Close) | Byte 2 (State) |
+----------------+----------------+----------------+
```

#### Byte 0: Direction (`Dir`)
| Value | Enumeration | Description | ESP32 Haptic Action |
| :---: | :--- | :--- | :--- |
| `0` | `NONE` | Target not visible / searching | Both motors OFF |
| `1` | `LEFT` | Target is in left third of viewfinder | Pulse Left Motor (GPIO 25) |
| `2` | `RIGHT` | Target is in right third of viewfinder | Pulse Right Motor (GPIO 26) |
| `3` | `UP` | Reserved (elevation guidance) | No motor action (MVP) |
| `4` | `DOWN` | Reserved (elevation guidance) | No motor action (MVP) |
| `5` | `CENTERED` | Target is in center third | Pulse Both Motors synchronously |

#### Byte 1: Closeness (`Closeness`)
Calculated from ultrasonic distance. *(Note: The ESP32's local sensor measurement overrides this value for pulse frequency if ultrasonic readings are active).*

| Value | Enumeration | Distance Threshold | Pulse Period (`PERIOD_MS`) |
| :---: | :--- | :--- | :--- |
| `0` | `FAR` | $\ge 100\text{ cm}$ or no echo | 900 ms |
| `1` | `MID` | $< 100\text{ cm}$ and $\ge 60\text{ cm}$ | 520 ms |
| `2` | `NEAR` | $< 60\text{ cm}$ and $\ge 30\text{ cm}$ | 300 ms |
| `3` | `VERY_NEAR`| $< 30\text{ cm}$ | 160 ms |

Pulse duration is fixed at `ON_MS = 80 ms`.

#### Byte 2: State (`GState`)
| Value | Enumeration | Meaning | Haptic Behavior |
| :---: | :--- | :--- | :--- |
| `0` | `SEARCHING` | Target not yet locked | Standard directional pulsing |
| `1` | `APPROACHING`| Target locked and tracking | Cadence-modulated pulsing |
| `2` | `REACHED` | Centered & verified $< 60\text{ cm}$ | Solid 700 ms dual-motor confirmation buzz |

---

### B. ESP32 $\rightarrow$ Phone Sensor Telemetry (3 Bytes)

Notified to the mobile application every 100 ms.

```text
+--------------------+--------------------+--------------------+
| Byte 0 (Dist Lo)   | Byte 1 (Dist Hi)   | Byte 2 (Closeness) |
+--------------------+--------------------+--------------------+
```

- **Byte 0 (`Dist Lo`)**: Lower byte of measured distance in centimeters (`distCm & 0xFF`).
- **Byte 1 (`Dist Hi`)**: Upper byte of measured distance in centimeters (`(distCm >> 8) & 0xFF`).
- **Byte 2 (`Closeness`)**: Current closeness classification index (`0` to `3`).

---

## 3. Reliability & Fail-Safe Mechanisms

1. **Command Timeout (`CMD_TIMEOUT_MS = 1500 ms`)**:
   If the ESP32 does not receive a haptic write within 1.5 seconds (e.g., app crash, BLE disconnection, or out-of-range), it immediately shuts off both motors to prevent continuous buzzing.
2. **Edge-Triggered Arrival Buzz**:
   Transitioning into `S_REACHED` triggers an edge-sensitive 700 ms buzz that runs without interruption.
3. **Double Dispatch on Arrival**:
   The phone sends a redundant `S_REACHED` command 300 ms after the initial packet to ensure arrival confirmation is received even if an unacknowledged BLE packet drops.
