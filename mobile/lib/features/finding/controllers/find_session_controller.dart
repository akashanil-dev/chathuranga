import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/services/audio_feedback_service.dart';
import '../../../core/types/direction.dart';
import '../../intent/services/intent_client.dart';
import '../../vision/models/detection_result.dart';
import '../../vision/services/object_detector.dart';
import '../../voice/services/speech_service.dart';
import '../../wearable/services/ble_wearable_service.dart';
import '../../guidance/models/guidance_output.dart';
import '../../guidance/services/guidance_engine.dart';

enum FindSessionState {
  idle,
  listening,
  parsingIntent,
  searching,
  guiding,
  nearTarget,
  completed,
  error,
}

class FindSessionController extends ChangeNotifier {
  final SpeechService speechService;
  final AudioFeedbackService audioService;
  final IntentClient intentClient;
  final WearableService wearableService;
  final GuidanceEngine guidanceEngine = GuidanceEngine();

  ObjectDetector? _objectDetector;
  CameraController? _cameraController;

  FindSessionState _state = FindSessionState.idle;
  String _targetObject = '';
  String _lastVoiceTranscript = '';
  GuidanceOutput? _currentGuidance;
  double? _latestSensorDistance;
  bool _isProcessingFrame = false;
  DateTime _lastDetectionTime = DateTime.now();

  FindSessionState get state => _state;
  String get targetObject => _targetObject;
  String get lastVoiceTranscript => _lastVoiceTranscript;
  GuidanceOutput? get currentGuidance => _currentGuidance;
  double? get latestSensorDistance => _latestSensorDistance;
  CameraController? get cameraController => _cameraController;

  FindSessionController({
    required this.speechService,
    required this.audioService,
    required this.intentClient,
    required this.wearableService,
  }) {
    _initWearable();
  }

  void _initWearable() {
    wearableService.distanceStream.listen((dist) {
      _latestSensorDistance = dist;
      notifyListeners();
    });
  }

  void setDetector(ObjectDetector detector) {
    _objectDetector = detector;
  }

  /// Start the entire flow: User taps anywhere on the screen
  Future<void> onUserTap() async {
    HapticFeedback.heavyImpact();

    if (_state == FindSessionState.idle || _state == FindSessionState.completed || _state == FindSessionState.error) {
      await startListening();
    } else if (_state == FindSessionState.listening) {
      await stopListening();
    }
  }

  /// Double tap cancels or resets the current search
  Future<void> onUserDoubleTap() async {
    HapticFeedback.mediumImpact();
    await resetToIdle(speakMessage: 'Search cancelled.');
  }

  Future<void> startListening() async {
    _state = FindSessionState.listening;
    _lastVoiceTranscript = '';
    notifyListeners();

    await audioService.speak('Listening. What would you like to find?');

    await speechService.startListening(
      onResult: (transcript, isFinal) async {
        _lastVoiceTranscript = transcript;
        notifyListeners();

        if (isFinal && transcript.trim().isNotEmpty) {
          await speechService.stopListening();
          await processVoiceInput(transcript);
        }
      },
    );
  }

  Future<void> stopListening() async {
    await speechService.stopListening();
    if (_lastVoiceTranscript.trim().isNotEmpty) {
      await processVoiceInput(_lastVoiceTranscript);
    } else {
      await resetToIdle(speakMessage: 'No command heard.');
    }
  }

  Future<void> processVoiceInput(String transcript) async {
    _state = FindSessionState.parsingIntent;
    notifyListeners();

    final intent = await intentClient.parseIntent(transcript);

    if (intent.action == 'STOP') {
      await resetToIdle(speakMessage: 'Stopped.');
      return;
    }

    if (intent.action == 'HELP') {
      await audioService.speak('You can say: Find my keys, where is my water bottle, or stop.');
      _state = FindSessionState.idle;
      notifyListeners();
      return;
    }

    final target = intent.target?.trim() ?? '';
    if (target.isEmpty) {
      await audioService.speak('I did not catch what you want to find. Please try again.');
      _state = FindSessionState.idle;
      notifyListeners();
      return;
    }

    _targetObject = target;
    _state = FindSessionState.searching;
    guidanceEngine.reset();
    notifyListeners();

    await audioService.speak('Searching for $_targetObject. Please slowly point the camera around.');
    await _startCameraStream();
  }

  Future<void> _startCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      try {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          // If no physical camera (e.g. emulator), use mock detector
          _objectDetector ??= MockObjectDetector();
          _startMockDetectionLoop();
          return;
        }

        final backCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );

        _cameraController = CameraController(
          backCamera,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );

        await _cameraController!.initialize();
        notifyListeners();
      } catch (e) {
        debugPrint('Camera init failed: $e. Falling back to mock vision mode.');
        _objectDetector ??= MockObjectDetector();
        _startMockDetectionLoop();
        return;
      }
    }

    _objectDetector ??= MlKitObjectDetector();

    try {
      await _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessingFrame) return;
        _isProcessingFrame = true;
        _processCameraFrame(image);
      });
    } catch (e) {
      debugPrint('Error starting camera stream: $e');
    }
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    try {
      if (_state != FindSessionState.searching &&
          _state != FindSessionState.guiding &&
          _state != FindSessionState.nearTarget) {
        return;
      }

      final orientation = _cameraController?.description.sensorOrientation ?? 90;
      final detections = await _objectDetector!.detectFromCamera(image, orientation);

      _handleDetections(detections);
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _startMockDetectionLoop() {
    Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (_state != FindSessionState.searching &&
          _state != FindSessionState.guiding &&
          _state != FindSessionState.nearTarget) {
        timer.cancel();
        return;
      }
      _handleDetections([
        DetectionResult(
          label: _targetObject,
          confidence: 0.94,
          boundingBox: const Rect.fromLTWH(0.7, 0.3, 0.2, 0.2), // Appears on the right
        ),
      ]);
    });
  }

  void _handleDetections(List<DetectionResult> detections) {
    final guidance = guidanceEngine.processDetections(
      target: _targetObject,
      detections: detections,
      sensorDistanceCm: _latestSensorDistance,
    );

    _currentGuidance = guidance;

    if (guidance.detected) {
      _lastDetectionTime = DateTime.now();

      if (guidance.direction == Direction.near) {
        _state = FindSessionState.nearTarget;
      } else {
        _state = FindSessionState.guiding;
      }

      // Check if guidance should trigger spoken direction
      if (guidanceEngine.shouldSpeak(guidance.direction)) {
        audioService.speak(guidance.voiceMessage);
      }

      // Check if haptic vibration command should be sent
      if (guidanceEngine.shouldSendHaptic()) {
        wearableService.sendHaptic(guidance.hapticCommand);
      }
    } else {
      // If lost for > 3.5 seconds
      if (DateTime.now().difference(_lastDetectionTime) > const Duration(milliseconds: 3500)) {
        if (_state == FindSessionState.guiding) {
          _state = FindSessionState.searching;
          audioService.speak('Looking for $_targetObject. Move camera slowly.');
          wearableService.sendHaptic(HapticCommand.stop);
        }
      }
    }

    notifyListeners();
  }

  Future<void> resetToIdle({String? speakMessage}) async {
    _state = FindSessionState.idle;
    _targetObject = '';
    _currentGuidance = null;
    _lastVoiceTranscript = '';
    guidanceEngine.reset();
    notifyListeners();

    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
    }

    await wearableService.sendHaptic(HapticCommand.stop);

    if (speakMessage != null) {
      await audioService.speak(speakMessage);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _objectDetector?.dispose();
    super.dispose();
  }
}
