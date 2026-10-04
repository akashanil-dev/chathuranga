# SENSE — AI-Powered Assistive Object Finder

SENSE is an assistive-technology prototype that helps people with visual impairments locate everyday objects using voice commands, camera-based AI guidance, spoken feedback, and haptic cues from an ESP32 wristband.

## What it does

- Accepts a voice request such as “find my keys”.
- Analyses camera frames to locate the requested object.
- Guides the user with `LEFT`, `CENTER`, `RIGHT`, `NEAR`, and `TOUCHING` instructions.
- Speaks guidance through the mobile app and relays haptic commands to a Bluetooth Low Energy (BLE) wristband.
- Uses a local Qwen3-VL model through Ollama first, with Anthropic Claude Vision as an optional fallback.

## Architecture

```text
Voice + camera
      |
Flutter mobile app  <---- BLE ---->  ESP32 wristband
      |
      | HTTP
      v
FastAPI backend
  ├─ Local Qwen3-VL via Ollama (primary)
  └─ Claude Vision API (optional fallback)
```

The backend converts the detected bounding box into deterministic guidance commands, so the wearable receives the same consistent signal regardless of the vision provider.

## Repository layout

| Directory | Purpose |
| --- | --- |
| `mobile/` | Flutter Android app: accessibility UI, speech, camera, BLE, and audio feedback |
| `backend/` | FastAPI API, object-intent parsing, vision providers, and guidance rules |
| `firmware/esp32_wristband/` | ESP32 Arduino sketch for the BLE haptic wristband and ultrasonic sensor |

## Prerequisites

- Flutter SDK and Android development tools
- Python 3.10 or later
- [Ollama](https://ollama.com/) with the `qwen3-vl:2b` model for local vision
- Arduino IDE or `arduino-cli` with the ESP32 board package (for the wristband)
- An Anthropic API key only if you want cloud vision fallback

## Run the backend

```powershell
# Install and prepare the local vision model (one time)
ollama pull qwen3-vl:2b

cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
# Edit .env and set ANTHROPIC_API_KEY if using Claude fallback
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Check that the service is ready at `http://127.0.0.1:8000/health`.

Key environment variables are documented in [`backend/.env.example`](backend/.env.example). Set `LOCAL_VLM_ENABLED=false` to use Claude only, or leave `ANTHROPIC_API_KEY` unset to use local vision only.

## Run the mobile app

```powershell
cd mobile

# USB device: make the phone's localhost:8000 reach the development machine
adb reverse tcp:8000 tcp:8000
flutter run

# Wi-Fi device: use the development machine's LAN address
flutter run --dart-define=BACKEND_URL=http://<your-pc-lan-ip>:8000
```

Enable Bluetooth and grant microphone, camera, and nearby-device permissions when Android asks.

## Flash the wristband

Open [`firmware/esp32_wristband/esp32_wristband.ino`](firmware/esp32_wristband/esp32_wristband.ino) in Arduino IDE, select **ESP32 Dev Module**, then upload. Alternatively:

```powershell
arduino-cli compile --fqbn esp32:esp32:esp32 firmware/esp32_wristband
arduino-cli upload -p COMx --fqbn esp32:esp32:esp32 firmware/esp32_wristband
```

### Wiring

| Component | ESP32 pin | Notes |
| --- | --- | --- |
| Vibration motor | GPIO 18 | Drive through an NPN transistor or logic-level MOSFET; add a flyback diode |
| HC-SR04 VCC / GND | 5V (VIN) / GND | |
| HC-SR04 TRIG | GPIO 5 | |
| HC-SR04 ECHO | GPIO 17 | Use a voltage divider; the sensor echo output is 5 V |
| Status LED | GPIO 2 | On-board LED; lit while the phone is connected |

The serial monitor runs at 115200 baud. You can enter `LEFT`, `RIGHT`, `CENTER`, `NEAR`, `TOUCHING`, or `STOP` to test haptic patterns without the mobile app.

## License

This project is licensed under the [MIT License](LICENSE).
