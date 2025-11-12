import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/models/wheel_position.dart';
import '../../../core/models/word.dart';
import 'word_wheel_controller.dart';

/// Visual representation of the wheel
/// This layer is IgnorePointer - all gestures handled by GestureCaptureLayer
class WheelVisualLayer extends StatelessWidget {
  final WordWheelController controller;
  final Size wheelSize;
  final bool alwaysVisible;

  const WheelVisualLayer({
    super.key,
    required this.controller,
    required this.wheelSize,
    this.alwaysVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!alwaysVisible && !controller.isVisible) {
          return const SizedBox.shrink();
        }

        // Calculate positions based on actual wheel size (may differ from controller config)
        final centerX = wheelSize.width / 2;
        final centerY = wheelSize.height / 2;
        final innerRingDistance = wheelSize.width * 0.25;
        final outerRingDistance = wheelSize.width * 0.45;
        final innerRingDistanceY = wheelSize.height * 0.25;
        final outerRingDistanceY = wheelSize.height * 0.45;

        return IgnorePointer(
          child: CustomPaint(
              painter: WheelPainterV2(
                words: controller.visibleWords,
                isExpanded: controller.isExpanded,
                hoveredWord: controller.hoveredWord,
                dragPosition: controller.dragPosition,
                isHolding: controller.state == WheelState.dragging ||
                    controller.state == WheelState.visible,
                centerX: centerX,
                centerY: centerY,
                innerRingDistance: innerRingDistance,
                outerRingDistance: outerRingDistance,
                innerRingDistanceY: innerRingDistanceY,
                outerRingDistanceY: outerRingDistanceY,
              ),
              size: wheelSize,
            ),
        );
      },
    );
  }
}

/// Custom painter for the word wheel V2
class WheelPainterV2 extends CustomPainter {
  final List<Word> words;
  final bool isExpanded;
  final Word? hoveredWord;
  final Offset? dragPosition;
  final bool isHolding;
  final double centerX;
  final double centerY;
  final double innerRingDistance;
  final double outerRingDistance;
  final double innerRingDistanceY;
  final double outerRingDistanceY;

  const WheelPainterV2({
    required this.words,
    required this.isExpanded,
    required this.hoveredWord,
    required this.dragPosition,
    required this.isHolding,
    required this.centerX,
    required this.centerY,
    required this.innerRingDistance,
    required this.outerRingDistance,
    required this.innerRingDistanceY,
    required this.outerRingDistanceY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(centerX, centerY);

    // Draw center control point
    _drawCenterControl(canvas, center);

    // Draw drag indicator if dragging
    if (dragPosition != null) {
      _drawDragIndicator(canvas, center, dragPosition!);
    }

    // Draw words
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final position = _calculateWordPosition(i);
      final isHovered = hoveredWord == word;

      _drawWord(canvas, word, position, i, isHovered);
    }

    // Draw expansion hint if not expanded
    if (!isExpanded && words.length > 4 && !isHolding) {
      _drawExpansionHint(canvas, center);
    }

    // Draw hovered word preview in center (after center control so it's on top)
    if (hoveredWord != null && isHolding) {
      _drawCenterPreview(canvas, center, hoveredWord!.text);
    }

    // Draw floating label above finger when dragging
    if (hoveredWord != null && dragPosition != null && isHolding) {
      _drawFloatingLabel(canvas, dragPosition!, hoveredWord!.text);
    }
  }

  void _drawCenterControl(Canvas canvas, Offset center) {
    // Outer touch target
    canvas.drawCircle(
      center,
      40,
      Paint()
        ..color = Colors.blue.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill,
    );

    // Inner circle (larger if holding to show preview text)
    final centerRadius = (isHolding && hoveredWord != null) ? 35.0 : 20.0;
    canvas.drawCircle(
      center,
      centerRadius,
      Paint()
        ..color = isHolding ? Colors.blue[700]! : Colors.blue
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawCircle(
      center,
      centerRadius,
      Paint()
        ..color = Colors.blue[900]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawCenterPreview(Canvas canvas, Offset center, String text) {
    final textStyle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: 60);

    // Draw text in center
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );
  }

  void _drawFloatingLabel(Canvas canvas, Offset fingerPos, String text) {
    // Position label above finger (offset upward)
    final labelOffset = Offset(fingerPos.dx, fingerPos.dy - 60);

    final textStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();

    // Draw background pill
    final padding = 12.0;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: labelOffset,
        width: textPainter.width + padding * 2,
        height: textPainter.height + padding * 2,
      ),
      const Radius.circular(8),
    );

    // Shadow
    canvas.drawRRect(
      bgRect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Background
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.blue[900]!
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Draw text
    textPainter.paint(
      canvas,
      Offset(
        labelOffset.dx - (textPainter.width / 2),
        labelOffset.dy - (textPainter.height / 2),
      ),
    );
  }

  void _drawDragIndicator(Canvas canvas, Offset center, Offset dragPos) {
    canvas.drawLine(
      center,
      dragPos,
      Paint()
        ..color = Colors.blue.withValues(alpha: 0.5)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      dragPos,
      8,
      Paint()..color = Colors.blue,
    );
  }

  void _drawWord(
    Canvas canvas,
    Word word,
    WheelPosition position,
    int index,
    bool isHovered,
  ) {
    var buttonSize = 70.0 - (index * 4.0).clamp(0.0, 20.0);
    if (isHovered) buttonSize *= 1.3;

    final buttonRadius = buttonSize / 2;

    // Draw connector line
    canvas.drawLine(
      Offset(centerX, centerY),
      position.offset,
      Paint()
        ..color = isHovered
            ? Colors.blue.withValues(alpha: 0.6)
            : Colors.grey.withValues(alpha: 0.2)
        ..strokeWidth = isHovered ? 3 : 1.5,
    );

    // Draw button background
    canvas.drawCircle(
      position.offset,
      buttonRadius,
      Paint()
        ..color = isHovered
            ? Colors.blue.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
    );

    // Draw button border
    canvas.drawCircle(
      position.offset,
      buttonRadius,
      Paint()
        ..color = isHovered ? Colors.blue[900]! : Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHovered ? 4 : 2,
    );

    // Draw word text
    final textStyle = TextStyle(
      fontSize: isHovered ? 20 : 16 - (index * 0.5),
      fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
      color: isHovered ? Colors.white : Colors.black87,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: word.text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: buttonSize - 10);
    textPainter.paint(
      canvas,
      Offset(
        position.offset.dx - (textPainter.width / 2),
        position.offset.dy - (textPainter.height / 2),
      ),
    );

    // Draw usage count badge for top 3
    if (index < 3 && !isHovered && word.usageCount > 0) {
      _drawUsageBadge(canvas, position.offset, word.usageCount, buttonRadius);
    }
  }

  void _drawUsageBadge(
    Canvas canvas,
    Offset wordPos,
    int usageCount,
    double buttonRadius,
  ) {
    final badgePos = Offset(
      wordPos.dx + buttonRadius - 8,
      wordPos.dy - buttonRadius + 8,
    );

    canvas.drawCircle(
      badgePos,
      14,
      Paint()..color = Colors.green,
    );

    canvas.drawCircle(
      badgePos,
      14,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final badgeText = TextPainter(
      text: TextSpan(
        text: '$usageCount',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    badgeText.layout();
    badgeText.paint(
      canvas,
      Offset(
        badgePos.dx - (badgeText.width / 2),
        badgePos.dy - (badgeText.height / 2),
      ),
    );
  }

  void _drawExpansionHint(Canvas canvas, Offset center) {
    final arrowPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 4; i++) {
      final angle = (pi / 2) * i;
      final startPos = Offset(
        center.dx + (60 * cos(angle)),
        center.dy + (60 * sin(angle)),
      );
      final endPos = Offset(
        center.dx + (75 * cos(angle)),
        center.dy + (75 * sin(angle)),
      );

      canvas.drawLine(startPos, endPos, arrowPaint);
    }
  }

  WheelPosition _calculateWordPosition(int index) {
    final isInnerRing = index < 4;
    final ringIndex = isInnerRing ? index : index - 4;
    final ringSize = isInnerRing ? 4 : 8;

    final angleOffset = -pi / 2;
    final angle = angleOffset + (2 * pi / ringSize) * ringIndex;

    // Use separate X and Y distances for elliptical positioning
    final distanceX = isInnerRing ? innerRingDistance : outerRingDistance;
    final distanceY = isInnerRing ? innerRingDistanceY : outerRingDistanceY;

    final x = centerX + (distanceX * cos(angle));
    final y = centerY + (distanceY * sin(angle));

    return WheelPosition(
      offset: Offset(x, y),
      angle: angle,
      distance: distanceX, // Use X distance for reference
      isInnerRing: isInnerRing,
      word: words[index],
    );
  }

  @override
  bool shouldRepaint(WheelPainterV2 oldDelegate) {
    // Only repaint when something actually changed
    return oldDelegate.isExpanded != isExpanded ||
        oldDelegate.hoveredWord != hoveredWord ||
        oldDelegate.dragPosition != dragPosition ||
        oldDelegate.isHolding != isHolding ||
        oldDelegate.words.length != words.length;
  }
}
