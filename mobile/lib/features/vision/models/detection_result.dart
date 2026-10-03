import 'dart:ui';

class DetectionResult {
  final String label;
  final double confidence;
  final Rect boundingBox; // Normalized: left, top, right, bottom in [0.0, 1.0]

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  double get centerX => (boundingBox.left + boundingBox.right) / 2.0;
  double get centerY => (boundingBox.top + boundingBox.bottom) / 2.0;
  double get areaRatio => boundingBox.width * boundingBox.height;

  @override
  String toString() =>
      'DetectionResult(label: $label, conf: ${confidence.toStringAsFixed(2)}, center: (${centerX.toStringAsFixed(2)}, ${centerY.toStringAsFixed(2)}))';
}
