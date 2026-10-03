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

  static String cleanTargetPhrase(String text) {
    if (text.trim().isEmpty) return '';
    String clean = text.toLowerCase().trim();
    clean = clean.replaceAll(RegExp(r'[\.\?\!\,\;]+$'), '').trim();

    final prefixPatterns = [
      RegExp(r'^(?:hey\s+|ok\s+)?sense\s+'),
      RegExp(r'^(?:hello|hi|please|um|uh)\s+'),
      RegExp(r'^(?:can\s+you|could\s+you|would\s+you)\s+(?:please\s+)?'),
      RegExp(r"^(?:i\s+want\s+to|i\s+need\s+to|i\s+would\s+like\s+to|i['\s]?m\s+trying\s+to)\s+"),
      RegExp(r"^(?:i\s+am\s+looking\s+for|i['\s]?m\s+looking\s+for|looking\s+for)\s+"),
      RegExp(r'^(?:help\s+me|help\s+me\s+to)\s+'),
      RegExp(r'^(?:find|locate|search\s+for|look\s+for|detect|track|spot|see|show\s+me)\s+(?:me\s+)?'),
      RegExp(r"^(?:where\s+is|where\s+are|where['\s]?s|wheres|where\s+did\s+i\s+leave|where\s+did\s+i\s+put)\s+"),
      RegExp(r'^(?:my|the|a|an|some)\s+'),
    ];

    bool changed = true;
    while (changed) {
      changed = false;
      for (final p in prefixPatterns) {
        final match = p.firstMatch(clean);
        if (match != null) {
          clean = clean.substring(match.end).trim();
          changed = true;
        }
      }
    }

    clean = clean.replaceAll(RegExp(r'\s+(?:please|for\s+me|thanks|thank\s+you|now)$'), '').trim();
    clean = clean.replaceAll(RegExp(r'^(?:my|the|a|an)\s+'), '').trim();

    return clean;
  }

  Future<GuidanceOutput?> analyzeSceneWithVision({
    required String transcript,
    String? target,
    required String imageBase64,
    double? sensorDistanceCm,
  }) async {
    final cleanTarget = (target != null && target.trim().isNotEmpty)
        ? cleanTargetPhrase(target)
        : cleanTargetPhrase(transcript);

    final hosts = [baseUrl, if (baseUrl != AppConstants.wifiBackendUrl) AppConstants.wifiBackendUrl];
    for (final host in hosts) {
      try {
        final url = Uri.parse('$host/api/v1/analyze');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'transcript': transcript,
                'target': cleanTarget,
                'image_base64': imageBase64,
                'sensor_distance_cm': sensorDistanceCm,
              }),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final rawTarget = data['target'] as String? ?? '';
          final resolvedTarget = cleanTarget.isNotEmpty
              ? cleanTarget
              : (rawTarget.isNotEmpty ? cleanTargetPhrase(rawTarget) : 'object');

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
            target: resolvedTarget,
            detected: detected,
            direction: direction,
            imagePosition: pos,
            voiceMessage: voiceMsg,
            hapticCommand: haptic,
            proximity: proximity,
          );
        }
      } catch (e) {
        debugPrint('Vision API call error on $host: $e');
      }
    }
    return null;
  }

  UserIntent _fallbackParse(String text) {
    final lower = text.toLowerCase().trim();

    if (lower.contains('stop') || lower.contains('cancel') || lower.contains('quit')) {
      return UserIntent(action: 'STOP', target: null, rawTranscript: text);
    }

    if (lower == 'help' || lower == 'help me') {
      return UserIntent(action: 'HELP', target: null, rawTranscript: text);
    }

    final target = cleanTargetPhrase(text);

    return UserIntent(
      action: 'FIND_OBJECT',
      target: target.isNotEmpty ? target : 'object',
      rawTranscript: text,
    );
  }
}
