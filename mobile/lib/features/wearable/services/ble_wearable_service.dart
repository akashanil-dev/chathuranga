import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/types/direction.dart';

abstract class WearableService {
  Future<void> connect();
  Future<void> disconnect();
  Future<void> sendHaptic(HapticCommand command);
  Stream<double?> get distanceStream;
  Stream<bool> get isConnectedStream;
  bool get isConnected;
  String get statusMessage;
}

class BleWearableService implements WearableService {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _telemetryChar;

  final _distanceController = StreamController<double?>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _isConnected = false;
  String _statusMessage = 'Disconnected';
  StreamSubscription? _scanSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _telemetrySub;
  Timer? _autoConnectTimer;
  bool _connecting = false;

  /// Keep trying to reach the wristband in the background (user never has to press a button).
  void startAutoConnect({Duration interval = const Duration(seconds: 12)}) {
    _autoConnectTimer?.cancel();
    void attempt() {
      if (_isConnected || _connecting || FlutterBluePlus.isScanningNow) return;
      connect();
    }

    attempt();
    _autoConnectTimer = Timer.periodic(interval, (_) => attempt());
  }

  @override
  Stream<double?> get distanceStream => _distanceController.stream;

  @override
  Stream<bool> get isConnectedStream => _connectionController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  String get statusMessage => _statusMessage;

  @override
  Future<void> connect() async {
    try {
      _updateStatus('Scanning for SENSE-Wristband...');

      // Check adapter availability
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _updateStatus('Bluetooth is turned off');
        return;
      }

      await FlutterBluePlus.startScan(
        withServices: [Guid.fromString(AppConstants.serviceUuid)],
        timeout: const Duration(seconds: 8),
      );

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          if (r.device.platformName.contains('SENSE') ||
              r.advertisementData.serviceUuids.contains(Guid.fromString(AppConstants.serviceUuid))) {
            await FlutterBluePlus.stopScan();
            await _connectToDevice(r.device);
            break;
          }
        }
      });
    } catch (e) {
      _updateStatus('BLE Scan Error: $e');
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_connecting) return;
    _connecting = true;
    try {
      _updateStatus('Connecting to ${device.platformName}...');
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 5),
        autoConnect: false,
      );
      _connectedDevice = device;

      _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        _isConnected = connected;
        _connectionController.add(connected);
        if (!connected) {
          _updateStatus('Wristband Disconnected');
          _commandChar = null;
          _telemetryChar = null;
        }
      });

      // Discover Services
      final services = await device.discoverServices();
      for (final s in services) {
        if (s.uuid == Guid.fromString(AppConstants.serviceUuid)) {
          for (final c in s.characteristics) {
            if (c.uuid == Guid.fromString(AppConstants.commandCharUuid)) {
              _commandChar = c;
            } else if (c.uuid == Guid.fromString(AppConstants.telemetryCharUuid)) {
              _telemetryChar = c;
              await _telemetryChar!.setNotifyValue(true);
              await _telemetrySub?.cancel();
              _telemetrySub = _telemetryChar!.lastValueStream.listen(_onTelemetryReceived);
            }
          }
        }
      }

      _isConnected = true;
      _updateStatus('Wristband Connected');
      _connectionController.add(true);
    } catch (e) {
      _updateStatus('Connection failed: $e');
    } finally {
      _connecting = false;
    }
  }

  void _onTelemetryReceived(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final str = utf8.decode(bytes).trim();
      final dist = double.tryParse(str);
      if (dist != null) {
        _distanceController.add(dist);
      }
    } catch (_) {}
  }

  @override
  Future<void> sendHaptic(HapticCommand command) async {
    if (!_isConnected || _commandChar == null) return;
    try {
      // Send command string as UTF-8 (e.g. "LEFT", "RIGHT", "CENTER", "NEAR", "STOP")
      final payload = utf8.encode(command.textValue);
      await _commandChar!.write(payload, withoutResponse: true);
    } catch (e) {
      debugPrint('Failed to send BLE haptic: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _autoConnectTimer?.cancel();
    await _telemetrySub?.cancel();
    await _scanSub?.cancel();
    await _connectionSub?.cancel();
    await _connectedDevice?.disconnect();
    _isConnected = false;
    _commandChar = null;
    _telemetryChar = null;
    _updateStatus('Disconnected');
    _connectionController.add(false);
  }

  void _updateStatus(String msg) {
    _statusMessage = msg;
    debugPrint('BLE: $msg');
  }
}

class MockWearableService implements WearableService {
  final _distanceController = StreamController<double?>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _connected = true;
  String _lastSentCommand = 'STOP';

  String get lastSentCommand => _lastSentCommand;

  @override
  bool get isConnected => _connected;

  @override
  Stream<double?> get distanceStream => _distanceController.stream;

  @override
  Stream<bool> get isConnectedStream => _connectionController.stream;

  @override
  String get statusMessage => _connected ? 'Connected (Simulated)' : 'Disconnected';

  @override
  Future<void> connect() async {
    _connected = true;
    _connectionController.add(true);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _connectionController.add(false);
  }

  @override
  Future<void> sendHaptic(HapticCommand command) async {
    _lastSentCommand = command.textValue;
    debugPrint('Mock Wristband Haptic: ${command.textValue}');
  }

  void simulateDistance(double cm) {
    _distanceController.add(cm);
  }
}
