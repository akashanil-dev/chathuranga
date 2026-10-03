import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app.dart';
import '../core/constants.dart';
import '../services/detector_service.dart';
import '../services/guidance.dart';

const kAccent = Color(0xFFFFD600);
const kGood = Color(0xFF00E676);
const kBad = Color(0xFFFF5252);
const kPanel = Color(0xFF1C1C1C);

String fmtDist(int cm) => cm < 0 ? '— cm' : (cm >= 400 ? 'no echo' : '$cm cm');

ThemeData senseTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(primary: kAccent, onPrimary: Colors.black, surface: kPanel),
    );

// ---------- shared widgets ----------

class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.onTap, this.icon, this.outlined = false, this.loading = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool outlined, loading;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    final child = loading
        ? const SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 3))
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 28), const SizedBox(width: 12)],
            Flexible(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          ]);
    return SizedBox(
      width: double.infinity,
      height: 84,
      child: outlined
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: kAccent, side: const BorderSide(color: kAccent, width: 2.5), shape: shape),
              onPressed: onTap,
              child: child)
          : FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: Colors.black, shape: shape),
              onPressed: onTap,
              child: child),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.ok});
  final String text;
  final bool ok;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 12, color: ok ? kGood : kBad),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        ]),
      );
}

class CheckRow extends StatelessWidget {
  const CheckRow(this.text, this.ok, {super.key});
  final String text;
  final bool ok;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? kGood : Colors.grey, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 20))),
        ]),
      );
}

// ---------- 1. Connect ----------

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: ble,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('SENSE', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: kAccent, letterSpacing: 2)),
                const Text('See less. Sense more.', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 24),
                Pill(ble.status, ok: ble.connected),
                const SizedBox(height: 16),
                if (ble.connected) ...[
                  const CheckRow('Wristband connected', true),
                  CheckRow(ble.sensorActive ? 'Sensor active · ${fmtDist(ble.distanceCm)}' : 'Waiting for sensor', ble.sensorActive),
                  const CheckRow('Haptics ready', true),
                  const SizedBox(height: 12),
                  const Text('Motor test (buzzes ~1.5 s)', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  Row(children: [
                    for (final t in [('LEFT', Dir.left), ('RIGHT', Dir.right), ('BOTH', Dir.centered)])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                            onPressed: () => ble.send(t.$2, Closeness.mid, GState.approaching, force: true),
                            child: Text(t.$1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ]),
                ],
                const Spacer(),
                if (!ble.connected)
                  BigButton(
                    label: 'CONNECT WRISTBAND',
                    icon: Icons.bluetooth,
                    loading: ble.busy,
                    onTap: ble.busy ? null : ble.connect,
                  )
                else
                  BigButton(
                    label: 'FIND AN OBJECT',
                    icon: Icons.search,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectScreen(demo: false))),
                  ),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectScreen(demo: true))),
                  child: const Text('Demo mode (no wristband)', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- 2. Select target ----------

class SelectScreen extends StatelessWidget {
  const SelectScreen({super.key, required this.demo});
  final bool demo;
  static const _emoji = {'PHONE': '📱', 'BOTTLE': '🧴', 'CUP': '☕'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('What should I find?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            for (final t in kTargets)
              Semantics(
                button: true,
                label: 'Find ${t.toLowerCase()}',
                excludeSemantics: true,
                child: Material(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      engine.start(t, demoMode: demo);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const FindingScreen()));
                    },
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_emoji[t] ?? '', style: const TextStyle(fontSize: 56)),
                      const SizedBox(height: 8),
                      Text(t, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- 3. Finding ----------

class FindingScreen extends StatefulWidget {
  const FindingScreen({super.key});
  @override
  State<FindingScreen> createState() => _FindingScreenState();
}

class _FindingScreenState extends State<FindingScreen> {
  bool _leaving = false;
  CameraController? _cameraController;
  final DetectorService _detector = DetectorService();
  bool _cameraLoading = false;
  bool _cameraDenied = false;
  bool _isProcessing = false;
  int _missedCount = 0;
  DateTime _lastFrameTime = DateTime.now();
  DetectionResult? _latestDetection;

  @override
  void initState() {
    super.initState();
    engine.addListener(_check);
    if (!engine.demo) {
      _initCameraAndDetector();
    }
  }

  Future<void> _initCameraAndDetector() async {
    setState(() => _cameraLoading = true);
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _cameraDenied = true;
          _cameraLoading = false;
        });
      }
      return;
    }

    try {
      await _detector.init();
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      _cameraLoading = false;
      setState(() {});

      controller.startImageStream((CameraImage image) {
        if (!mounted || _isProcessing) return;
        final now = DateTime.now();
        if (now.difference(_lastFrameTime).inMilliseconds < 100) return; // ~5-10 fps
        _isProcessing = true;
        _lastFrameTime = now;

        try {
          final targetLabel =
              kTargetLabels[engine.target] ?? engine.target.toLowerCase();
          final result = _detector.detect(
            image,
            backCamera.sensorOrientation,
            targetLabel,
          );

          if (mounted) {
            setState(() {
              _latestDetection = result;
            });
          }

          if (result != null) {
            _missedCount = 0;
            final normalizedX = (result.box.left + result.box.right) / 2.0;
            engine.setInput(dirFromX(normalizedX));
          } else {
            _missedCount++;
            if (_missedCount >= 3) {
              engine.setInput(Dir.none);
            }
          }
        } catch (e) {
          debugPrint('Detection error: $e');
        } finally {
          _isProcessing = false;
        }
      });
    } catch (e) {
      debugPrint('Camera/detector init error: $e');
      if (mounted) {
        setState(() {
          _cameraDenied = true;
          _cameraLoading = false;
        });
      }
    }
  }

  void _check() {
    if (engine.phase == Phase.reached && !_leaving && mounted) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const FoundScreen()));
        }
      });
    }
  }

  @override
  void dispose() {
    engine.removeListener(_check);
    if (engine.phase != Phase.reached) engine.reset(notify: false);
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _detector.dispose();
    super.dispose();
  }

  IconData _icon(GuidanceEngine e) {
    switch (e.phase) {
      case Phase.steer:
        return e.dir == Dir.left
            ? Icons.arrow_back_rounded
            : Icons.arrow_forward_rounded;
      case Phase.centered:
        return Icons.my_location;
      case Phase.near:
        return Icons.touch_app_rounded;
      case Phase.reached:
        return Icons.check_circle_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([engine, ble]),
          builder: (context, _) {
            final e = engine;
            final showSimulated = !kDetectorReady || e.demo || _cameraDenied;

            return ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                Expanded(
                  child: Text('FINDING ${e.target}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('STOP',
                      style: TextStyle(
                          fontSize: 20,
                          color: kBad,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 12),

              // Camera Preview in top third
              if (!e.demo && !_cameraDenied) ...[
                if (_cameraController != null &&
                    _cameraController!.value.isInitialized) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_cameraController!),
                          if (_latestDetection != null)
                            CustomPaint(
                              painter: BoundingBoxPainter(
                                box: _latestDetection!.box,
                                label: _latestDetection!.label,
                                confidence: _latestDetection!.score,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else if (_cameraLoading) ...[
                  Container(
                    height: 140,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kPanel,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(strokeWidth: 3),
                        SizedBox(width: 16),
                        Text('Starting camera detector...',
                            style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],

              // Camera denied message
              if (_cameraDenied) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBad),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.videocam_off, color: kBad, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Camera permission denied. Using simulated controls.',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              Container(
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                    color: kPanel, borderRadius: BorderRadius.circular(28)),
                child: Column(children: [
                  Icon(_icon(e), size: 110, color: kAccent),
                  const SizedBox(height: 8),
                  Text(e.instruction,
                      style: const TextStyle(
                          fontSize: 38, fontWeight: FontWeight.w900)),
                ]),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmtDist(e.distanceCm),
                      style: const TextStyle(
                          fontSize: 52, fontWeight: FontWeight.w900)),
                  Text(e.closeness.name.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: kAccent)),
                ],
              ),
              const SizedBox(height: 12),
              Pill(
                e.demo
                    ? 'Demo mode · no wristband'
                    : (ble.connected
                        ? 'Wristband connected'
                        : 'Wristband lost'),
                ok: e.demo || ble.connected,
              ),

              // Simulated AI controls: shown in demo mode or if camera is denied
              if (showSimulated) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(20)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SIMULATED AI INPUT (demo mode / fallback)',
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          for (final o in [
                            ('LEFT', Dir.left),
                            ('CENTER', Dir.centered),
                            ('RIGHT', Dir.right),
                            ('LOST', Dir.none)
                          ])
                            ChoiceChip(
                              label: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(o.$1,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700))),
                              selected: e.input == o.$2,
                              onSelected: (_) => e.setInput(o.$2),
                            ),
                        ]),
                        if (e.demo) ...[
                          const SizedBox(height: 12),
                          Text('Simulated distance: ${e.demoDistance} cm',
                              style: const TextStyle(fontSize: 16)),
                          Slider(
                              min: 10,
                              max: 150,
                              value: e.demoDistance.toDouble(),
                              onChanged: (v) => e.setDemoDistance(v.round())),
                        ],
                      ]),
                ),
              ],

              ExpansionTile(
                title: const Text('Diagnostics', style: TextStyle(fontSize: 18)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'BLE        ${ble.connected ? "CONNECTED" : "OFF"}\n'
                      'TARGET     ${e.target}\n'
                      'DIRECTION  ${e.dir.name.toUpperCase()}\n'
                      'ULTRASONIC ${fmtDist(e.distanceCm)}\n'
                      'CLOSENESS  ${e.closeness.name.toUpperCase()}\n'
                      'PHASE      ${e.phase.name.toUpperCase()}\n'
                      'PACKET     ${e.packet}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                    ),
                  ),
                ],
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  const BoundingBoxPainter({
    required this.box,
    required this.label,
    required this.confidence,
  });

  final Rect box;
  final String label;
  final double confidence;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      box.left * size.width,
      box.top * size.height,
      box.right * size.width,
      box.bottom * size.height,
    );

    final boxPaint = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    canvas.drawRect(rect, boxPaint);

    final text = '$label ${(confidence * 100).toInt()}%';
    final span = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();

    final bgTop = (rect.top - 22).clamp(0.0, size.height - 22);
    final bgRect = Rect.fromLTWH(rect.left, bgTop, tp.width + 10, 22);
    canvas.drawRect(bgRect, Paint()..color = kAccent);
    tp.paint(canvas, Offset(bgRect.left + 5, bgRect.top + 3));
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) =>
      oldDelegate.box != box ||
      oldDelegate.label != label ||
      oldDelegate.confidence != confidence;
}

// ---------- 4. Found ----------

class FoundScreen extends StatelessWidget {
  const FoundScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.check_circle_rounded, size: 140, color: kGood),
            const SizedBox(height: 12),
            const Text('TARGET FOUND', textAlign: TextAlign.center, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: kGood)),
            Text(engine.target, textAlign: TextAlign.center, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Distance: ${fmtDist(engine.distanceCm)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 40),
            BigButton(
              label: 'FIND ANOTHER OBJECT',
              icon: Icons.search,
              onTap: () {
                engine.reset();
                Navigator.pop(context);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
