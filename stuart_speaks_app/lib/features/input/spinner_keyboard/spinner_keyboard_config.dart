import 'package:flutter/material.dart';

/// Configuration for spinner keyboard sizing and layout
class SpinnerKeyboardConfig {
  final double centerX;
  final double centerY;
  final double letterRingRadius; // Outer ring - 26 letters
  final double numberRingRadius; // Middle ring - 10 numbers
  final double punctuationRingRadius; // Inner ring - punctuation
  final double centerHubRadius; // Center for text display
  final double outsideRimThreshold; // Distance beyond outer ring for special actions
  final Duration activationDelay;

  const SpinnerKeyboardConfig({
    required this.centerX,
    required this.centerY,
    required this.letterRingRadius,
    required this.numberRingRadius,
    required this.punctuationRingRadius,
    this.centerHubRadius = 50.0,
    this.outsideRimThreshold = 30.0,
    this.activationDelay = const Duration(milliseconds: 400),
  });

  /// Create responsive config from screen size
  factory SpinnerKeyboardConfig.responsive(Size screenSize) {
    final wheelSize = _calculateWheelSize(screenSize);
    final radius = wheelSize.width / 2;

    return SpinnerKeyboardConfig(
      centerX: radius,
      centerY: radius,
      letterRingRadius: radius * 0.85, // Outer ring
      numberRingRadius: radius * 0.60, // Middle ring
      punctuationRingRadius: radius * 0.38, // Inner ring
      centerHubRadius: radius * 0.22,
    );
  }

  /// Calculate wheel size based on screen dimensions
  static Size _calculateWheelSize(Size screenSize) {
    final shortestSide = screenSize.shortestSide;

    if (shortestSide < 375) {
      // Small phones (iPhone SE)
      return const Size(320, 320);
    } else if (shortestSide < 768) {
      // Regular phones
      return const Size(400, 400);
    } else {
      // Tablets
      return const Size(500, 500);
    }
  }

  /// Get the wheel size for this configuration
  Size get wheelSize => Size(centerX * 2, centerY * 2);

  /// Check if a position is outside the outer rim (for special actions)
  bool isOutsideRim(Offset position) {
    final center = Offset(centerX, centerY);
    final distance = (position - center).distance;
    return distance > letterRingRadius + outsideRimThreshold;
  }

  /// Check if outside rim with hysteresis buffer (to prevent jitter)
  /// When already outside, require coming back further inside to re-enter
  bool isOutsideRimWithHysteresis(Offset position, double hysteresisBuffer) {
    final center = Offset(centerX, centerY);
    final distance = (position - center).distance;
    // When already outside, must come back inside by hysteresisBuffer amount
    return distance > letterRingRadius + outsideRimThreshold - hysteresisBuffer;
  }

  /// Determine which ring a position is in
  /// Uses exclusive ranges with clear boundaries
  SpinnerRing? getRingAtPosition(Offset position) {
    final center = Offset(centerX, centerY);
    final distance = (position - center).distance;

    // Define clear ring boundaries (inner edge to outer edge)
    final punctOuter = (centerHubRadius + punctuationRingRadius) / 2 + punctuationRingRadius / 2;
    final numberOuter = (punctuationRingRadius + numberRingRadius) / 2 + numberRingRadius / 3;
    final letterOuter = letterRingRadius + outsideRimThreshold;

    if (distance < centerHubRadius) {
      return SpinnerRing.center;
    } else if (distance < punctOuter) {
      return SpinnerRing.punctuation;
    } else if (distance < numberOuter) {
      return SpinnerRing.numbers;
    } else if (distance < letterOuter) {
      return SpinnerRing.letters;
    }
    return null; // Outside all rings
  }
}

/// Enum for the different rings of the spinner
enum SpinnerRing {
  center,
  punctuation,
  numbers,
  letters,
}
