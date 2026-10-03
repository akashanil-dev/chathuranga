class AppConstants {
  // Guidance thresholds (horizontal camera width normalized to 0.0 - 1.0)
  static const double leftThreshold = 0.35;
  static const double rightThreshold = 0.65;
  static const double nearAreaRatioThreshold = 0.30; // 30% of camera frame area

  // Debounce timing
  static const Duration speechDebounceDuration = Duration(milliseconds: 2200);
  static const Duration hapticCooldown = Duration(milliseconds: 600);

  // Backend URL: Uses 127.0.0.1 via adb reverse for zero-latency, firewall-free connection
  static const String defaultBackendUrl = 'http://127.0.0.1:8000';
  static const String wifiBackendUrl = 'http://10.68.37.235:8000';

  // BLE UUIDs matching firmware/esp32_wristband.ino
  static const String bleDeviceName = 'SENSE-Wristband';
  static const String serviceUuid = '0000FEED-0000-1000-8000-00805F9B34FB';
  static const String commandCharUuid = '0000BEEF-0000-1000-8000-00805F9B34FB';
  static const String telemetryCharUuid = '0000CAFE-0000-1000-8000-00805F9B34FB';
}
