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
      debugPrint('ML Kit detection error: $e');
      return [];
    }
  }

  InputImage? _buildInputImage(CameraImage image, int rotationDegrees) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
          InputImageRotation.rotation0deg;

      // Concatenate all planes (Y + U + V) into a single buffer
      final allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('_buildInputImage error: $e');
      return null;
    }
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
