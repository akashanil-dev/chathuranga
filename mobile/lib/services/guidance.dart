import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import 'ble_service.dart';
import 'speech.dart';

enum Phase { idle, searching, steer, centered, near, reached }

/// SEARCHING -> LEFT/RIGHT -> CENTERED -> NEAR -> REACHED
/// Inputs: a direction (from the detector later; simulated for now) + distance (ESP32 ultrasonic).
/// Outputs: voice (only on change), a 3-byte BLE packet, and UI state.
class GuidanceEngine extends ChangeNotifier {
  GuidanceEngine(this.ble, this.speech);
  final BleService ble;
  final Speech speech;

  String target = 'PHONE';
  bool demo = false; // true = no wristband, distance comes from the slider
  int demoDistance = 120;
  Phase phase = Phase.idle;
  Dir dir = Dir.none; // debounced direction
  List<int> packet = const [0, 0, 0];

  Timer? _timer;
  Dir _input = Dir.none, _cand = Dir.none;
  int _candN = 0, _nearN = 0;
  Dir _spokenDir = Dir.none;

  Dir get input => _input;
  int get distanceCm => demo ? demoDistance : ble.distanceCm;
  Closeness get closeness => closenessFor(distanceCm);
  String get _name => target.toLowerCase();

  String get instruction {
    switch (phase) {
      case Phase.steer:
        return dir == Dir.left ? 'MOVE LEFT' : 'MOVE RIGHT';
      case Phase.centered:
        return 'AHEAD OF YOU';
      case Phase.near:
        return 'CLOSE: REACH';
      case Phase.reached:
        return 'FOUND';
      default:
        return 'SEARCHING';
    }
  }

  void start(String t, {required bool demoMode}) {
    _timer?.cancel();
    target = t;
    demo = demoMode;
    demoDistance = 120;
    phase = Phase.searching;
    dir = _input = _cand = Dir.none;
    _candN = _nearN = 0;
    _spokenDir = Dir.none;
    speech.say('Looking for $_name.', force: true);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    notifyListeners();
  }

  /// The detector (Phase 7) calls this with dirFromX(...) or Dir.none when the target is not visible.
  void setInput(Dir d) {
    _input = d;
    notifyListeners();
  }

  void setDemoDistance(int cm) {
    demoDistance = cm;
    notifyListeners();
  }

  void reset({bool notify = true}) {
    _timer?.cancel();
    phase = Phase.idle;
    dir = _input = Dir.none;
    ble.send(Dir.none, Closeness.far, GState.searching, force: true);
    speech.stop();
    if (notify) notifyListeners();
  }

  void _tick() {
    // Direction must hold for 2 ticks (~400 ms) before it changes: simple hysteresis.
    if (_input == _cand) {
      _candN++;
    } else {
      _cand = _input;
      _candN = 1;
    }
    if (_candN >= 2) dir = _cand;

    final c = closeness;
    Phase p;
    if (dir == Dir.none) {
      p = Phase.searching;
    } else if (dir == Dir.left || dir == Dir.right) {
      p = Phase.steer;
    } else {
      p = c.index >= Closeness.near.index ? Phase.near : Phase.centered;
    }

    // REACHED = centered AND near, held ~600 ms. Distance alone never triggers it.
    _nearN = (p == Phase.near) ? _nearN + 1 : 0;
    if (_nearN >= 3) p = Phase.reached;

    final changed = p != phase;
    final dirChanged = p == Phase.steer && dir != _spokenDir;
    phase = p;
    if (changed || dirChanged) _announce();

    final state = p == Phase.reached
        ? GState.reached
        : (p == Phase.searching ? GState.searching : GState.approaching);
    final wireDir = p == Phase.reached ? Dir.centered : dir;
    packet = [wireDir.index, c.index, state.index];
    ble.send(wireDir, c, state, force: p == Phase.reached);

    if (p == Phase.reached) {
      _timer?.cancel();
      // second send in case the first write-without-response was dropped
      Future.delayed(const Duration(milliseconds: 300),
          () => ble.send(Dir.centered, c, GState.reached, force: true));
    }
    notifyListeners();
  }

  void _announce() {
    switch (phase) {
      case Phase.searching:
        speech.say('Searching.');
        break;
      case Phase.steer:
        _spokenDir = dir;
        speech.say(dir == Dir.left ? 'Move left.' : 'Move right.');
        break;
      case Phase.centered:
        speech.say('The $_name is in front of you.');
        break;
      case Phase.near:
        speech.say("You're close.");
        break;
      case Phase.reached:
        speech.say('Your $_name is here.', force: true);
        break;
      case Phase.idle:
        break;
    }
  }
}
