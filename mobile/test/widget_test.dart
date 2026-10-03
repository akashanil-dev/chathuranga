import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/audio_feedback_service.dart';
import 'package:mobile/core/types/direction.dart';
import 'package:mobile/features/finding/controllers/find_session_controller.dart';
import 'package:mobile/features/guidance/services/guidance_engine.dart';
import 'package:mobile/features/intent/services/intent_client.dart';
import 'package:mobile/features/vision/models/detection_result.dart';
import 'package:mobile/features/voice/services/speech_service.dart';
import 'package:mobile/features/wearable/services/ble_wearable_service.dart';
import 'package:mobile/main.dart';
import 'package:flutter/material.dart';

void main() {
  group('Guidance Engine Unit Tests', () {
    final engine = GuidanceEngine();

    test('Object on left produces LEFT guidance and haptic', () {
      final output = engine.processDetections(
        target: 'keys',
        detections: [
          DetectionResult(
            label: 'keys',
            confidence: 0.90,
            boundingBox: const Rect.fromLTWH(0.1, 0.3, 0.15, 0.15), // cx = 0.175 (< 0.35)
          ),
        ],
      );

      expect(output.detected, true);
      expect(output.imagePosition, 'left');
      expect(output.direction, Direction.left);
      expect(output.hapticCommand, HapticCommand.left);
      expect(output.voiceMessage, contains('left'));
    });

    test('Object on right produces RIGHT guidance and haptic', () {
      final output = engine.processDetections(
        target: 'keys',
        detections: [
          DetectionResult(
            label: 'keys',
            confidence: 0.88,
            boundingBox: const Rect.fromLTWH(0.75, 0.3, 0.15, 0.15), // cx = 0.825 (> 0.65)
          ),
        ],
      );

      expect(output.detected, true);
      expect(output.imagePosition, 'right');
      expect(output.direction, Direction.right);
      expect(output.hapticCommand, HapticCommand.right);
      expect(output.voiceMessage, contains('right'));
    });

    test('Object in middle produces CENTER guidance and haptic', () {
      final output = engine.processDetections(
        target: 'keys',
        detections: [
          DetectionResult(
            label: 'keys',
            confidence: 0.95,
            boundingBox: const Rect.fromLTWH(0.42, 0.3, 0.16, 0.16), // cx = 0.50
          ),
        ],
      );

      expect(output.detected, true);
      expect(output.imagePosition, 'center');
      expect(output.direction, Direction.center);
      expect(output.hapticCommand, HapticCommand.center);
      expect(output.voiceMessage, contains('Straight ahead'));
    });

    test('Proximity sensor or large box produces NEAR guidance and distinct haptic', () {
      final output = engine.processDetections(
        target: 'keys',
        detections: [
          DetectionResult(
            label: 'keys',
            confidence: 0.95,
            boundingBox: const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2),
          ),
        ],
        sensorDistanceCm: 12.0, // Sensor detects object < 20cm
      );

      expect(output.detected, true);
      expect(output.direction, Direction.near);
      expect(output.hapticCommand, HapticCommand.near);
      expect(output.voiceMessage, contains('Approaching'));
    });

    test('Proximity sensor <= 8cm produces TOUCHING guidance and continuous haptic', () {
      final engine = GuidanceEngine();
      final output = engine.processDetections(
        target: 'keys',
        detections: [
          DetectionResult(
            label: 'keys',
            confidence: 0.95,
            boundingBox: const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2),
          ),
        ],
        sensorDistanceCm: 5.0, // Sensor detects object <= 8cm
      );

      expect(output.detected, true);
      expect(output.direction, Direction.touching);
      expect(output.hapticCommand, HapticCommand.touching);
      expect(output.voiceMessage, contains('Target reached'));
    });
  });

  group('Intent Client Rule Fallback Tests', () {
    final client = IntentClient();

    test('Extracts keys from "Find my keys"', () async {
      final intent = await client.parseIntent('Find my keys');
      expect(intent.action, 'FIND_OBJECT');
      expect(intent.target, 'keys');
    });

    test('Extracts water bottle from "Where is my water bottle?"', () async {
      final intent = await client.parseIntent('Where is my water bottle?');
      expect(intent.action, 'FIND_OBJECT');
      expect(intent.target, 'water bottle');
    });

    test('Extracts STOP action from "Stop"', () async {
      final intent = await client.parseIntent('Stop');
      expect(intent.action, 'STOP');
    });
  });

  testWidgets('SenseApp UI smoke test', (WidgetTester tester) async {
    final controller = FindSessionController(
      speechService: SpeechService(),
      audioService: AudioFeedbackService(),
      intentClient: IntentClient(),
      wearableService: MockWearableService(),
    );

    await tester.pumpWidget(SenseApp(controller: controller));

    // Verify initial accessible elements
    expect(find.text('TAP TO SEARCH'), findsOneWidget);
    expect(find.text('TAP SCREEN TO START'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}
