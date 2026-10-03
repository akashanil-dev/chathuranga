import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// BLE identifiers: must match firmware/sense_wrist/sense_wrist.ino
const kDeviceName = 'SENSE-WRIST-01';
final kServiceUuid = Guid('5e45a001-1000-4a5e-9e5e-5e45e5e5e5e5');
final kSensorUuid = Guid('5e45a002-1000-4a5e-9e5e-5e45e5e5e5e5');
final kHapticUuid = Guid('5e45a003-1000-4a5e-9e5e-5e45e5e5e5e5');

// Wire protocol: enum index == byte value. Do not reorder.
enum Dir { none, left, right, up, down, centered }
enum Closeness { far, mid, near, veryNear }
enum GState { searching, approaching, reached }

// INITIAL values. Calibrate with your real hardware and keep identical in the firmware.
const int kVeryNearCm = 30, kNearCm = 60, kMidCm = 100;
const double kLeftMax = 0.35, kRightMin = 0.65; // used by the detector in Phase 7

// Flip to true when the camera + detector (Phase 5-7) feed engine.setInput().
const bool kDetectorReady = true;

const kTargets = ['PHONE', 'BOTTLE', 'CUP'];

const kTargetLabels = {
  'PHONE': 'cell phone',
  'BOTTLE': 'bottle',
  'CUP': 'cup',
};

Closeness closenessFor(int cm) {
  if (cm <= 0 || cm >= 400) return Closeness.far; // no echo
  if (cm < kVeryNearCm) return Closeness.veryNear;
  if (cm < kNearCm) return Closeness.near;
  if (cm < kMidCm) return Closeness.mid;
  return Closeness.far;
}

/// normalizedX = bboxCenterX / frameWidth
Dir dirFromX(double x) =>
    x < kLeftMax ? Dir.left : (x > kRightMin ? Dir.right : Dir.centered);
