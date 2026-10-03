import '../services/ble_service.dart';
import '../services/guidance.dart';
import '../services/speech.dart';

// Hackathon-simple: three app-wide singletons, no DI framework.
final ble = BleService();
final speech = Speech();
final engine = GuidanceEngine(ble, speech);
