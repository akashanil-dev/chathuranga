import 'package:flutter/material.dart';
import 'core/app.dart';
import 'ui/screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await speech.init();
  } catch (_) {}
  runApp(const SenseApp());
}

class SenseApp extends StatelessWidget {
  const SenseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SENSE',
        debugShowCheckedModeBanner: false,
        theme: senseTheme(),
        home: const ConnectScreen(),
      );
}
