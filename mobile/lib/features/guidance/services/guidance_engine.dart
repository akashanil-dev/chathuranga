import '../../../core/constants/app_constants.dart';
import '../../../core/types/direction.dart';
import '../../vision/models/detection_result.dart';
import '../models/guidance_output.dart';

class GuidanceEngine {
  Direction _lastDirection = Direction.none;
  DateTime _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHapticTime = DateTime.fromMillisecondsSinceEpoch(0);

  Direction get lastDirection => _lastDirection;

  GuidanceOutput processDetections({
    required String target,
    required List<DetectionResult> detections,
    double? sensorDistanceCm,
  }) {
    final cleanTarget = target.trim().toLowerCase();

    // Find best match among detections
    DetectionResult? matched;
    for (final d in detections) {
      final label = d.label.toLowerCase();
      if (label.contains(cleanTarget) || cleanTarget.contains(label)) {
        matched = d;
        break;
      }
    }

    // If no exact label match, pick highest confidence detection as candidate
    matched ??= detections.isNotEmpty
        ? detections.reduce((curr, next) => curr.confidence > next.confidence ? curr : next)
        : null;

    if (matched == null) {
      _lastDirection = Direction.none;
      return GuidanceOutput(
        target: cleanTarget,
        detected: false,
        direction: Direction.none,
        imagePosition: 'none',
        voiceMessage: 'Scanning for $cleanTarget...',
        hapticCommand: HapticCommand.stop,
        proximity: 'unknown',
      );
    }

    // Determine horizontal position
    final cx = matched.centerX;
    final areaRatio = matched.areaRatio;

    Direction direction;
    String position;
    String voice;
    HapticCommand haptic;

    // Check proximity (touching <= 8cm, near <= 25cm, or large visual box)
    String proximity = 'unknown';
    if (sensorDistanceCm != null) {
      proximity = '${sensorDistanceCm.toStringAsFixed(1)} cm';
    }

    final isSensorTouching = sensorDistanceCm != null && sensorDistanceCm <= 8.0;
    final isSensorNear = sensorDistanceCm != null && sensorDistanceCm <= 25.0;
    final isVisualNear = areaRatio >= AppConstants.nearAreaRatioThreshold;

    if (isSensorTouching) {
      direction = Direction.touching;
      position = 'center';
      voice = 'Target reached! Right beneath your hand.';
      haptic = HapticCommand.touching;
    } else if (isSensorNear || isVisualNear) {
      direction = Direction.near;
      position = cx < AppConstants.leftThreshold
          ? 'left'
          : (cx > AppConstants.rightThreshold ? 'right' : 'center');
      voice = 'Approaching $cleanTarget. Reach forward slowly.';
      haptic = HapticCommand.near;
      if (proximity == 'unknown' && isVisualNear) {
        proximity = 'close (visual)';
      }
    } else if (cx < AppConstants.leftThreshold) {
      direction = Direction.left;
      position = 'left';
      voice = 'The $cleanTarget appears to your left.';
      haptic = HapticCommand.left;
    } else if (cx > AppConstants.rightThreshold) {
      direction = Direction.right;
      position = 'right';
      voice = 'The $cleanTarget appears to your right.';
      haptic = HapticCommand.right;
    } else {
      direction = Direction.center;
      position = 'center';
      voice = 'Straight ahead. The $cleanTarget is in front of you.';
      haptic = HapticCommand.center;
    }

    _lastDirection = direction;

    return GuidanceOutput(
      target: cleanTarget,
      detected: true,
      direction: direction,
      imagePosition: position,
      voiceMessage: voice,
      hapticCommand: haptic,
      proximity: proximity,
      confidence: matched.confidence,
    );
  }

  /// Evaluates whether a voice message should be spoken based on direction change and debouncing
  bool shouldSpeak(Direction newDirection) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastSpokenTime);

    // If direction changed significantly (e.g. Left -> Center or Center -> Near), allow speech faster
    final bool directionChanged = newDirection != _lastDirection;
    final minInterval = directionChanged
        ? const Duration(milliseconds: 1400)
        : AppConstants.speechDebounceDuration;

    if (elapsed >= minInterval) {
      _lastSpokenTime = now;
      return true;
    }
    return false;
  }

  /// Evaluates whether a haptic command should be transmitted
  bool shouldSendHaptic() {
    final now = DateTime.now();
    if (now.difference(_lastHapticTime) >= AppConstants.hapticCooldown) {
      _lastHapticTime = now;
      return true;
    }
    return false;
  }

  void reset() {
    _lastDirection = Direction.none;
    _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastHapticTime = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
