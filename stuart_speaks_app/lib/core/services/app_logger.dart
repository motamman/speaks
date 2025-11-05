import 'package:flutter/foundation.dart';

/// Structured logging service for the application
class AppLogger {
  final String _tag;

  AppLogger([this._tag = 'StuartSpeaks']);

  /// Log debug information (only in debug mode)
  void debug(String message, {dynamic error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint('[$_tag] DEBUG: $message');
      if (error != null) {
        debugPrint('  Error: $error');
      }
      if (stackTrace != null) {
        debugPrint('  Stack: $stackTrace');
      }
    }
  }

  /// Log informational messages
  void info(String message) {
    debugPrint('[$_tag] INFO: $message');
  }

  /// Log warnings
  void warning(String message, {dynamic error, StackTrace? stackTrace}) {
    debugPrint('[$_tag] WARNING: $message');
    if (error != null) {
      debugPrint('  Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('  Stack: $stackTrace');
    }
  }

  /// Log errors
  void error(String message, {dynamic error, StackTrace? stackTrace}) {
    debugPrint('[$_tag] ERROR: $message');
    if (error != null) {
      debugPrint('  Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('  Stack: $stackTrace');
    }
  }

  /// Create a logger with a specific tag
  AppLogger withTag(String tag) => AppLogger(tag);
}
