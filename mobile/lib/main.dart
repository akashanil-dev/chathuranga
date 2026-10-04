import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services/audio_feedback_service.dart';
import 'features/finding/controllers/find_session_controller.dart';
import 'features/finding/presentation/accessible_home_page.dart';
import 'features/intent/services/intent_client.dart';
import 'features/voice/services/speech_service.dart';
import 'features/wearable/services/ble_wearable_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation for consistent spatial coordinate orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set system UI overlay (black navigation bar, dark status bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize core services
  final audioService = AudioFeedbackService();
  await audioService.initialize();

  final speechService = SpeechService();
  final intentClient = IntentClient();
  final wearableService = BleWearableService()..startAutoConnect();

  final controller = FindSessionController(
    speechService: speechService,
    audioService: audioService,
    intentClient: intentClient,
    wearableService: wearableService,
  );

  runApp(SenseApp(controller: controller));
}

class SenseApp extends StatelessWidget {
  final FindSessionController controller;

  const SenseApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SENSE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFE600), // High-contrast accessible yellow
          secondary: Color(0xFF00E676), // Vibrant accessible green
          surface: Color(0xFF121212),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Colors.white),
        ),
      ),
      home: AccessibleHomePage(controller: controller),
    );
  }
}
