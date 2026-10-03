import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../core/types/direction.dart';
import '../controllers/find_session_controller.dart';

class AccessibleHomePage extends StatefulWidget {
  final FindSessionController controller;

  const AccessibleHomePage({super.key, required this.controller});

  @override
  State<AccessibleHomePage> createState() => _AccessibleHomePageState();
}

class _AccessibleHomePageState extends State<AccessibleHomePage> {
  bool _showDebugHud = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final state = c.state;
    final guidance = c.currentGuidance;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: System Status & Debug Toggle
            _buildTopBar(c),

            // Giant Accessible Interaction Area (Full screen touch target)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: c.onUserTap,
                onDoubleTap: c.onUserDoubleTap,
                child: Semantics(
                  label: _getAccessibleSemanticLabel(state, guidance),
                  button: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildStateIcon(state, guidance?.direction),
                        const SizedBox(height: 32),
                        _buildPrimaryStatusText(state, guidance),
                        const SizedBox(height: 16),
                        _buildSecondaryHelperText(state, c),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Collapsible Debug HUD for Hackathon Demos & Testing
            if (_showDebugHud) _buildDebugHud(c),

            // Bottom Tap Prompt (Accessibility cue)
            _buildBottomPrompt(state),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(FindSessionController c) {
    final isBleConnected = c.wearableService.isConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade900,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isBleConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: isBleConnected ? const Color(0xFF00E676) : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                c.wearableService.statusMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              _showDebugHud ? Icons.visibility_off : Icons.developer_mode,
              color: const Color(0xFFFFE600),
            ),
            tooltip: 'Toggle Debug HUD',
            onPressed: () {
              setState(() {
                _showDebugHud = !_showDebugHud;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStateIcon(FindSessionState state, Direction? direction) {
    IconData icon;
    Color color;

    switch (state) {
      case FindSessionState.idle:
        icon = Icons.mic;
        color = const Color(0xFFFFE600);
        break;
      case FindSessionState.listening:
        icon = Icons.hearing;
        color = const Color(0xFF00E676);
        break;
      case FindSessionState.parsingIntent:
        icon = Icons.psychology;
        color = Colors.lightBlueAccent;
        break;
      case FindSessionState.searching:
        icon = Icons.center_focus_weak;
        color = Colors.orangeAccent;
        break;
      case FindSessionState.guiding:
        color = const Color(0xFFFFE600);
        if (direction == Direction.left) {
          icon = Icons.arrow_back;
        } else if (direction == Direction.right) {
          icon = Icons.arrow_forward;
        } else {
          icon = Icons.arrow_upward;
        }
        break;
      case FindSessionState.nearTarget:
        icon = Icons.check_circle;
        color = const Color(0xFF00E676);
        break;
      case FindSessionState.completed:
        icon = Icons.thumb_up;
        color = const Color(0xFF00E676);
        break;
      case FindSessionState.error:
        icon = Icons.error_outline;
        color = Colors.redAccent;
        break;
    }

    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 4),
      ),
      child: Icon(icon, size: 70, color: color),
    );
  }

  Widget _buildPrimaryStatusText(FindSessionState state, dynamic guidance) {
    String text;
    Color color = Colors.white;

    switch (state) {
      case FindSessionState.idle:
        text = 'TAP TO FIND';
        color = const Color(0xFFFFE600);
        break;
      case FindSessionState.listening:
        text = 'LISTENING...';
        color = const Color(0xFF00E676);
        break;
      case FindSessionState.parsingIntent:
        text = 'UNDERSTANDING...';
        color = Colors.lightBlueAccent;
        break;
      case FindSessionState.searching:
        text = 'SEARCHING...';
        color = Colors.orangeAccent;
        break;
      case FindSessionState.guiding:
        text = guidance != null ? guidance.imagePosition.toUpperCase() : 'GUIDING';
        color = const Color(0xFFFFE600);
        break;
      case FindSessionState.nearTarget:
        text = 'CLOSE TO HAND';
        color = const Color(0xFF00E676);
        break;
      case FindSessionState.completed:
        text = 'OBJECT LOCATED';
        color = const Color(0xFF00E676);
        break;
      case FindSessionState.error:
        text = 'RETRY';
        color = Colors.redAccent;
        break;
    }

    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: 34,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
      ),
    );
  }

  Widget _buildSecondaryHelperText(FindSessionState state, FindSessionController c) {
    String subtext;

    if (state == FindSessionState.idle) {
      subtext = 'Tap anywhere on screen\nto say "Find my keys"';
    } else if (state == FindSessionState.listening) {
      subtext = c.lastVoiceTranscript.isNotEmpty
          ? '"${c.lastVoiceTranscript}"'
          : 'Speak your object name clearly';
    } else if (state == FindSessionState.searching) {
      subtext = 'Target: "${c.targetObject}"\nSlowly scan your camera';
    } else if (state == FindSessionState.guiding && c.currentGuidance != null) {
      subtext = c.currentGuidance!.voiceMessage;
    } else if (state == FindSessionState.nearTarget) {
      subtext = 'Wristband vibrating fast.\nReach slowly forward.';
    } else {
      subtext = 'Double tap anytime to cancel';
    }

    return Text(
      subtext,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    );
  }

  Widget _buildBottomPrompt(FindSessionState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      color: Colors.grey.shade900,
      child: Text(
        state == FindSessionState.idle ? 'TAP SCREEN TO START' : 'DOUBLE TAP TO CANCEL',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFFFE600),
          fontSize: 15,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildDebugHud(FindSessionController c) {
    final camera = c.cameraController;

    return Container(
      height: 240,
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Live Camera Preview (if available)
          if (camera != null && camera.value.isInitialized)
            SizedBox(
              width: 130,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CameraPreview(camera),
              ),
            )
          else
            Container(
              width: 130,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: const Center(
                child: Text('Camera\nInactive', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            ),
          const SizedBox(width: 12),
          // Telemetry and Status
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DEBUG TELEMETRY', style: TextStyle(color: Color(0xFFFFE600), fontWeight: FontWeight.bold, fontSize: 13)),
                  const Divider(color: Colors.grey, height: 8),
                  Text('State: ${c.state.name}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('Target: ${c.targetObject}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('Direction: ${c.currentGuidance?.imagePosition ?? "none"}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('Haptic: ${c.currentGuidance?.hapticCommand.textValue ?? "STOP"}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('Proximity: ${c.currentGuidance?.proximity ?? "unknown"}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        onPressed: () {
                          c.wearableService.connect();
                        },
                        child: const Text('Connect BLE', style: TextStyle(fontSize: 11)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        onPressed: () => _showBackendUrlDialog(c),
                        child: const Text('Edit Server URL', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBackendUrlDialog(FindSessionController c) {
    final textController = TextEditingController(text: c.intentClient.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Backend Server URL', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'http://10.68.37.235:8000',
            labelText: 'FastAPI Server Address',
            labelStyle: TextStyle(color: Colors.amber),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              c.intentClient.baseUrl = textController.text.trim();
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getAccessibleSemanticLabel(FindSessionState state, dynamic guidance) {
    if (state == FindSessionState.idle) {
      return 'SENSE is ready. Tap anywhere on the screen to give a voice command to find an object.';
    } else if (state == FindSessionState.listening) {
      return 'Listening to your voice. Speak the name of the object you want to find.';
    } else if (state == FindSessionState.guiding && guidance != null) {
      return guidance.voiceMessage;
    }
    return 'SENSE assistive finder active.';
  }
}
