import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart' as mlkit;
import '../models/detection_result.dart';

abstract class ObjectDetector {
  Future<List<DetectionResult>> detectFromCamera(CameraImage image, int sensorOrientation);
  Future<void> dispose();
}

class MlKitObjectDetector implements ObjectDetector {
  late final mlkit.ObjectDetector _detector;
  bool _isDisposed = false;
  int _consecutiveErrors = 0;

  MlKitObjectDetector() {
    final options = mlkit.ObjectDetectorOptions(
      mode: mlkit.DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _detector = mlkit.ObjectDetector(options: options);
  }

  @override
  Future<List<DetectionResult>> detectFromCamera(
    CameraImage image,
    int sensorOrientation,
  ) async {
    if (_isDisposed) return [];

    try {
      final inputImage = _buildInputImage(image, sensorOrientation);
      if (inputImage == null) return [];

      final objects = await _detector.processImage(inputImage);
      _consecutiveErrors = 0;
      final results = <DetectionResult>[];

      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();

      for (final obj in objects) {
        String label = 'object';
        double confidence = 0.5;

        if (obj.labels.isNotEmpty) {
          final topLabel = obj.labels.first;
          label = topLabel.text.toLowerCase();
          confidence = topLabel.confidence;
        }

        // Normalize bounding box to [0.0, 1.0]
        final rect = obj.boundingBox;
        final normalizedRect = Rect.fromLTRB(
          (rect.left / imageWidth).clamp(0.0, 1.0),
          (rect.top / imageHeight).clamp(0.0, 1.0),
          (rect.right / imageWidth).clamp(0.0, 1.0),
          (rect.bottom / imageHeight).clamp(0.0, 1.0),
        );

        results.add(
          DetectionResult(
            label: label,
            confidence: confidence,
            boundingBox: normalizedRect,
          ),
        );
      }

      return results;
    } catch (e) {
      _consecutiveErrors++;
      if (_consecutiveErrors <= 3) {
        debugPrint('ML Kit detection error: $e');
      }
      return [];
    }
  }

  InputImage? _buildInputImage(CameraImage image, int rotationDegrees) {
    try {
      final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
          InputImageRotation.rotation0deg;

      Uint8List bytes;
      InputImageFormat format;
      int bytesPerRow;

      if (defaultTargetPlatform == TargetPlatform.android) {
        format = InputImageFormat.nv21;
        if (image.planes.length == 1) {
          // CameraX with ImageFormatGroup.nv21 outputs a single NV21 plane
          bytes = image.planes.first.bytes;
          bytesPerRow = image.planes.first.bytesPerRow;
        } else {
          // Fallback: convert 3 YUV_420_888 planes to NV21
          bytes = _yuv420ToNv21(image);
          bytesPerRow = image.width;
        }
      } else {
        format = InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.bgra8888;
        bytes = image.planes.first.bytes;
        bytesPerRow = image.planes.first.bytesPerRow;
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('_buildInputImage error: $e');
      return null;
    }
  }

  static Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final numPixels = (width * height * 1.5).toInt();
    final nv21 = Uint8List(numPixels);

    try {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBuffer = yPlane.bytes;
      final uBuffer = uPlane.bytes;
      final vBuffer = vPlane.bytes;

      final yRowStride = yPlane.bytesPerRow;
      int pos = 0;
      if (yRowStride == width) {
        final len = yBuffer.length < width * height ? yBuffer.length : width * height;
        nv21.setRange(0, len, yBuffer);
        pos = width * height;
      } else {
        for (int row = 0; row < height; row++) {
          final srcStart = row * yRowStride;
          if (srcStart + width <= yBuffer.length) {
            nv21.setRange(pos, pos + width, yBuffer, srcStart);
          }
          pos += width;
        }
      }

      final uvWidth = width ~/ 2;
      final uvHeight = height ~/ 2;
      final uRowStride = uPlane.bytesPerRow;
      final vRowStride = vPlane.bytesPerRow;
      final uPixelStride = uPlane.bytesPerPixel ?? 1;
      final vPixelStride = vPlane.bytesPerPixel ?? 1;

      for (int row = 0; row < uvHeight; row++) {
        final uRowStart = row * uRowStride;
        final vRowStart = row * vRowStride;
        for (int col = 0; col < uvWidth; col++) {
          final vIdx = vRowStart + col * vPixelStride;
          final uIdx = uRowStart + col * uPixelStride;
          if (pos < numPixels && vIdx < vBuffer.length && uIdx < uBuffer.length) {
            nv21[pos++] = vBuffer[vIdx];
            nv21[pos++] = uBuffer[uIdx];
          }
        }
      }
    } catch (e) {
      debugPrint('Error converting YUV420 to NV21: $e');
    }

    return nv21;
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _detector.close();
  }
}

class MockObjectDetector implements ObjectDetector {
  double simulatedX = 0.8; // Simulates an object on the right
  String simulatedLabel = 'keys';

  @override
  Future<List<DetectionResult>> detectFromCamera(
    CameraImage image,
    int sensorOrientation,
  ) async {
    return [
      DetectionResult(
        label: simulatedLabel,
        confidence: 0.92,
        boundingBox: Rect.fromLTWH(simulatedX - 0.1, 0.4, 0.2, 0.2),
      ),
    ];
  }

  @override
  Future<void> dispose() async {}
}
