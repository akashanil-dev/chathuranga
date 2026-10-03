import 'package:flutter_tts/flutter_tts.dart';

class Speech {
  final FlutterTts _tts = FlutterTts();
  String _last = '';
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  /// Newest message interrupts older ones. Identical text within 3 s is suppressed.
  Future<void> say(String text, {bool force = false}) async {
    final now = DateTime.now();
    if (!force && text == _last && now.difference(_at) < const Duration(seconds: 3)) return;
    _last = text;
    _at = now;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
