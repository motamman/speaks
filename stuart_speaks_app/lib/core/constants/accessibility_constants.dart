import 'package:flutter/widgets.dart';

/// Accessibility constants for motor impairment support
///
/// Following WCAG 2.1 Level AAA guidelines and platform recommendations:
/// - iOS: 44x44pt minimum tap target
/// - Android: 48x48dp minimum tap target
/// - For motor impairments: 48x48 or larger recommended
class AccessibilityConstants {
  // Minimum tap target sizes
  static const double minTapTargetSize = 48.0; // Meets both iOS and Android
  static const double recommendedTapTargetSize = 56.0; // Better for motor impairments
  static const double largeTapTargetSize = 64.0; // Best for severe impairments

  // Icon sizes
  static const double smallIconSize = 20.0;
  static const double standardIconSize = 24.0;
  static const double largeIconSize = 32.0;
  static const double extraLargeIconSize = 40.0;

  // Spacing between interactive elements
  static const double minSpacing = 8.0;
  static const double recommendedSpacing = 12.0;
  static const double comfortableSpacing = 16.0;

  // Button heights
  static const double smallButtonHeight = 40.0;
  static const double standardButtonHeight = 48.0;
  static const double largeButtonHeight = 56.0;
  static const double extraLargeButtonHeight = 70.0; // Current "SPEAK NOW" button

  // Touch feedback durations
  static const Duration shortFeedbackDuration = Duration(milliseconds: 100);
  static const Duration standardFeedbackDuration = Duration(milliseconds: 200);
  static const Duration longFeedbackDuration = Duration(milliseconds: 300);

  // Long press duration (for users with tremors)
  static const Duration longPressDuration = Duration(milliseconds: 500);
  static const Duration accessibleLongPressDuration = Duration(milliseconds: 800);

  // Accidental tap prevention
  static const Duration doubleTapWindow = Duration(milliseconds: 300);
  static const Duration destructiveActionDelay = Duration(milliseconds: 500);
}

/// Helper widget for accessible tap targets
class AccessibleTapTarget {
  /// Creates minimum constraints for tap targets
  static BoxConstraints minimum() => const BoxConstraints(
        minWidth: AccessibilityConstants.minTapTargetSize,
        minHeight: AccessibilityConstants.minTapTargetSize,
      );

  /// Creates recommended constraints for tap targets
  static BoxConstraints recommended() => const BoxConstraints(
        minWidth: AccessibilityConstants.recommendedTapTargetSize,
        minHeight: AccessibilityConstants.recommendedTapTargetSize,
      );

  /// Creates large constraints for users with motor impairments
  static BoxConstraints large() => const BoxConstraints(
        minWidth: AccessibilityConstants.largeTapTargetSize,
        minHeight: AccessibilityConstants.largeTapTargetSize,
      );
}
