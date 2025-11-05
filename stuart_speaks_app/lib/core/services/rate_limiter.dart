import 'app_logger.dart';

/// Rate limiter to prevent excessive API calls
class RateLimiter {
  final Map<String, DateTime> _lastCalls = {};
  final Duration minimumDelay;
  final AppLogger _logger;

  RateLimiter({
    required this.minimumDelay,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger('RateLimiter');

  /// Throttle an operation - ensures minimum delay between calls
  Future<T> throttle<T>(
    String key,
    Future<T> Function() operation,
  ) async {
    final lastCall = _lastCalls[key];

    if (lastCall != null) {
      final elapsed = DateTime.now().difference(lastCall);

      if (elapsed < minimumDelay) {
        final waitTime = minimumDelay - elapsed;
        _logger.debug(
          'Rate limiting $key, waiting ${waitTime.inMilliseconds}ms',
        );
        await Future.delayed(waitTime);
      }
    }

    _lastCalls[key] = DateTime.now();
    return operation();
  }

  /// Check if an operation can be performed without waiting
  bool canPerform(String key) {
    final lastCall = _lastCalls[key];

    if (lastCall == null) return true;

    final elapsed = DateTime.now().difference(lastCall);
    return elapsed >= minimumDelay;
  }

  /// Get remaining wait time for a key
  Duration getRemainingWait(String key) {
    final lastCall = _lastCalls[key];

    if (lastCall == null) return Duration.zero;

    final elapsed = DateTime.now().difference(lastCall);

    if (elapsed >= minimumDelay) return Duration.zero;

    return minimumDelay - elapsed;
  }

  /// Clear rate limit for a specific key
  void clear(String key) {
    _lastCalls.remove(key);
  }

  /// Clear all rate limits
  void clearAll() {
    _lastCalls.clear();
  }
}

/// Rate limit exception thrown when an operation is rate limited
class RateLimitException implements Exception {
  final String message;
  final Duration waitTime;

  RateLimitException(this.message, this.waitTime);

  @override
  String toString() => 'RateLimitException: $message (wait ${waitTime.inMilliseconds}ms)';
}
