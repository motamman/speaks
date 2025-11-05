/// Input validation utilities
class InputValidator {
  /// Maximum text length for TTS (5000 characters)
  static const int maxTextLength = 5000;

  /// Maximum phrase length (500 characters)
  static const int maxPhraseLength = 500;

  /// Minimum text length for TTS (1 character)
  static const int minTextLength = 1;

  /// Validate TTS input text
  static ValidationResult validateTTSInput(String text) {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return ValidationResult.error('Please enter some text to speak');
    }

    if (trimmed.length < minTextLength) {
      return ValidationResult.error('Text is too short');
    }

    if (trimmed.length > maxTextLength) {
      return ValidationResult.error(
        'Text is too long. Maximum $maxTextLength characters allowed.',
      );
    }

    return ValidationResult.valid();
  }

  /// Validate phrase input
  static ValidationResult validatePhraseInput(String text) {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return ValidationResult.error('Please enter a phrase');
    }

    if (trimmed.length > maxPhraseLength) {
      return ValidationResult.error(
        'Phrase is too long. Maximum $maxPhraseLength characters allowed.',
      );
    }

    return ValidationResult.valid();
  }

  /// Validate API key format
  static ValidationResult validateApiKey(String key) {
    final trimmed = key.trim();

    if (trimmed.isEmpty) {
      return ValidationResult.error('API key cannot be empty');
    }

    if (trimmed.length < 10) {
      return ValidationResult.error('API key appears to be invalid (too short)');
    }

    return ValidationResult.valid();
  }

  /// Check if text is approaching the limit
  static bool isApproachingLimit(String text, int limit) {
    return text.length >= (limit * 0.8); // 80% of limit
  }

  /// Get remaining character count
  static int getRemainingChars(String text, int limit) {
    return limit - text.length;
  }

  /// Get character count message
  static String getCharacterCountMessage(String text, int limit) {
    final remaining = getRemainingChars(text, limit);
    if (remaining < 0) {
      return '${remaining.abs()} characters over limit';
    } else if (remaining < limit * 0.2) {
      return '$remaining characters remaining';
    }
    return '';
  }
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult._(this.isValid, this.errorMessage);

  factory ValidationResult.valid() => const ValidationResult._(true, null);

  factory ValidationResult.error(String message) => ValidationResult._(false, message);

  @override
  String toString() => isValid ? 'Valid' : 'Invalid: $errorMessage';
}
