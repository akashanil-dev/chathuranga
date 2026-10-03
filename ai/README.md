# SENSE AI & Computer Vision Subsystem

This directory contains the computer vision models, label sets, and inference specifications used by the SENSE assistive object-finding application.

---

## 1. Overview & Architecture

The vision pipeline is designed for **100% on-device, offline inference** on Android smartphones with zero external network calls, zero API keys, and zero cloud latency.

```text
Camera Frame (YUV420)
       ↓
Orientation Correction & Color Conversion (YUV → RGB, 300×300)
       ↓
TFLite SSD MobileNet v1 Interpreter (Quantized uint8)
       ↓
Detections (Boxes [yMin, xMin, yMax, xMax], Classes, Scores)
       ↓
Target Filtering & Confidence Threshold (Score >= 0.5)
       ↓
Spatial Centroid Calculation (normalizedX = (xMin + xMax) / 2)
       ↓
Zone Partitioning (LEFT < 0.35, CENTER 0.35..0.65, RIGHT > 0.65)
       ↓
Debounce Logic (3-miss failsafe)
       ↓
GuidanceEngine.setInput(Dir)
```

---

## 2. Bundled Model Details

| Attribute | Specification |
| :--- | :--- |
| **Model Architecture** | SSD MobileNet v1 (Single Shot MultiBox Detector) |
| **Quantization** | Full integer post-training quantization (`uint8`) |
| **Input Shape** | `[1, 300, 300, 3]` (RGB normalized to 0..255) |
| **Output Tensors** | 1. Bounding Boxes `[1, 10, 4]` (float: `[ymin, xmin, ymax, xmax]`)<br>2. Class IDs `[1, 10]` (float index)<br>3. Confidence Scores `[1, 10]` (float 0.0..1.0)<br>4. Number of detections `[1]` (float count) |
| **File Size** | 4.18 MB (`ssd_mobilenet.tflite`) |
| **Inference Latency** | ~35–65 ms on standard Android ARM64 CPU |
| **Runtime Dependencies** | `tflite_flutter: ^0.12.1` |

---

## 3. Supported Target Classes

The model is trained on the standard 90-class Microsoft COCO dataset (`labelmap.txt`).

SENSE currently targets everyday items verified present in the COCO label map:
- **`PHONE`** $\rightarrow$ mapped to `cell phone` (COCO ID: 76)
- **`BOTTLE`** $\rightarrow$ mapped to `bottle` (COCO ID: 43)
- **`CUP`** $\rightarrow$ mapped to `cup` (COCO ID: 46)

*(Note: Items such as keys and wallets are not standard COCO categories and are omitted to avoid false positive hallucinations. Custom fine-tuned models can be dropped into `assets/models/` without changing the app's guidance engine interface).*

---

## 4. Directional Spatial Reasoning

1. **Sensor Orientation Transformation**:
   Android back-camera sensors typically report image frames rotated 90° clockwise relative to the upright portrait phone orientation. Preprocessing rotates and maps pixel buffers so coordinates match user perspective:
   $$\text{Screen } X = \text{Frame } Y, \quad \text{Screen } Y = 1.0 - \text{Frame } X$$

2. **Centroid Normalization**:
   For the highest-confidence bounding box of the selected target above the threshold ($s \ge 0.5$):
   $$\text{normalizedX} = \frac{x_{\min} + x_{\max}}{2}$$

3. **Horizontal Field-of-View (FOV) Partitioning**:
   - $\text{normalizedX} < 0.35 \implies \mathbf{Dir.left}$ (triggers left wrist vibration)
   - $\text{normalizedX} > 0.65 \implies \mathbf{Dir.right}$ (triggers right wrist vibration)
   - $0.35 \le \text{normalizedX} \le 0.65 \implies \mathbf{Dir.centered}$ (triggers dual wrist vibration)

4. **Temporal Debouncing**:
   - If the selected target is not detected for **3 consecutive frames**, `GuidanceEngine.setInput(Dir.none)` is emitted to prevent phantom steering commands.
   - Processing is throttled to 5–10 FPS, dropping incoming camera frames while an inference cycle is active to prevent thermal throttling and maintain responsive UI rendering.
