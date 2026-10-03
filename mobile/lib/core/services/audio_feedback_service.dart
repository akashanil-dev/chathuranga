import 'package:flutter_tts/flutter_tts.dart';

class AudioFeedbackService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  AudioFeedbackService();

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5); // Natural conversational rate
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      _isInitialized = true;
    } catch (e) {
      // Fallback silently if TTS service isn't ready
    }
  }

  Future<void> speak(String text, {bool interrupt = true}) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (interrupt) {
      await stop();
    }
    if (text.trim().isNotEmpty) {
      await _tts.speak(text);
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
