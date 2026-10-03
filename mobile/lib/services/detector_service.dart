import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const double kConfidenceThreshold = 0.5;

class DetectionResult {
  final Rect box; // In normalized portrait coordinates (0..1)
  final String label;
  final double score;

  DetectionResult({
    required this.box,
    required this.label,
    required this.score,
  });
}

class DetectorService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _initialized = false;

  bool get isReady => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/ssd_mobilenet.tflite');
      final labelData = await rootBundle.loadString('assets/models/labelmap.txt');
      _labels = labelData
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      _initialized = true;
    } catch (e) {
      debugPrint('Failed to load TFLite detector: $e');
    }
  }

  /// Converts CameraImage (YUV420) to 1x300x300x3 Uint8List in upright portrait orientation
  Uint8List _convertYUV420ToRGB300(CameraImage image, int sensorOrientation) {
    final int w = image.width;
    final int h = image.height;
    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final int yRowStride = image.planes[0].bytesPerRow;
    final int uRowStride = image.planes[1].bytesPerRow;
    final int vRowStride = image.planes[2].bytesPerRow;
    final int uPixelStride = image.planes[1].bytesPerPixel ?? 1;
    final int vPixelStride = image.planes[2].bytesPerPixel ?? 1;

    final out = Uint8List(1 * 300 * 300 * 3);
    int outIndex = 0;

    for (int ty = 0; ty < 300; ty++) {
      final double normY = ty / 299.0;
      for (int tx = 0; tx < 300; tx++) {
        final double normX = tx / 299.0;

        int sx, sy;
        if (sensorOrientation == 90) {
          sx = (normY * (w - 1)).round();
          sy = ((1.0 - normX) * (h - 1)).round();
        } else if (sensorOrientation == 270) {
          sx = ((1.0 - normY) * (w - 1)).round();
          sy = (normX * (h - 1)).round();
        } else {
          sx = (normX * (w - 1)).round();
          sy = (normY * (h - 1)).round();
        }

        final int yIndex = sy * yRowStride + sx;
        final int uvX = sx >> 1;
        final int uvY = sy >> 1;
        final int uIndex = uvY * uRowStride + uvX * uPixelStride;
        final int vIndex = uvY * vRowStride + uvX * vPixelStride;

        final int yVal = yPlane[yIndex];
        final int uVal = uPlane[uIndex] - 128;
        final int vVal = vPlane[vIndex] - 128;

        int r = yVal + ((1436 * vVal) >> 10);
        int g = yVal - ((352 * uVal + 731 * vVal) >> 10);
        int b = yVal + ((1815 * uVal) >> 10);

        out[outIndex++] = r < 0 ? 0 : (r > 255 ? 255 : r);
        out[outIndex++] = g < 0 ? 0 : (g > 255 ? 255 : g);
        out[outIndex++] = b < 0 ? 0 : (b > 255 ? 255 : b);
      }
    }

    return out;
  }

  DetectionResult? detect(CameraImage image, int sensorOrientation, String targetLabel) {
    if (!_initialized || _interpreter == null) return null;

    final input = _convertYUV420ToRGB300(image, sensorOrientation);

    // Outputs for SSD MobileNet:
    // 0: Locations [1, 10, 4]
    // 1: Classes [1, 10]
    // 2: Scores [1, 10]
    // 3: Count [1]
    final outputLocations = List.generate(
      1,
      (_) => List.generate(10, (_) => List.filled(4, 0.0)),
    );
    final outputClasses = List.generate(1, (_) => List.filled(10, 0.0));
    final outputScores = List.generate(1, (_) => List.filled(10, 0.0));
    final numDetections = List.filled(1, 0.0);

    _interpreter!.runForMultipleInputs(
      [input],
      {
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: numDetections,
      },
    );

    final int count = numDetections[0].toInt().clamp(0, 10);
    DetectionResult? best;
    double maxScore = kConfidenceThreshold;

    for (int i = 0; i < count; i++) {
      final double score = outputScores[0][i];
      if (score < maxScore) continue;

      final int classId = outputClasses[0][i].round();
      String label = '';
      if (classId >= 0 && classId < _labels.length) {
        label = _labels[classId];
      }
      if (label != targetLabel && classId - 1 >= 0 && classId - 1 < _labels.length) {
        if (_labels[classId - 1] == targetLabel) {
          label = _labels[classId - 1];
        }
      }

      if (label == targetLabel && score > maxScore) {
        maxScore = score;
        final loc = outputLocations[0][i];
        final top = loc[0].clamp(0.0, 1.0);
        final left = loc[1].clamp(0.0, 1.0);
        final bottom = loc[2].clamp(0.0, 1.0);
        final right = loc[3].clamp(0.0, 1.0);
        best = DetectionResult(
          box: Rect.fromLTRB(left, top, right, bottom),
          label: label,
          score: score,
        );
      }
    }

    return best;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _initialized = false;
  }
}
