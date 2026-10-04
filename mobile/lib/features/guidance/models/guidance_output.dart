import '../../../core/types/direction.dart';

class GuidanceOutput {
  final String target;
  final bool detected;
  final Direction direction;
  final String imagePosition; // "left", "center", "right", "none"
  final String voiceMessage;
  final HapticCommand hapticCommand;
  final String proximity;
  final double? confidence;
  final String? provider; // "local", "claude", "rules", "none" (backend), null for on-device

  GuidanceOutput({
    required this.target,
    required this.detected,
    required this.direction,
    required this.imagePosition,
    required this.voiceMessage,
    required this.hapticCommand,
    required this.proximity,
    this.confidence,
    this.provider,
  });

  Map<String, dynamic> toJson() => {
        'target': target,
        'detected': detected,
        'image_position': imagePosition,
        'voice_message': voiceMessage,
        'haptic_command': hapticCommand.textValue,
        'proximity': proximity,
      };

  @override
  String toString() =>
      'GuidanceOutput(target: $target, pos: $imagePosition, haptic: ${hapticCommand.textValue}, voice: "$voiceMessage")';
}
