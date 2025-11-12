import 'package:flutter/material.dart';

/// Configuration for word wheel sizing and layout
class WordWheelConfig {
  final double centerX;
  final double centerY;
  final double innerRingDistance;
  final double outerRingDistance;
  final double innerRingDistanceY; // Vertical radius for inner ring
  final double outerRingDistanceY; // Vertical radius for outer ring
  final double deadZoneRadius;
  final Duration activationDelay;
  final Duration hideAnimationDuration;

  const WordWheelConfig({
    required this.centerX,
    required this.centerY,
    required this.innerRingDistance,
    required this.outerRingDistance,
    double? innerRingDistanceY,
    double? outerRingDistanceY,
    this.deadZoneRadius = 30.0,
    this.activationDelay = const Duration(milliseconds: 400),
    this.hideAnimationDuration = const Duration(milliseconds: 200),
  })  : innerRingDistanceY = innerRingDistanceY ?? innerRingDistance,
        outerRingDistanceY = outerRingDistanceY ?? outerRingDistance;

  /// Helper to create responsive config from screen size
  factory WordWheelConfig.responsive(Size screenSize) {
    final wheelSize = _calculateWheelSize(screenSize);

    return WordWheelConfig(
      centerX: wheelSize.width / 2,
      centerY: wheelSize.height / 2,
      innerRingDistance: wheelSize.width * 0.25,
      outerRingDistance: wheelSize.width * 0.45,
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
}
