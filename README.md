# SENSE — AI-Powered Assistive Object Finder

An assistive technology prototype designed for visually impaired individuals to locate everyday objects (keys, water bottle, phone) using voice commands, real-time computer vision guidance, and directional haptic feedback through an ESP32 wearable wristband.

---

## System Architecture

```text
                  ┌───────────────────┐
                  │       USER        │
                  │  Voice + Hearing  │
                  └─────────┬─────────┘
                            │
                            ▼
                 ┌─────────────────────┐
                 │    Android Phone    │
                 │      (Flutter)      │
                 │                     │
                 │ • Speech-to-Text    │
                 │ • Camera Capture    │
                 │ • Object Detection  │
                 │ • Guidance Engine   │
                 │ • Text-to-Speech    │
                 │ • BLE Central       │
                 └───────┬─────┬───────┘
                         │     │
                   HTTPS │     │ BLE
                         │     │
                         ▼     ▼
                ┌────────────┐ ┌─────────────┐
                │  Backend   │ │    ESP32    │
                │  (FastAPI) │ │  Wristband  │
                │ Claude API │ │             │
                └────────────┘ │ • ToF       │
                               │ • Vibration │
                               └─────────────┘
```

---

## Project Structure

- **[`mobile/`](file:///home/akash/Documents/chathuranga/mobile)**: Flutter Android application.
  - High-contrast, accessible UI (single-tap anywhere to speak, double-tap to cancel).
  - On-device local object detection (Google ML Kit / fallback).
  - Spatial guidance calculation (`LEFT`, `CENTER`, `RIGHT`, `NEAR`).
  - BLE communication with the ESP32 wristband.
  - Developer HUD for testing and hackathon judging demonstrations.
- **[`backend/`](file:///home/akash/Documents/chathuranga/backend)**: Lightweight FastAPI service interfacing with Anthropic Claude for natural language intent understanding (`FIND_OBJECT`, `STOP`, `HELP`).
- **[`firmware/esp32_wristband/`](file:///home/akash/Documents/chathuranga/firmware/esp32_wristband/esp32_wristband.ino)**: Arduino C++ sketch for ESP32 BLE peripheral with dual-motor haptics and ToF distance sensor support.

---

## How to Run

### 1. Start the Backend

```bash
cd backend
source venv/bin/activate
# Optional: Set your Claude API key in backend/.env
# ANTHROPIC_API_KEY=your_key_here
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Run the Flutter Mobile App

```bash
cd mobile
flutter run
```

### 3. Flash the ESP32 Firmware

Open [`firmware/esp32_wristband/esp32_wristband.ino`](file:///home/akash/Documents/chathuranga/firmware/esp32_wristband/esp32_wristband.ino) in Arduino IDE or PlatformIO, select your ESP32 board, and flash.
