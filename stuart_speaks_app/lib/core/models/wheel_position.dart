import 'dart:ui';

import 'word.dart';

/// Represents the position of a word in the predictive wheel
class WheelPosition {
  final Offset offset;
  final double angle;
  final double distance;
  final bool isInnerRing;
  final Word word;

  const WheelPosition({
    required this.offset,
    required this.angle,
    required this.distance,
    required this.isInnerRing,
    required this.word,
  });

  /// Calculate if a point is within this word's button
  bool containsPoint(Offset point, double buttonRadius) {
    final dx = point.dx - offset.dx;
    final dy = point.dy - offset.dy;
    final distanceSquared = dx * dx + dy * dy;
    return distanceSquared <= buttonRadius * buttonRadius;
  }
}
