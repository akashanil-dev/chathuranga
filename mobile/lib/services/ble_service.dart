import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';

class BleService extends ChangeNotifier {
  BluetoothCharacteristic? _haptic;
  StreamSubscription<List<int>>? _sensorSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool connected = false;
  bool busy = false;
  String status = 'Wristband not connected';
  int distanceCm = -1;
  DateTime? _lastSensorAt;
  List<int> _lastPacket = const [];
  DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get sensorActive =>
      connected &&
      _lastSensorAt != null &&
      DateTime.now().difference(_lastSensorAt!) < const Duration(seconds: 2);

  void _set(String s) {
    status = s;
    notifyListeners();
  }

  Future<void> connect() async {
    if (busy || connected) return;
    busy = true;
    _set('Searching for $kDeviceName…');
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      BluetoothDevice? found;
      final sub = FlutterBluePlus.scanResults.listen((list) {
        for (final r in list) {
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          if (name == kDeviceName || r.advertisementData.serviceUuids.contains(kServiceUuid)) {
            found = r.device;
            FlutterBluePlus.stopScan();
          }
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
      await sub.cancel();

      final dev = found;
      if (dev == null) {
        busy = false;
        _set('Wristband not found. Is it powered on?');
        return;
      }

      _set('Connecting…');
      await dev.connect(timeout: const Duration(seconds: 10));
      _connSub = dev.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _onDisconnected();
      });

      final services = await dev.discoverServices();
      final svc = services.firstWhere((s) => s.uuid == kServiceUuid);
      _haptic = svc.characteristics.firstWhere((c) => c.uuid == kHapticUuid);
      final sensor = svc.characteristics.firstWhere((c) => c.uuid == kSensorUuid);
      await sensor.setNotifyValue(true);
      _sensorSub = sensor.onValueReceived.listen(_onSensor);

      connected = true;
      busy = false;
      _set('Wristband connected');
    } catch (e) {
      busy = false;
      connected = false;
      _set('Connect failed: $e');
    }
  }

  void _onSensor(List<int> v) {
    if (v.length < 3) return;
    distanceCm = v[0] | (v[1] << 8);
    _lastSensorAt = DateTime.now();
    notifyListeners();
  }

  void _onDisconnected() {
    connected = false;
    _haptic = null;
    distanceCm = -1;
    _sensorSub?.cancel();
    _connSub?.cancel();
    _set('Wristband disconnected');
  }

  /// Sends [direction, closeness, state]. Re-sends the same packet every ~600 ms
  /// as a heartbeat, because the ESP32 turns motors off after 1.5 s of silence (failsafe).
  Future<void> send(Dir d, Closeness c, GState s, {bool force = false}) async {
    final h = _haptic;
    if (h == null) return;
    final p = [d.index, c.index, s.index];
    final now = DateTime.now();
    if (!force && listEquals(p, _lastPacket) && now.difference(_lastSendAt) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastPacket = p;
    _lastSendAt = now;
    try {
      await h.write(p, withoutResponse: true);
    } catch (_) {}
  }
}
