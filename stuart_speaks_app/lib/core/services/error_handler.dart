import 'dart:io';
import 'package:flutter/material.dart';
import '../providers/tts_provider.dart';
import 'app_logger.dart';

/// Categorized error information for user display
class UserFriendlyError {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? action;

  const UserFriendlyError({
    required this.title,
    required this.message,
    this.actionLabel,
    this.action,
  });
}

/// Central error handling service
class ErrorHandler {
  final AppLogger _logger;

  ErrorHandler({AppLogger? logger}) : _logger = logger ?? AppLogger('ErrorHandler');

  /// Convert technical exception to user-friendly error
  UserFriendlyError handleError(dynamic error, {StackTrace? stackTrace}) {
    _logger.error('Handling error', error: error, stackTrace: stackTrace);

    // TTS Provider specific errors
    if (error is TTSProviderException) {
      return _handleTTSError(error);
    }

    // Network errors
    if (error is SocketException) {
      return const UserFriendlyError(
        title: 'No Internet Connection',
        message: 'Please check your internet connection and try again.',
      );
    }

    // HTTP errors
    if (error is HttpException) {
      return const UserFriendlyError(
        title: 'Network Error',
        message: 'Unable to communicate with the speech service. Please try again.',
      );
    }

    // Format errors
    if (error is FormatException) {
      return const UserFriendlyError(
        title: 'Invalid Data',
        message: 'The speech service returned unexpected data. Please try a different provider.',
      );
    }

    // Timeout errors
    if (error is TimeoutException) {
      return const UserFriendlyError(
        title: 'Request Timeout',
        message: 'The request took too long. Please try again.',
      );
    }

    // Generic fallback
    return UserFriendlyError(
      title: 'Unexpected Error',
      message: 'An unexpected error occurred. Please try again.',
    );
  }

  /// Handle TTS provider specific errors
  UserFriendlyError _handleTTSError(TTSProviderException error) {
    final message = error.message.toLowerCase();
    final statusCode = error.statusCode;

    // Check for authentication errors
    if (statusCode == 401 || statusCode == 403 || message.contains('unauthorized') || message.contains('forbidden')) {
      return const UserFriendlyError(
        title: 'Authentication Failed',
        message: 'Your API key is invalid or expired. Please check your settings.',
        actionLabel: 'Open Settings',
      );
    }

    // Check for rate limiting
    if (statusCode == 429 || message.contains('rate limit') || message.contains('too many requests')) {
      return const UserFriendlyError(
        title: 'Rate Limit Exceeded',
        message: 'Too many requests. Please wait a moment and try again.',
      );
    }

    // Check for invalid input
    if (statusCode == 400 || message.contains('invalid') || message.contains('bad request')) {
      return UserFriendlyError(
        title: 'Invalid Input',
        message: error.message,
      );
    }

    // Check for server errors
    if (statusCode != null && statusCode >= 500) {
      return const UserFriendlyError(
        title: 'Service Error',
        message: 'The speech service is temporarily unavailable. Please try again later.',
      );
    }

    // Generic TTS error
    return UserFriendlyError(
      title: 'Speech Error',
      message: error.message.isNotEmpty ? error.message : 'Unable to generate speech. Please try again.',
    );
  }

  /// Show error dialog with user-friendly message
  void showErrorDialog(BuildContext context, dynamic error, {StackTrace? stackTrace}) {
    final friendlyError = handleError(error, stackTrace: stackTrace);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(friendlyError.title)),
          ],
        ),
        content: Text(friendlyError.message),
        actions: [
          if (friendlyError.actionLabel != null && friendlyError.action != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                friendlyError.action?.call();
              },
              child: Text(friendlyError.actionLabel!),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar
  void showErrorSnackbar(BuildContext context, dynamic error, {StackTrace? stackTrace}) {
    final friendlyError = handleError(error, stackTrace: stackTrace);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friendlyError.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(friendlyError.message),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 4),
        action: friendlyError.actionLabel != null && friendlyError.action != null
            ? SnackBarAction(
                label: friendlyError.actionLabel!,
                textColor: Colors.white,
                onPressed: friendlyError.action!,
              )
            : null,
      ),
    );
  }
}

/// Timeout exception
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
