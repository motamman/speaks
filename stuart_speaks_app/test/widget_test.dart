// Basic widget test for Stuart Speaks App

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stuart_speaks_app/main.dart';

void main() {
  testWidgets('App starts with TTS screen', (WidgetTester tester) async {
    // Setup mock SharedPreferences for testing
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const StuartSpeaksApp());

    // Wait for async initialization to complete
    await tester.pump(const Duration(seconds: 1));

    // Verify that the app title is present
    expect(find.text('Stuart Speaks'), findsOneWidget);

    // Verify that the speak button is present
    expect(find.text('SPEAK NOW'), findsOneWidget);
  });
}
