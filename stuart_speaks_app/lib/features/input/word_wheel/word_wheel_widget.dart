import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/word.dart';
import '../../../core/models/wheel_position.dart';

/// Accessible word wheel with multiple input modes:
/// 1. Direct tap - tap word directly
/// 2. Tap-hold-spin - hold center and drag to word
/// 3. Expandable - swipe out for more words
class WordWheelWidget extends StatefulWidget {
  final List<Word> words;
  final Function(Word) onWordSelected;
  final bool showEmpty; // Show empty state or wheel
  final VoidCallback? onTapHoldStart; // Trigger for sentence starters
  final VoidCallback? onWheelShown; // Callback when wheel becomes visible
  final VoidCallback? onWheelHidden; // Callback when wheel is hidden
  final VoidCallback? onTapWhenHidden; // Callback when tapped while hidden

  const WordWheelWidget({
    super.key,
    required this.words,
    required this.onWordSelected,
    this.showEmpty = false,
    this.onTapHoldStart,
    this.onWheelShown,
    this.onWheelHidden,
    this.onTapWhenHidden,
  });

  @override
  State<WordWheelWidget> createState() => _WordWheelWidgetState();
}

class _WordWheelWidgetState extends State<WordWheelWidget> {
  bool _isHolding = false;
  bool _isExpanded = false;
  bool _isVisible = false;
  Word? _hoveredWord;
  Offset? _dragPosition;
  Timer? _holdTimer;

  static const double _centerX = 200.0;
  static const double _centerY = 200.0;
  static const double _innerRingDistance = 100.0;
  static const double _outerRingDistance = 180.0;
  static const double _deadZoneRadius = 30.0;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use single gesture detector for both states to maintain gesture continuity
    // When hidden: translucent allows taps through to TextField while still detecting long press
    // When visible: opaque captures all gestures
    return SizedBox(
      width: 400,
      height: 400,
      child: GestureDetector(
        behavior: _isVisible ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onDragUpdate,
        onLongPressEnd: _onDragEnd,
        child: Visibility(
          visible: _isVisible || _isHolding,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: widget.showEmpty && widget.words.isEmpty
              ? _buildEmptyStateDisplay()
              : CustomPaint(
                  painter: WheelPainter(
                    words: _getVisibleWords(),
                    isExpanded: _isExpanded,
                    hoveredWord: _hoveredWord,
                    dragPosition: _dragPosition,
                    isHolding: _isHolding,
                  ),
                  size: const Size(400, 400),
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateDisplay() {
    return Container(
      width: 400,
      height: 400,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.transparent, // Transparent to show parent disc
        borderRadius: BorderRadius.circular(200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Tap & hold to start',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<Word> _getVisibleWords() {
    if (_isExpanded) {
      return widget.words.take(12).toList();
    } else {
      return widget.words.take(4).toList();
    }
  }

  void _onTapDown(TapDownDetails details) {
    // Start timer for hold detection
    _holdTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _isHolding = true;
      });
      HapticFeedback.mediumImpact();
      widget.onTapHoldStart?.call();
    });

    // Check for expand/collapse gesture
    final centerDistance = _distanceFromCenter(details.localPosition);
    if (centerDistance < 50) {
      // User tapped near center - could be expand gesture
      // We'll handle this on drag
    }
  }

  void _onTapUp(TapUpDetails details) {
    _holdTimer?.cancel();

    if (!_isHolding) {
      // If wheel is not visible, notify parent to show keyboard
      if (!_isVisible) {
        widget.onTapWhenHidden?.call();
      } else {
        // Direct tap - select word at position
        final tappedWord = _getWordAtPosition(details.localPosition);
        if (tappedWord != null) {
          HapticFeedback.mediumImpact();
          widget.onWordSelected(tappedWord);
        }
      }
    }

    setState(() {
      _isHolding = false;
      _hoveredWord = null;
      _dragPosition = null;
    });
  }

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isHolding = true;
      _isVisible = true;
      _dragPosition = details.localPosition;
    });
    HapticFeedback.mediumImpact();

    // Notify parent that wheel is shown
    widget.onWheelShown?.call();

    // Trigger callback to load words if in empty state
    if (widget.showEmpty || widget.words.isEmpty) {
      widget.onTapHoldStart?.call();
    }
  }

  void _onDragUpdate(LongPressMoveUpdateDetails details) {
    if (!_isHolding) return;

    final newHoveredWord = _getWordInDirection(details.localPosition);
    final centerDistance = _distanceFromCenter(details.localPosition);

    setState(() {
      _dragPosition = details.localPosition;

      // Check for expand/collapse gesture
      if (centerDistance > 150 && !_isExpanded && widget.words.length > 4) {
        _isExpanded = true;
        HapticFeedback.lightImpact();
      } else if (centerDistance < 80 && _isExpanded) {
        _isExpanded = false;
        HapticFeedback.lightImpact();
      }

      // Haptic feedback when hovering changes
      if (newHoveredWord != _hoveredWord && newHoveredWord != null) {
        HapticFeedback.selectionClick();
        _hoveredWord = newHoveredWord;
      }
    });
  }

  void _onDragEnd(LongPressEndDetails details) {
    if (_hoveredWord != null) {
      HapticFeedback.mediumImpact();
      widget.onWordSelected(_hoveredWord!);
    }

    setState(() {
      _isHolding = false;
      _hoveredWord = null;
      _dragPosition = null;
      _isVisible = false;
    });

    // Notify parent that wheel is hidden
    widget.onWheelHidden?.call();
  }

  Word? _getWordInDirection(Offset dragPos) {
    final center = const Offset(_centerX, _centerY);
    final dragVector = dragPos - center;
    final angle = atan2(dragVector.dy, dragVector.dx);
    final distance = dragVector.distance;

    // Ignore if in dead zone
    if (distance < _deadZoneRadius) return null;

    final visibleWords = _getVisibleWords();
    if (visibleWords.isEmpty) return null;

    // Find closest word by angle
    Word? closestWord;
    double smallestAngleDiff = double.infinity;

    for (var i = 0; i < visibleWords.length; i++) {
      final wordAngle = _getWordAngle(i, visibleWords.length);
      var angleDiff = (angle - wordAngle).abs();

      // Normalize angle difference to handle wrap-around (-180/180 boundary)
      if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;

      // Check if in correct ring when expanded
      final isInnerRing = i < 4;
      bool inCorrectRing = true;

      if (_isExpanded) {
        if (isInnerRing) {
          inCorrectRing = distance < 140;
        } else {
          inCorrectRing = distance >= 140 && distance < 220;
        }
      }

      // Track closest word in correct ring
      if (inCorrectRing && angleDiff < smallestAngleDiff) {
        smallestAngleDiff = angleDiff;
        closestWord = visibleWords[i];
      }
    }

    return closestWord;
  }

  double _distanceFromCenter(Offset position) {
    final center = const Offset(_centerX, _centerY);
    return (position - center).distance;
  }

  Word? _getWordAtPosition(Offset position) {
    final visibleWords = _getVisibleWords();

    for (var i = 0; i < visibleWords.length; i++) {
      final wordPos = _calculateWordPosition(i, visibleWords.length);
      final distance = (position - wordPos.offset).distance;

      final buttonRadius = _getButtonSize(i) / 2;
      if (distance < buttonRadius) {
        return visibleWords[i];
      }
    }
    return null;
  }

  WheelPosition _calculateWordPosition(int index, int totalWords) {
    final isInnerRing = index < 4;
    final ringIndex = isInnerRing ? index : index - 4;
    final ringSize = isInnerRing ? 4 : 8;

    final angleOffset = -pi / 2; // Start at top
    final angle = angleOffset + (2 * pi / ringSize) * ringIndex;

    final distance = isInnerRing ? _innerRingDistance : _outerRingDistance;

    final x = _centerX + (distance * cos(angle));
    final y = _centerY + (distance * sin(angle));

    return WheelPosition(
      offset: Offset(x, y),
      angle: angle,
      distance: distance,
      isInnerRing: isInnerRing,
      word: _getVisibleWords()[index],
    );
  }

  double _getWordAngle(int index, int totalWords) {
    final isInnerRing = index < 4;
    final ringIndex = isInnerRing ? index : index - 4;
    final ringSize = isInnerRing ? min(4, totalWords) : min(8, totalWords - 4);

    final angleOffset = -pi / 2;
    return angleOffset + (2 * pi / ringSize) * ringIndex;
  }

  double _getButtonSize(int index) {
    return 80.0 - (index * 4.0).clamp(0.0, 25.0);
  }
}

/// Custom painter for the word wheel
class WheelPainter extends CustomPainter {
  final List<Word> words;
  final bool isExpanded;
  final Word? hoveredWord;
  final Offset? dragPosition;
  final bool isHolding;

  static const double centerX = 200.0;
  static const double centerY = 200.0;
  static const double innerRingDistance = 100.0;
  static const double outerRingDistance = 180.0;

  const WheelPainter({
    required this.words,
    required this.isExpanded,
    required this.hoveredWord,
    required this.dragPosition,
    required this.isHolding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = const Offset(centerX, centerY);

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
      const Offset(centerX, centerY),
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

    final distance = isInnerRing ? innerRingDistance : outerRingDistance;

    final x = centerX + (distance * cos(angle));
    final y = centerY + (distance * sin(angle));

    return WheelPosition(
      offset: Offset(x, y),
      angle: angle,
      distance: distance,
      isInnerRing: isInnerRing,
      word: words[index],
    );
  }

  @override
  bool shouldRepaint(WheelPainter oldDelegate) {
    return oldDelegate.isExpanded != isExpanded ||
        oldDelegate.hoveredWord != hoveredWord ||
        oldDelegate.dragPosition != dragPosition ||
        oldDelegate.isHolding != isHolding ||
        oldDelegate.words.length != words.length;
  }
}
