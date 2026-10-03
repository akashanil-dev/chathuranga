class AppConstants {
  // Guidance thresholds (horizontal camera width normalized to 0.0 - 1.0)
  static const double leftThreshold = 0.35;
  static const double rightThreshold = 0.65;
  static const double nearAreaRatioThreshold = 0.30; // 30% of camera frame area

  // Debounce timing
  static const Duration speechDebounceDuration = Duration(milliseconds: 2200);
  static const Duration hapticCooldown = Duration(milliseconds: 600);

  // Backend URL (Default to Android Emulator loopback; can be changed in settings)
  // For physical Android device connected to PC WiFi, use PC IP e.g. http://192.168.1.x:8000
  static const String defaultBackendUrl = 'http://10.0.2.2:8000';

  // BLE UUIDs matching firmware/esp32_wristband.ino
  static const String bleDeviceName = 'SENSE-Wristband';
  static const String serviceUuid = '0000FEED-0000-1000-8000-00805F9B34FB';
  static const String commandCharUuid = '0000BEEF-0000-1000-8000-00805F9B34FB';
  static const String telemetryCharUuid = '0000CAFE-0000-1000-8000-00805F9B34FB';
}
