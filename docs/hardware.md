# SENSE Hardware & Circuit Documentation

This document describes the wearable smart wristband hardware design, pin mapping, driver circuits, and critical electrical protection requirements for the SENSE ESP32 wristband.

---

## 1. Bill of Materials (BOM)

| Component | Quantity | Purpose |
| :--- | :---: | :--- |
| **ESP32 DevKit V1** (30-pin or 38-pin) | 1 | Microcontroller with built-in BLE 4.2 / 5.0 |
| **HC-SR04 or RCWL-1601** Ultrasonic Sensor | 1 | Real-time obstacle and target proximity detection |
| **Coin Vibration Motors (ERM)** (3V, 10mm) | 2 | Directional haptic feedback (Left & Right) |
| **NPN Transistors** (2N2222 / 2N3904 or N-channel MOSFETs) | 2 | Motor switching drivers |
| **Flyback Diodes** (1N4148 or 1N4001) | 2 | Inductive kickback suppression across motor terminals |
| **Resistors** (1 kΩ) | 3 | Base current limiting (2×) + Voltage divider top (1×) |
| **Resistors** (2 kΩ) | 1 | Voltage divider bottom (Echo line level shift) |
| **Battery Source** (3.7V LiPo + 5V Step-Up or 5V Powerbank) | 1 | Portable wristband power |

---

## 2. GPIO Pin Assignments

The pins configured in [`firmware/sense_wrist/sense_wrist.ino`](file:///C:/Users/nashw/.gemini/antigravity/scratch/sense/firmware/sense_wrist/sense_wrist.ino) are:

| Function | ESP32 GPIO | Direction | Notes |
| :--- | :---: | :---: | :--- |
| **HC-SR04 Trigger** | `GPIO 5` | Output | 10 µs active-HIGH trigger pulse |
| **HC-SR04 Echo** | `GPIO 18` | Input | **Must use voltage divider** (step 5 V down to 3.3 V) |
| **Left Vibration Motor** | `GPIO 25` | Output | Active-HIGH drive through transistor |
| **Right Vibration Motor** | `GPIO 26` | Output | Active-HIGH drive through transistor |

---

## 3. Critical Voltage Protection: HC-SR04 Echo Line

> [!CAUTION]
> The HC-SR04 ultrasonic sensor operates at **5 V $V_{CC}$**. Its `ECHO` output pin drives a **5 V digital signal**. Connecting the 5 V Echo output directly to the ESP32 input pin (`GPIO 18`) can permanently damage the ESP32's 3.3 V-tolerant GPIO.

### Voltage Divider Circuit
Use a simple two-resistor voltage divider to shift the 5 V signal down to approximately 3.3 V:

```text
HC-SR04 ECHO (5 V) ───[ 1 kΩ ]───┬───> ESP32 GPIO 18 (~3.3 V)
                                 │
                              [ 2 kΩ ]
                                 │
                                GND
```

$$\text{V}_{\text{ESP32}} = 5\text{ V} \times \frac{2\text{ k}\Omega}{1\text{ k}\Omega + 2\text{ k}\Omega} = 5\text{ V} \times \frac{2}{3} \approx 3.33\text{ V}$$

*(Alternatively, modern 3.3V-compatible ultrasonic sensors such as the **RCWL-1601** or **US-100** running in 3.3V mode can be used directly without a divider).*

---

## 4. Motor Driver Circuit (Transistor / MOSFET)

The ESP32 GPIO pins can source a maximum of ~12–20 mA, whereas small coin vibration motors typically draw 60–100 mA at 3 V to 5 V. Driving motors directly from GPIOs will cause brownouts or burn the pins.

### NPN Transistor Driver Schematic (Per Motor)

```text
           +3.3V / +5V (VCC)
                 │
                 ├───[ + ] Vibration Motor
                 │           │
                 │          [ - ]
                 │           ├───[ Cathode: 1N4148 Diode (facing VCC) ]───┐
                 │           │                                             │
                 │           └─────────────────────────────────────────────┤ (Anode)
                 │                                                         │
                 │                                                Collector (C)
ESP32 GPIO ─────[ 1 kΩ Base Resistor ]───────────────────────── Base (B)  NPN (2N2222)
(Pin 25 or 26)                                                    Emitter (E)
                                                                       │
                                                                      GND
```

- **Base Resistor (1 kΩ)**: Limits base current from the ESP32 GPIO to safe levels (~2.6 mA).
- **Flyback Diode (1N4148)**: Absorbs high-voltage inductive spikes generated when the motor coil is switched off, shielding the transistor from breakdown.

---

## 5. Boot Self-Test Routine

Upon boot, the firmware runs `selfTest()`:
1. Pulses Left Motor for 250 ms $\rightarrow$ pauses 150 ms.
2. Pulses Right Motor for 250 ms $\rightarrow$ shuts off.

This provides instant tactile feedback to the user that the hardware and motor circuits are functioning correctly before BLE pairing begins.
