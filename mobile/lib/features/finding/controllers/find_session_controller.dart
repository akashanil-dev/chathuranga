import 'dart:async';
import 'dart:convert';
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
    _ensureCameraInitialized();
  }

  void _initWearable() {
    wearableService.distanceStream.listen((dist) {
      _latestSensorDistance = dist;
      _handleProximityUpdate(dist);
      notifyListeners();
    });
  }

  void _handleProximityUpdate(double? dist) {
    if (dist == null) return;
    if (_state != FindSessionState.guiding && _state != FindSessionState.nearTarget) return;

    if (dist <= 8.0) {
      if (_state != FindSessionState.completed) {
        _state = FindSessionState.completed;
        _scanningTimer?.cancel();
        audioService.speak('Target reached! Right beneath your hand.');
        HapticFeedback.heavyImpact();
        wearableService.sendHaptic(HapticCommand.touching);
        notifyListeners();
      }
    } else if (dist <= 25.0) {
      if (_state != FindSessionState.nearTarget) {
        _state = FindSessionState.nearTarget;
        audioService.speak('Approaching $_targetObject. Reach forward slowly.');
        HapticFeedback.mediumImpact();
        wearableService.sendHaptic(HapticCommand.near);
        notifyListeners();
      }
    }
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

  String _extractTargetFast(String transcript) {
    final lower = transcript.toLowerCase().trim();
    final prefixes = [
      'can you help me find my ', 'can you help me find the ', 'can you help me find a ', 'can you help me find ',
      'help me find my ', 'help me find the ', 'help me find a ', 'help me find ',
      'please find my ', 'please find the ', 'please find a ', 'please find ',
      'find my ', 'find the ', 'find a ', 'find ',
      'where are my ', 'where is my ', "where's my ", 'where are the ', 'where is the ',
      'look for my ', 'look for the ', 'look for ',
      'locate my ', 'locate the ', 'locate ',
    ];
    for (final p in prefixes) {
      if (lower.startsWith(p)) {
        String target = lower.substring(p.length).trim();
        final suffixes = [' please', ' for me', ' thanks', ' thank you'];
        for (final s in suffixes) {
          if (target.endsWith(s)) {
            target = target.substring(0, target.length - s.length).trim();
          }
        }
        return target.replaceAll(RegExp(r'[\.\?\!]+$'), '').trim();
      }
    }
    return '';
  }

  Timer? _scanningTimer;
  bool _isScanning = false;

  Future<void> processVoiceInput(String transcript) async {
    _state = FindSessionState.parsingIntent;
    notifyListeners();

    // Check quick commands first
    final lower = transcript.toLowerCase();
    if (lower.contains('stop') || lower.contains('cancel')) {
      await resetToIdle(speakMessage: 'Stopped.');
      return;
    }
    if (lower == 'help' || lower == 'help me') {
      await audioService.speak('You can say: Find my keys, where is my water bottle, or stop.');
      _state = FindSessionState.idle;
      notifyListeners();
      return;
    }

    // Fast extraction or fallback to backend intent parsing
    String target = _extractTargetFast(transcript);
    if (target.isEmpty) {
      final intent = await intentClient.parseIntent(transcript);
      target = intent.target?.trim() ?? '';
    }

    if (target.isEmpty) {
      await audioService.speak('I did not catch what you want to find. Please try again.');
      _state = FindSessionState.idle;
      notifyListeners();
      return;
    }

    // Initialize camera if needed
    await _ensureCameraInitialized();

    _targetObject = target;
    _state = FindSessionState.searching;
    guidanceEngine.reset();
    _currentGuidance = null;
    notifyListeners();

    // Immediate confirmation feedback
    HapticFeedback.mediumImpact();
    await audioService.speak('Searching for $_targetObject. Move your camera around slowly.');

    // Start continuous Claude Haiku scanning loop as the user pans around
    _startScanningLoop(transcript);
  }

  void _startScanningLoop(String originalTranscript) {
    _scanningTimer?.cancel();
    _runSingleScan(originalTranscript);

    _scanningTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) async {
      if (_state != FindSessionState.searching) {
        timer.cancel();
        return;
      }
      await _runSingleScan(originalTranscript);
    });
  }

  Future<void> _runSingleScan(String originalTranscript) async {
    if (_isScanning || _state != FindSessionState.searching) return;
    _isScanning = true;

    try {
      final snapshotBase64 = await _captureSnapshotBase64();
      if (snapshotBase64 != null && _state == FindSessionState.searching) {
        final visionGuidance = await intentClient.analyzeSceneWithVision(
          transcript: originalTranscript,
          imageBase64: snapshotBase64,
          sensorDistanceCm: _latestSensorDistance,
        );

        if (visionGuidance != null && visionGuidance.detected && _state == FindSessionState.searching) {
          _scanningTimer?.cancel();
          _state = FindSessionState.guiding;
          _targetObject = visionGuidance.target;
          _currentGuidance = visionGuidance;
          _lastDetectionTime = DateTime.now();
          notifyListeners();

          // Spoken guidance announcement
          HapticFeedback.heavyImpact();
          await audioService.speak('Found your $_targetObject! ${visionGuidance.voiceMessage}');
          await wearableService.sendHaptic(visionGuidance.hapticCommand);

          // Start continuous local camera tracking
          await _startCameraStream();
        }
      }
    } catch (e) {
      debugPrint('Scanning loop error: $e');
    } finally {
      _isScanning = false;
    }
  }

  Future<void> _ensureCameraInitialized() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _objectDetector ??= MockObjectDetector();
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
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _cameraController!.initialize();
      notifyListeners();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<String?> _captureSnapshotBase64() async {
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        final file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();
        return base64Encode(bytes);
      }
    } catch (e) {
      debugPrint('Snapshot capture error: $e');
    }
    return null;
  }

  int _lastFrameTimestamp = 0;

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
          imageFormatGroup: ImageFormatGroup.nv21,
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
      if (_cameraController!.value.isStreamingImages) {
        return;
      }
      await _cameraController!.startImageStream((CameraImage image) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastFrameTimestamp < 220) return; // Throttle to ~4.5 FPS
        if (_isProcessingFrame) return;
        _isProcessingFrame = true;
        _lastFrameTimestamp = now;
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
    _scanningTimer?.cancel();
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
    _scanningTimer?.cancel();
    _cameraController?.dispose();
    _objectDetector?.dispose();
    super.dispose();
  }
}
