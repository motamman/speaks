import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/tts/tts_screen.dart';

void main() {
  // Lock orientation to portrait for better accessibility
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const StuartSpeaksApp());
}

class StuartSpeaksApp extends StatelessWidget {
  const StuartSpeaksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stuart Speaks',
      debugShowCheckedModeBanner: false,
      // Disable shake-to-undo for accessibility (ALS user cannot shake device)
      builder: (context, child) {
        return Actions(
          actions: {
            UndoTextIntent: DoNothingAction(consumesKey: false),
            RedoTextIntent: DoNothingAction(consumesKey: false),
          },
          child: child!,
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        // Match the backend design colors
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB), // Blue from backend (#2563eb)
          brightness: Brightness.light,
          surface: const Color(0xFFEAD4A4), // Tan/beige background (#EAD4A4)
          primary: const Color(0xFF2563EB), // Primary blue
        ),
        scaffoldBackgroundColor: const Color(0xFFEAD4A4), // Tan background

        // Accessibility: Larger touch targets
        materialTapTargetSize: MaterialTapTargetSize.padded,

        // Accessibility: Larger text by default
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18),
          bodyMedium: TextStyle(fontSize: 16),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),

        // High contrast for better visibility
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(48, 48), // Minimum touch target
            textStyle: const TextStyle(fontSize: 18),
            backgroundColor: const Color(0xFF2563EB), // Blue buttons
            foregroundColor: Colors.white,
          ),
        ),

        // AppBar styling
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEAD4A4), // Tan background
          foregroundColor: Color(0xFF2563EB), // Blue text
          elevation: 0,
        ),
      ),
      home: const TTSScreen(),
    );
  }
}
