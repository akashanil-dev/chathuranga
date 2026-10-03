enum Direction {
  left,
  center,
  right,
  near,
  touching,
  none,
  lost;

  String get displayName {
    switch (this) {
      case Direction.left:
        return 'Left';
      case Direction.center:
        return 'Center';
      case Direction.right:
        return 'Right';
      case Direction.near:
        return 'Approaching Target';
      case Direction.touching:
        return 'Target Reached';
      case Direction.none:
        return 'Not Detected';
      case Direction.lost:
        return 'Target Lost';
    }
  }
}

enum HapticCommand {
  left('LEFT', 0x01),
  right('RIGHT', 0x02),
  center('CENTER', 0x03),
  near('NEAR', 0x04),
  touching('TOUCHING', 0x05),
  stop('STOP', 0x00);

  final String textValue;
  final int byteValue;

  const HapticCommand(this.textValue, this.byteValue);
}
