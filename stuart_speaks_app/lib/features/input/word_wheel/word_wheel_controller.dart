import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/models/word.dart';
import 'word_wheel_config.dart';

/// Single source of truth for word wheel state
class WordWheelController extends ChangeNotifier {
  // State
  WheelState _state = WheelState.hidden;
  List<Word> _words = [];
  Word? _hoveredWord;
  Offset? _dragPosition;
  bool _isExpanded = false;

  // Configuration
  final WordWheelConfig config;

  // Callbacks
  void Function(Word)? onWordSelected;
  VoidCallback? onActivated;
  VoidCallback? onHidden;

  WordWheelController({
    required this.config,
    List<Word>? words,
  }) : _words = words ?? [];

  // Getters
  WheelState get state => _state;
  bool get isActive => _state != WheelState.hidden;
  bool get isVisible =>
      _state == WheelState.visible || _state == WheelState.dragging;
  bool get isExpanded => _isExpanded;
  List<Word> get visibleWords =>
      _isExpanded ? _words.take(12).toList() : _words.take(4).toList();
  Word? get hoveredWord => _hoveredWord;
  Offset? get dragPosition => _dragPosition;

  // Actions
  void activate(Offset position) {
    _state = WheelState.activating;
    _dragPosition = position;
    notifyListeners();
    onActivated?.call();
  }

  void show() {
    _state = WheelState.visible;
    notifyListeners();
  }

  void updateDrag(Offset position) {
    if (_state == WheelState.activating || _state == WheelState.visible) {
      _state = WheelState.dragging;
    }

    _dragPosition = position;
    _hoveredWord = _calculateHoveredWord(position);
    _checkExpandCollapse(position);
    notifyListeners();
  }

  void release() {
    final selectedWord = _hoveredWord;
    hide();
    if (selectedWord != null) {
      onWordSelected?.call(selectedWord);
    }
  }

  void hide() {
    _state = WheelState.hidden;
    _hoveredWord = null;
    _dragPosition = null;
    _isExpanded = false;
    notifyListeners();
    onHidden?.call();
  }

  void updateWords(List<Word> words) {
    _words = words;
    // Recalculate hovered word if dragging
    if (_dragPosition != null) {
      _hoveredWord = _calculateHoveredWord(_dragPosition!);
    }
    notifyListeners();
  }

  // Private helper methods

  Word? _calculateHoveredWord(Offset dragPos) {
    final center = Offset(config.centerX, config.centerY);
    final dragVector = dragPos - center;
    final angle = atan2(dragVector.dy, dragVector.dx);

    // Calculate elliptical distance (normalized)
    final dx = dragVector.dx;
    final dy = dragVector.dy;
    final radiusX = config.outerRingDistance;
    final radiusY = config.outerRingDistanceY;
    final ellipticalDistance = sqrt((dx * dx) / (radiusX * radiusX) + (dy * dy) / (radiusY * radiusY)) * radiusX;

    // Ignore if in dead zone
    if (ellipticalDistance < config.deadZoneRadius) return null;

    final visible = visibleWords;
    if (visible.isEmpty) return null;

    // Find closest word by angle
    Word? closestWord;
    double smallestAngleDiff = double.infinity;

    for (var i = 0; i < visible.length; i++) {
      final wordAngle = _getWordAngle(i, visible.length);
      var angleDiff = (angle - wordAngle).abs();

      // Normalize angle difference to handle wrap-around (-180/180 boundary)
      if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;

      // Check if in correct ring when expanded
      final isInnerRing = i < 4;
      bool inCorrectRing = true;

      if (_isExpanded) {
        final innerBoundary = config.innerRingDistance + 40; // 140 in original
        final outerBoundary = config.outerRingDistance + 40; // 220 in original

        if (isInnerRing) {
          inCorrectRing = ellipticalDistance < innerBoundary;
        } else {
          inCorrectRing = ellipticalDistance >= innerBoundary && ellipticalDistance < outerBoundary;
        }
      }

      // Track closest word in correct ring
      if (inCorrectRing && angleDiff < smallestAngleDiff) {
        smallestAngleDiff = angleDiff;
        closestWord = visible[i];
      }
    }

    return closestWord;
  }

  void _checkExpandCollapse(Offset position) {
    final center = Offset(config.centerX, config.centerY);
    final dragVector = position - center;

    // Calculate elliptical distance for expand/collapse
    final dx = dragVector.dx;
    final dy = dragVector.dy;
    final radiusX = config.outerRingDistance;
    final radiusY = config.outerRingDistanceY;
    final ellipticalDistance = sqrt((dx * dx) / (radiusX * radiusX) + (dy * dy) / (radiusY * radiusY)) * radiusX;

    final expandThreshold = config.innerRingDistance + 50; // ~150 in original
    final collapseThreshold = 80.0;

    if (ellipticalDistance > expandThreshold && !_isExpanded && _words.length > 4) {
      _isExpanded = true;
    } else if (ellipticalDistance < collapseThreshold && _isExpanded) {
      _isExpanded = false;
    }
  }

  double _getWordAngle(int index, int totalWords) {
    final isInnerRing = index < 4;
    final ringIndex = isInnerRing ? index : index - 4;
    final ringSize = isInnerRing ? min(4, totalWords) : min(8, totalWords - 4);

    final angleOffset = -pi / 2; // Start at top
    return angleOffset + (2 * pi / ringSize) * ringIndex;
  }

  @override
  void dispose() {
    onWordSelected = null;
    onActivated = null;
    onHidden = null;
    super.dispose();
  }
}

/// State machine for word wheel
enum WheelState {
  hidden, // Not visible, not capturing gestures on visual
  activating, // Long press detected, about to show
  visible, // Visible, waiting for interaction
  dragging, // User is dragging to select word
}
