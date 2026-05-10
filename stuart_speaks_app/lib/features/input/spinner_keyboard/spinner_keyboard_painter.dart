import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/models/word.dart';
import 'spinner_keyboard_controller.dart';

/// Custom painter for the spinner keyboard
class SpinnerKeyboardPainter extends CustomPainter {
  final SpinnerKeyboardController controller;
  final bool isHolding;
  final double dwellProgress; // 0.0 to 1.0
  final bool isLeftHanded;
  final bool isShiftActive;

  const SpinnerKeyboardPainter({
    required this.controller,
    required this.isHolding,
    this.dwellProgress = 0.0,
    this.isLeftHanded = false,
    this.isShiftActive = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(controller.config.centerX, controller.config.centerY);

    // Draw background circles for rings
    _drawRingBackgrounds(canvas, center);

    // Draw punctuation ring (innermost)
    _drawPunctuationRing(canvas, center);

    // Draw number ring (middle)
    _drawNumberRing(canvas, center);

    // Draw letter ring (outer)
    _drawLetterRing(canvas, center);

    // Draw center hub with built string
    _drawCenterHub(canvas, center);

    // Draw drag indicator if dragging
    if (controller.dragPosition != null && isHolding) {
      _drawDragIndicator(canvas, center, controller.dragPosition!);
    }

    // Draw outside rim indicator if outside
    if (controller.isOutsideRim && isHolding) {
      _drawOutsideRimIndicator(canvas, center);
    }

    // Draw floating label above finger
    if (controller.hoveredKey != null && controller.dragPosition != null && isHolding) {
      _drawFloatingLabel(canvas, controller.dragPosition!, controller.hoveredKey!);
    }
  }

  void _drawRingBackgrounds(Canvas canvas, Offset center) {
    final config = controller.config;

    // Outer ring background (letters)
    canvas.drawCircle(
      center,
      config.letterRingRadius + 25,
      Paint()
        ..color = Colors.grey.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );

    // Ring separators
    canvas.drawCircle(
      center,
      config.letterRingRadius - 15,
      Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    canvas.drawCircle(
      center,
      config.numberRingRadius - 15,
      Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawLetterRing(Canvas canvas, Offset center) {
    final letters = SpinnerKeyboardController.letters;
    final config = controller.config;

    // Calculate segment dimensions
    final innerRadius = config.numberRingRadius + 15;
    final outerRadius = config.letterRingRadius + 20;
    final segmentAngle = 2 * pi / letters.length;

    for (var i = 0; i < letters.length; i++) {
      final letter = letters[i];
      final angle = controller.getLetterAngle(letter);

      final isHovered = controller.hoveredKey == letter;
      final isAnchor = controller.anchorKey == letter;

      // Apply shift to display label
      final displayLabel = isShiftActive ? letter.toUpperCase() : letter.toLowerCase();

      _drawSegmentKey(
        canvas,
        center,
        angle,
        segmentAngle,
        innerRadius,
        outerRadius,
        displayLabel,
        isHovered: isHovered,
        isAnchor: isAnchor,
      );
    }
  }

  void _drawSegmentKey(
    Canvas canvas,
    Offset center,
    double centerAngle,
    double segmentAngle,
    double innerRadius,
    double outerRadius,
    String label, {
    required bool isHovered,
    required bool isAnchor,
    Color ringColor = Colors.blue,
  }) {
    final startAngle = centerAngle - segmentAngle / 2;
    final sweepAngle = segmentAngle;

    // Background color - show dwell progress with gradient fill
    Color bgColor;
    if (isHovered && dwellProgress > 0) {
      // Blend from light to full color based on dwell progress
      bgColor = Color.lerp(
        ringColor.withValues(alpha: 0.3),
        ringColor.withValues(alpha: 0.95),
        dwellProgress,
      )!;
    } else if (isHovered) {
      bgColor = ringColor.withValues(alpha: 0.3);
    } else if (isAnchor) {
      bgColor = Colors.orange.withValues(alpha: 0.8);
    } else {
      bgColor = Colors.white.withValues(alpha: 0.95);
    }

    // Draw segment (pie slice between inner and outer radius)
    final path = Path();

    // Outer arc
    path.arcTo(
      Rect.fromCircle(center: center, radius: outerRadius),
      startAngle,
      sweepAngle,
      true,
    );

    // Line to inner arc end
    final innerEndX = center.dx + innerRadius * cos(startAngle + sweepAngle);
    final innerEndY = center.dy + innerRadius * sin(startAngle + sweepAngle);
    path.lineTo(innerEndX, innerEndY);

    // Inner arc (reverse direction)
    path.arcTo(
      Rect.fromCircle(center: center, radius: innerRadius),
      startAngle + sweepAngle,
      -sweepAngle,
      false,
    );

    path.close();

    // Fill
    canvas.drawPath(
      path,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.fill,
    );

    // Border - thicker when hovering with progress
    final borderWidth = isHovered ? (2.0 + dwellProgress * 3.0) : (isAnchor ? 3.0 : 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..color = isAnchor ? Colors.orange[800]! : (isHovered ? ringColor : Colors.grey[400]!)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // Draw dwell progress arc overlay on hovered key
    if (isHovered && dwellProgress > 0) {
      final progressPath = Path();
      final progressSweep = sweepAngle * dwellProgress;

      progressPath.arcTo(
        Rect.fromCircle(center: center, radius: outerRadius - 2),
        startAngle,
        progressSweep,
        true,
      );

      canvas.drawPath(
        progressPath,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }

    // Text at center of segment
    final textRadius = (innerRadius + outerRadius) / 2;
    final textX = center.dx + textRadius * cos(centerAngle);
    final textY = center.dy + textRadius * sin(centerAngle);

    final textStyle = TextStyle(
      fontSize: isHovered ? 20 : 16,
      fontWeight: isAnchor || isHovered ? FontWeight.bold : FontWeight.w600,
      color: (isHovered && dwellProgress > 0.5) ? Colors.white : Colors.black87,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        textX - textPainter.width / 2,
        textY - textPainter.height / 2,
      ),
    );
  }

  void _drawNumberRing(Canvas canvas, Offset center) {
    final numbers = SpinnerKeyboardController.numbers;
    final config = controller.config;

    // Calculate segment dimensions
    final innerRadius = config.punctuationRingRadius + 10;
    final outerRadius = config.numberRingRadius + 10;
    final segmentAngle = 2 * pi / numbers.length;

    for (var i = 0; i < numbers.length; i++) {
      final number = numbers[i];
      final angle = -pi / 2 + (2 * pi / numbers.length) * i;
      final isHovered = controller.hoveredKey == number;

      _drawSegmentKey(
        canvas,
        center,
        angle,
        segmentAngle,
        innerRadius,
        outerRadius,
        number,
        isHovered: isHovered,
        isAnchor: false,
        ringColor: Colors.teal,
      );
    }
  }

  void _drawPunctuationRing(Canvas canvas, Offset center) {
    final punctuation = SpinnerKeyboardController.punctuation;
    final config = controller.config;

    // Calculate segment dimensions
    final innerRadius = config.centerHubRadius + 5;
    final outerRadius = config.punctuationRingRadius + 5;
    final segmentAngle = 2 * pi / punctuation.length;

    for (var i = 0; i < punctuation.length; i++) {
      final punct = punctuation[i];
      final angle = -pi / 2 + (2 * pi / punctuation.length) * i;
      final isHovered = controller.hoveredKey == punct;

      _drawSegmentKey(
        canvas,
        center,
        angle,
        segmentAngle,
        innerRadius,
        outerRadius,
        punct,
        isHovered: isHovered,
        isAnchor: false,
        ringColor: Colors.purple,
      );
    }
  }

  void _drawCenterHub(Canvas canvas, Offset center) {
    final config = controller.config;
    final predictions = controller.wordPredictions;
    final hasPredictions = predictions.isNotEmpty;

    // Center circle background
    canvas.drawCircle(
      center,
      config.centerHubRadius,
      Paint()
        ..color = hasPredictions ? Colors.green[50]! : Colors.blue[50]!
        ..style = PaintingStyle.fill,
    );

    // Center circle border
    canvas.drawCircle(
      center,
      config.centerHubRadius,
      Paint()
        ..color = hasPredictions ? Colors.green[700]! : Colors.blue[700]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Built string text (always show at top of center)
    if (controller.builtString.isNotEmpty) {
      final stringY = hasPredictions
          ? center.dy - config.centerHubRadius * 0.5
          : center.dy;

      final textStyle = TextStyle(
        fontSize: hasPredictions ? 14 : _calculateFontSize(controller.builtString.length),
        fontWeight: FontWeight.bold,
        color: Colors.blue[900],
      );

      final textPainter = TextPainter(
        text: TextSpan(text: controller.builtString, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout(maxWidth: config.centerHubRadius * 1.8);
      textPainter.paint(
        canvas,
        Offset(
          center.dx - textPainter.width / 2,
          stringY - textPainter.height / 2,
        ),
      );

      // Draw word predictions below
      if (hasPredictions) {
        _drawWordPredictions(canvas, center, predictions);
      }
    } else {
      // Instruction text - more prominent
      final instructionPainter = TextPainter(
        text: TextSpan(
          text: 'Tap a letter',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      instructionPainter.layout();
      instructionPainter.paint(
        canvas,
        Offset(
          center.dx - instructionPainter.width / 2,
          center.dy - instructionPainter.height / 2,
        ),
      );
    }
  }

  void _drawWordPredictions(Canvas canvas, Offset center, List<Word> predictions) {
    final config = controller.config;
    final selectedIndex = controller.selectedPredictionIndex;

    // Draw predictions in a row below the typed string
    final predictionsY = center.dy + config.centerHubRadius * 0.15;
    final maxWidth = config.centerHubRadius * 1.6;
    final itemWidth = maxWidth / min(predictions.length, 4);

    for (var i = 0; i < min(predictions.length, 4); i++) {
      final prediction = predictions[i];
      final isSelected = i == selectedIndex;

      // Calculate x position (centered)
      final totalWidth = itemWidth * min(predictions.length, 4);
      final startX = center.dx - totalWidth / 2;
      final x = startX + itemWidth * i + itemWidth / 2;

      // Draw prediction chip
      final chipCenter = Offset(x, predictionsY);

      // Background
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: chipCenter, width: itemWidth - 4, height: 24),
          const Radius.circular(12),
        ),
        Paint()
          ..color = isSelected ? Colors.green : Colors.green[100]!
          ..style = PaintingStyle.fill,
      );

      // Border
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: chipCenter, width: itemWidth - 4, height: 24),
          const Radius.circular(12),
        ),
        Paint()
          ..color = Colors.green[700]!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      // Text
      final textStyle = TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : Colors.green[900],
      );

      final textPainter = TextPainter(
        text: TextSpan(text: prediction.text, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout(maxWidth: itemWidth - 8);
      textPainter.paint(
        canvas,
        Offset(
          chipCenter.dx - textPainter.width / 2,
          chipCenter.dy - textPainter.height / 2,
        ),
      );
    }

    // Draw "tap to complete" hint if has predictions
    if (predictions.isNotEmpty) {
      final hintPainter = TextPainter(
        text: TextSpan(
          text: 'tap to complete',
          style: TextStyle(
            fontSize: 8,
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      hintPainter.layout();
      hintPainter.paint(
        canvas,
        Offset(
          center.dx - hintPainter.width / 2,
          center.dy + config.centerHubRadius * 0.55,
        ),
      );
    }
  }

  double _calculateFontSize(int stringLength) {
    if (stringLength <= 3) return 24;
    if (stringLength <= 6) return 18;
    if (stringLength <= 10) return 14;
    return 11;
  }

  void _drawDragIndicator(Canvas canvas, Offset center, Offset dragPos) {
    // Line from center to drag position
    canvas.drawLine(
      center,
      dragPos,
      Paint()
        ..color = Colors.blue.withValues(alpha: 0.3)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Dot at drag position
    canvas.drawCircle(
      dragPos,
      6,
      Paint()..color = Colors.blue.withValues(alpha: 0.5),
    );
  }

  void _drawOutsideRimIndicator(Canvas canvas, Offset center) {
    // Draw pulsing red ring to indicate outside rim
    canvas.drawCircle(
      center,
      controller.config.letterRingRadius + controller.config.outsideRimThreshold,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Draw backspace icon hint
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Backspace',
        style: TextStyle(
          fontSize: 14,
          color: Colors.red[700],
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy + controller.config.letterRingRadius + 45,
      ),
    );
  }

  void _drawFloatingLabel(Canvas canvas, Offset fingerPos, String hoveredKey) {
    // Get neighboring keys for the magnifier
    final neighbors = _getNeighborKeys(hoveredKey);
    final leftKey = neighbors[0];
    final rightKey = neighbors[1];

    // Magnifier dimensions
    const keyWidth = 50.0;
    const keyHeight = 60.0;
    const spacing = 4.0;
    const totalWidth = keyWidth * 3 + spacing * 2;
    const totalHeight = keyHeight + 16;

    // Follow finger with offset away from hand
    // Right-handed: offset up and LEFT (hand comes from bottom-right)
    // Left-handed: offset up and RIGHT (hand comes from bottom-left)
    final wheelWidth = controller.config.centerX * 2;
    final wheelHeight = controller.config.centerY * 2;
    final halfWidth = (totalWidth + 16) / 2;
    final halfHeight = totalHeight / 2;

    final xOffset = isLeftHanded ? 100.0 : -100.0;
    var magnifierX = fingerPos.dx + xOffset;
    var magnifierY = fingerPos.dy - 80;  // above finger

    // Clamp to stay within bounds
    magnifierX = magnifierX.clamp(halfWidth, wheelWidth - halfWidth);
    magnifierY = magnifierY.clamp(halfHeight, wheelHeight - halfHeight);

    final magnifierCenter = Offset(magnifierX, magnifierY);

    // Draw shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: magnifierCenter.translate(0, 3),
          width: totalWidth + 16,
          height: keyHeight + 16,
        ),
        const Radius.circular(12),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Draw magnifier background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: magnifierCenter,
          width: totalWidth + 16,
          height: keyHeight + 16,
        ),
        const Radius.circular(12),
      ),
      Paint()
        ..color = Colors.grey[850]!
        ..style = PaintingStyle.fill,
    );

    // Draw border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: magnifierCenter,
          width: totalWidth + 16,
          height: keyHeight + 16,
        ),
        const Radius.circular(12),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Apply shift to display labels
    String displayKey(String? key) {
      if (key == null) return '';
      // Letters should be uppercase when shift is active
      if (isShiftActive && SpinnerKeyboardController.letters.contains(key)) {
        return key.toUpperCase();
      }
      // Default to lowercase for letters
      if (SpinnerKeyboardController.letters.contains(key)) {
        return key.toLowerCase();
      }
      return key;
    }

    // Draw left neighbor key
    if (leftKey != null) {
      _drawMagnifierKey(
        canvas,
        Offset(magnifierCenter.dx - keyWidth - spacing, magnifierCenter.dy),
        displayKey(leftKey),
        keyWidth,
        keyHeight,
        isCenter: false,
        isAnchor: controller.anchorKey == leftKey,
      );
    }

    // Draw center (hovered) key - larger with dwell progress
    _drawMagnifierKey(
      canvas,
      magnifierCenter,
      displayKey(hoveredKey),
      keyWidth,
      keyHeight,
      isCenter: true,
      isAnchor: controller.anchorKey == hoveredKey,
    );

    // Draw right neighbor key
    if (rightKey != null) {
      _drawMagnifierKey(
        canvas,
        Offset(magnifierCenter.dx + keyWidth + spacing, magnifierCenter.dy),
        displayKey(rightKey),
        keyWidth,
        keyHeight,
        isCenter: false,
        isAnchor: controller.anchorKey == rightKey,
      );
    }

    // Draw pointer triangle pointing down to finger
    final trianglePath = Path();
    trianglePath.moveTo(magnifierCenter.dx, magnifierCenter.dy + keyHeight / 2 + 12);
    trianglePath.lineTo(magnifierCenter.dx - 10, magnifierCenter.dy + keyHeight / 2 + 8);
    trianglePath.lineTo(magnifierCenter.dx + 10, magnifierCenter.dy + keyHeight / 2 + 8);
    trianglePath.close();

    canvas.drawPath(
      trianglePath,
      Paint()
        ..color = Colors.grey[850]!
        ..style = PaintingStyle.fill,
    );
  }

  /// Get the left and right neighbor keys based on current angles
  List<String?> _getNeighborKeys(String key) {
    final letters = SpinnerKeyboardController.letters;
    final numbers = SpinnerKeyboardController.numbers;
    final punctuation = SpinnerKeyboardController.punctuation;

    // Check if it's a letter
    if (letters.contains(key)) {
      final letterAngles = controller.letterAngles;
      final currentAngle = letterAngles[key] ?? 0;

      // Find neighbors by angle proximity
      String? leftNeighbor;
      String? rightNeighbor;
      double leftDiff = double.infinity;
      double rightDiff = double.infinity;

      for (final entry in letterAngles.entries) {
        if (entry.key == key) continue;

        var diff = entry.value - currentAngle;
        // Normalize to -pi to pi
        while (diff > pi) {
          diff -= 2 * pi;
        }
        while (diff < -pi) {
          diff += 2 * pi;
        }

        if (diff > 0 && diff < rightDiff) {
          rightDiff = diff;
          rightNeighbor = entry.key;
        } else if (diff < 0 && -diff < leftDiff) {
          leftDiff = -diff;
          leftNeighbor = entry.key;
        }
      }

      return [leftNeighbor, rightNeighbor];
    }

    // For numbers
    if (numbers.contains(key)) {
      final index = numbers.indexOf(key);
      final leftIndex = (index - 1 + numbers.length) % numbers.length;
      final rightIndex = (index + 1) % numbers.length;
      return [numbers[leftIndex], numbers[rightIndex]];
    }

    // For punctuation
    if (punctuation.contains(key)) {
      final index = punctuation.indexOf(key);
      final leftIndex = (index - 1 + punctuation.length) % punctuation.length;
      final rightIndex = (index + 1) % punctuation.length;
      return [punctuation[leftIndex], punctuation[rightIndex]];
    }

    return [null, null];
  }

  /// Draw a single key in the magnifier
  void _drawMagnifierKey(
    Canvas canvas,
    Offset center,
    String label,
    double width,
    double height, {
    required bool isCenter,
    required bool isAnchor,
  }) {
    final scale = isCenter ? 1.0 : 0.8;
    final scaledWidth = width * scale;
    final scaledHeight = height * scale;

    // Background color
    Color bgColor;
    if (isCenter) {
      // Show dwell progress in center key
      bgColor = Color.lerp(
        Colors.blue.withValues(alpha: 0.4),
        Colors.blue,
        dwellProgress,
      )!;
    } else if (isAnchor) {
      bgColor = Colors.orange.withValues(alpha: 0.8);
    } else {
      bgColor = Colors.grey[700]!;
    }

    // Draw key background
    final keyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: scaledWidth, height: scaledHeight),
      const Radius.circular(8),
    );

    canvas.drawRRect(
      keyRect,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.fill,
    );

    // Border - show dwell progress with thicker border
    final borderWidth = isCenter ? (2.0 + dwellProgress * 2.0) : 1.0;
    canvas.drawRRect(
      keyRect,
      Paint()
        ..color = isCenter ? Colors.white : Colors.grey[500]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // Draw dwell progress arc at bottom of center key
    if (isCenter && dwellProgress > 0) {
      final progressWidth = scaledWidth * 0.8 * dwellProgress;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(center.dx, center.dy + scaledHeight / 2 - 6),
            width: progressWidth,
            height: 4,
          ),
          const Radius.circular(2),
        ),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
    }

    // Text
    final fontSize = isCenter ? 28.0 : 20.0;
    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: isCenter ? FontWeight.bold : FontWeight.normal,
      color: Colors.white,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2 - (isCenter && dwellProgress > 0 ? 4 : 0),
      ),
    );
  }

  @override
  bool shouldRepaint(SpinnerKeyboardPainter oldDelegate) {
    return oldDelegate.controller.state != controller.state ||
        oldDelegate.controller.hoveredKey != controller.hoveredKey ||
        oldDelegate.controller.anchorKey != controller.anchorKey ||
        oldDelegate.controller.builtString != controller.builtString ||
        oldDelegate.controller.dragPosition != controller.dragPosition ||
        oldDelegate.controller.isOutsideRim != controller.isOutsideRim ||
        oldDelegate.controller.wordPredictions.length != controller.wordPredictions.length ||
        oldDelegate.controller.selectedPredictionIndex != controller.selectedPredictionIndex ||
        oldDelegate.isHolding != isHolding ||
        oldDelegate.dwellProgress != dwellProgress ||
        oldDelegate.isLeftHanded != isLeftHanded ||
        oldDelegate.isShiftActive != isShiftActive;
  }
}
