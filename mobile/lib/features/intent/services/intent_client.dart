import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_constants.dart';
import '../../../core/types/direction.dart';
import '../../guidance/models/guidance_output.dart';

class UserIntent {
  final String action; // FIND_OBJECT, STOP, HELP, UNKNOWN
  final String? target;
  final String rawTranscript;

  UserIntent({
    required this.action,
    this.target,
    required this.rawTranscript,
  });

  factory UserIntent.fromJson(Map<String, dynamic> json) {
    return UserIntent(
      action: json['action'] as String? ?? 'FIND_OBJECT',
      target: json['target'] as String?,
      rawTranscript: json['raw_transcript'] as String? ?? '',
    );
  }
}

class IntentClient {
  String baseUrl;

  IntentClient({this.baseUrl = AppConstants.defaultBackendUrl});

  Future<UserIntent> parseIntent(String transcript) async {
    final clean = transcript.trim();
    if (clean.isEmpty) {
      return UserIntent(action: 'UNKNOWN', target: null, rawTranscript: transcript);
    }

    try {
      final url = Uri.parse('$baseUrl/api/v1/intent');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'transcript': clean}),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return UserIntent.fromJson(data);
      }
    } catch (e) {
      debugPrint('Backend intent error: $e. Using local fallback parser.');
    }

    // Offline / Fallback heuristic parser
    return _fallbackParse(clean);
  }

  Future<GuidanceOutput?> analyzeSceneWithVision({
    required String transcript,
    required String imageBase64,
    double? sensorDistanceCm,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/analyze');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transcript': transcript,
              'image_base64': imageBase64,
              'sensor_distance_cm': sensorDistanceCm,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final target = data['target'] as String? ?? 'object';
        final detected = data['detected'] as bool? ?? false;
        final pos = data['image_position'] as String? ?? 'none';
        final voiceMsg = data['voice_message'] as String? ?? '';
        final hapticStr = data['haptic_command'] as String? ?? 'STOP';
        final proximity = data['proximity'] as String? ?? 'unknown';

        Direction direction;
        if (pos == 'left') {
          direction = Direction.left;
        } else if (pos == 'right') {
          direction = Direction.right;
        } else if (pos == 'center') {
          direction = Direction.center;
        } else if (!detected) {
          direction = Direction.none;
        } else {
          direction = Direction.near;
        }

        HapticCommand haptic = HapticCommand.stop;
        for (final h in HapticCommand.values) {
          if (h.textValue == hapticStr) {
            haptic = h;
            break;
          }
        }

        return GuidanceOutput(
          target: target,
          detected: detected,
          direction: direction,
          imagePosition: pos,
          voiceMessage: voiceMsg,
          hapticCommand: haptic,
          proximity: proximity,
        );
      }
    } catch (e) {
      debugPrint('Claude Vision API call error: $e');
    }
    return null;
  }

  UserIntent _fallbackParse(String text) {
    final lower = text.toLowerCase();

    if (lower.contains('stop') || lower.contains('cancel') || lower.contains('quit')) {
      return UserIntent(action: 'STOP', target: null, rawTranscript: text);
    }

    if (lower == 'help' || lower == 'help me') {
      return UserIntent(action: 'HELP', target: null, rawTranscript: text);
    }

    final prefixes = [
      'can you help me find my ',
      'can you help me find the ',
      'can you help me find a ',
      'can you help me find ',
      'help me find my ',
      'help me find the ',
      'help me find a ',
      'help me find ',
      'please find my ',
      'please find the ',
      'please find a ',
      'please find ',
      'find my ',
      'find the ',
      'find a ',
      'find ',
      'where are my ',
      'where is my ',
      'where\'s my ',
      'where did i leave my ',
      'where are the ',
      'where is the ',
      'look for my ',
      'look for the ',
      'look for ',
      'locate my ',
      'locate the ',
      'locate ',
    ];

    String target = lower;
    for (final p in prefixes) {
      if (target.startsWith(p)) {
        target = target.substring(p.length).trim();
        break;
      }
    }

    target = target.replaceAll(RegExp(r'[\.\?!]'), '').trim();

    return UserIntent(
      action: 'FIND_OBJECT',
      target: target.isNotEmpty ? target : 'object',
      rawTranscript: text,
    );
  }
}
