import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/models/word.dart';
import '../../../core/services/word_usage_tracker.dart';
import 'letter_bigram_service.dart';
import 'spinner_keyboard_config.dart';

/// Single source of truth for spinner keyboard state
class SpinnerKeyboardController extends ChangeNotifier {
  // Configuration
  final SpinnerKeyboardConfig config;

  // Word usage tracker for word predictions (optional, injected)
  WordUsageTracker? _wordTracker;

  // Bigram service for predictive reordering
  final LetterBigramService _bigramService = LetterBigramService();

  // State
  SpinnerState _state = SpinnerState.hidden;
  String _builtString = '';
  String? _hoveredKey;
  String? _anchorKey; // The key that stays fixed during reordering
  Offset? _dragPosition;
  bool _isOutsideRim = false;
  DateTime? _outsideRimStartTime; // For detecting pause outside rim
  String? _previousKey; // For tracking letter transitions

  // Dwell selection state
  DateTime? _hoverStartTime; // When current key hover started
  static const Duration _dwellDuration = Duration(milliseconds: 600); // Time to pause before selection (AAC recommended)

  // Gesture timing constants
  static const int _backspaceDelayMs = 350; // Pause outside rim to trigger backspace
  static const int _doubleLetterWindowMs = 450; // Swipe out and back within this window for double letter
  static const double _hysteresisBuffer = 10.0; // Dead zone for rim boundary to prevent jitter

  // Word predictions
  List<Word> _wordPredictions = [];
  int _selectedPredictionIndex = -1; // -1 = none selected

  // Letter positions (angle in radians for each letter)
  Map<String, double> _letterAngles = {};

  // Static key sets - letters ordered by frequency (most common at top)
  static const letters = 'ETAOINSHRDLCUMWFGYPBVKJXQZ';
  static const numbers = '0123456789';
  static const punctuation = '.,?!\'"()-:;';

  // Callbacks
  void Function(String)? onStringCompleted;
  void Function(String)? onKeySelected;
  void Function(String)? onWordPredictionSelected; // When a prediction is tapped
  VoidCallback? onActivated;
  VoidCallback? onHidden;

  SpinnerKeyboardController({required this.config}) {
    _initializeLetterPositions();
  }

  /// Initialize the controller with optional word tracker
  Future<void> initialize({WordUsageTracker? wordTracker}) async {
    _wordTracker = wordTracker;
    await _initializeBigramService();
  }

  Future<void> _initializeBigramService() async {
    await _bigramService.initialize();
  }

  /// Set word tracker for predictions (can be set after construction)
  void setWordTracker(WordUsageTracker tracker) {
    _wordTracker = tracker;
  }

  // Getters for word predictions
  List<Word> get wordPredictions => List.unmodifiable(_wordPredictions);
  int get selectedPredictionIndex => _selectedPredictionIndex;
  bool get hasPredictions => _wordPredictions.isNotEmpty;

  /// Update word predictions based on current built string
  void _updateWordPredictions() {
    if (_wordTracker == null || _builtString.isEmpty) {
      _wordPredictions = [];
      _selectedPredictionIndex = -1;
      return;
    }

    // Get word suggestions matching the current prefix
    _wordPredictions = _wordTracker!.getSuggestions(
      _builtString,
      limit: 4, // Show up to 4 predictions in center
    );
    _selectedPredictionIndex = -1;
  }

  /// Select a word prediction by index
  void selectPrediction(int index) {
    if (index >= 0 && index < _wordPredictions.length) {
      final selectedWord = _wordPredictions[index];
      _builtString = selectedWord.text;
      _selectedPredictionIndex = index;
      // Update anchor to last letter of prediction for consistency
      if (selectedWord.text.isNotEmpty) {
        final lastChar = selectedWord.text[selectedWord.text.length - 1].toUpperCase();
        if (letters.contains(lastChar)) {
          _anchorKey = lastChar;
        }
      }
      onWordPredictionSelected?.call(selectedWord.text);
      notifyListeners();
    }
  }

  /// Check if a position is in the center hub (for tap detection)
  bool isInCenterHub(Offset position) {
    final center = Offset(config.centerX, config.centerY);
    final distance = (position - center).distance;
    return distance <= config.centerHubRadius;
  }

  /// Get prediction index at position (for tap selection)
  int? getPredictionIndexAtPosition(Offset position) {
    if (!isInCenterHub(position) || _wordPredictions.isEmpty) {
      return null;
    }

    final center = Offset(config.centerX, config.centerY);
    final relative = position - center;

    // Divide center into quadrants for up to 4 predictions
    // Top, Right, Bottom, Left order
    if (_wordPredictions.length == 1) {
      return 0; // Only one prediction, any tap selects it
    }

    final angle = atan2(relative.dy, relative.dx);
    final normalizedAngle = (angle + pi) / (2 * pi); // 0 to 1

    // Map angle to prediction index
    final index = (normalizedAngle * _wordPredictions.length).floor() % _wordPredictions.length;
    return index;
  }

  // Initialize letters in frequency order around the ring (most common at top)
  // Uses alternating left/right pattern so common letters cluster at top
  void _initializeLetterPositions() {
    _letterAngles = {};
    final angleStep = 2 * pi / letters.length;

    for (var i = 0; i < letters.length; i++) {
      final letter = letters[i];

      if (i == 0) {
        // First letter (E) at top
        _letterAngles[letter] = -pi / 2;
      } else {
        // Alternate left and right from top
        final offset = (i + 1) ~/ 2; // 1, 1, 2, 2, 3, 3, ...
        final direction = i.isOdd ? -1 : 1; // Odd index = left (counter-clockwise), even = right (clockwise)
        _letterAngles[letter] = -pi / 2 + (angleStep * offset * direction);
      }
    }
  }

  // Getters
  SpinnerState get state => _state;
  bool get isActive => _state != SpinnerState.hidden;
  bool get isVisible =>
      _state == SpinnerState.visible || _state == SpinnerState.dragging;
  String get builtString => _builtString;
  String? get hoveredKey => _hoveredKey;
  String? get anchorKey => _anchorKey;
  Offset? get dragPosition => _dragPosition;
  bool get isOutsideRim => _isOutsideRim;
  Map<String, double> get letterAngles => Map.unmodifiable(_letterAngles);

  // Get angle for a specific letter
  double getLetterAngle(String letter) {
    return _letterAngles[letter.toUpperCase()] ?? 0;
  }

  // Get position for a letter on the ring
  Offset getLetterPosition(String letter) {
    final angle = getLetterAngle(letter);
    return Offset(
      config.centerX + config.letterRingRadius * cos(angle),
      config.centerY + config.letterRingRadius * sin(angle),
    );
  }

  // Get position for a number on the ring
  Offset getNumberPosition(int index) {
    final angle = -pi / 2 + (2 * pi / numbers.length) * index;
    return Offset(
      config.centerX + config.numberRingRadius * cos(angle),
      config.centerY + config.numberRingRadius * sin(angle),
    );
  }

  // Get position for punctuation on the ring
  Offset getPunctuationPosition(int index) {
    final angle = -pi / 2 + (2 * pi / punctuation.length) * index;
    return Offset(
      config.centerX + config.punctuationRingRadius * cos(angle),
      config.centerY + config.punctuationRingRadius * sin(angle),
    );
  }

  // Actions
  void activate(Offset position) {
    _state = SpinnerState.activating;
    _dragPosition = position;
    _builtString = '';
    _anchorKey = null;
    _previousKey = null;
    notifyListeners();
    onActivated?.call();
  }

  void show() {
    _state = SpinnerState.visible;
    notifyListeners();
  }

  void updateDrag(Offset position) {
    if (_state == SpinnerState.activating || _state == SpinnerState.visible) {
      _state = SpinnerState.dragging;
    }

    _dragPosition = position;

    // Check if outside rim with hysteresis to prevent jitter
    final wasOutsideRim = _isOutsideRim;
    // Use hysteresis: require coming back further inside to re-enter
    if (_isOutsideRim) {
      // Must come back inside by buffer amount to re-enter
      _isOutsideRim = config.isOutsideRimWithHysteresis(position, _hysteresisBuffer);
    } else {
      _isOutsideRim = config.isOutsideRim(position);
    }

    if (_isOutsideRim) {
      if (!wasOutsideRim) {
        // Just went outside - start timer
        _outsideRimStartTime = DateTime.now();
      }
      _hoveredKey = null;
      _hoverStartTime = null; // Reset dwell timer
    } else {
      if (wasOutsideRim && _outsideRimStartTime != null) {
        // Coming back inside after being outside
        final duration = DateTime.now().difference(_outsideRimStartTime!);
        if (duration.inMilliseconds < _doubleLetterWindowMs) {
          // Quick swipe out and back = double letter
          _doubleLetter();
        }
        // If longer pause, backspace was already handled in checkBackspace
      }
      _outsideRimStartTime = null;

      final previousHovered = _hoveredKey;
      _hoveredKey = _calculateHoveredKey(position);

      // Track dwell time - only start timer when entering a NEW key
      if (_hoveredKey != previousHovered) {
        if (_hoveredKey != null) {
          // Entered a new key - start dwell timer
          _hoverStartTime = DateTime.now();
        } else {
          // Left all keys
          _hoverStartTime = null;
        }
      }
      // Note: selection happens via checkDwellSelection() called from widget timer
    }

    notifyListeners();
  }

  /// Check if dwell selection should trigger (called from timer in widget)
  /// Returns true if a key was selected
  bool checkDwellSelection() {
    if (_hoveredKey != null && _hoverStartTime != null) {
      final duration = DateTime.now().difference(_hoverStartTime!);
      if (duration >= _dwellDuration) {
        // Dwell time reached - select the key
        selectKey(_hoveredKey!);
        _hoverStartTime = null; // Reset so we don't re-select
        return true;
      }
    }
    return false;
  }

  /// Get dwell progress (0.0 to 1.0) for visual feedback
  double get dwellProgress {
    if (_hoveredKey == null || _hoverStartTime == null) {
      return 0.0;
    }
    final elapsed = DateTime.now().difference(_hoverStartTime!);
    return (elapsed.inMilliseconds / _dwellDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Select a key and add it to the string
  void selectKey(String key) {
    // Record transition for learning (if this is a letter following another)
    if (_previousKey != null &&
        letters.contains(key.toUpperCase()) &&
        letters.contains(_previousKey!.toUpperCase())) {
      _bigramService.recordTransition(_previousKey!, key);
    }

    _builtString += key;
    _anchorKey = key;
    _previousKey = key;
    onKeySelected?.call(key);

    // Update word predictions based on new string
    _updateWordPredictions();
    notifyListeners();
  }

  /// Check if we should trigger backspace (called from timer in widget)
  bool checkBackspace() {
    if (_isOutsideRim && _outsideRimStartTime != null) {
      final duration = DateTime.now().difference(_outsideRimStartTime!);
      if (duration.inMilliseconds >= _backspaceDelayMs) {
        // Pause outside rim = backspace
        backspace();
        _outsideRimStartTime = DateTime.now(); // Reset for continuous backspace
        return true;
      }
    }
    return false;
  }

  /// Get backspace progress (0.0 to 1.0) for visual feedback
  double get backspaceProgress {
    if (!_isOutsideRim || _outsideRimStartTime == null) {
      return 0.0;
    }
    final elapsed = DateTime.now().difference(_outsideRimStartTime!);
    return (elapsed.inMilliseconds / _backspaceDelayMs).clamp(0.0, 1.0);
  }

  /// Remove last character from built string
  void backspace() {
    if (_builtString.isNotEmpty) {
      _builtString = _builtString.substring(0, _builtString.length - 1);
      // Reset anchor to last character, or null if empty
      _anchorKey = _builtString.isNotEmpty ? _builtString[_builtString.length - 1] : null;
      // Reset prediction selection
      _selectedPredictionIndex = -1;
      // Update word predictions
      _updateWordPredictions();
      notifyListeners();
    }
  }

  void _doubleLetter() {
    if (_builtString.isNotEmpty) {
      final lastChar = _builtString[_builtString.length - 1];
      _builtString += lastChar;
      onKeySelected?.call(lastChar);
      _updateWordPredictions();
      notifyListeners();
    }
  }

  void release() {
    final completedString = _builtString;
    hide();
    if (completedString.isNotEmpty) {
      onStringCompleted?.call(completedString);
    }
  }

  void hide() {
    _state = SpinnerState.hidden;
    _hoveredKey = null;
    _dragPosition = null;
    _isOutsideRim = false;
    _outsideRimStartTime = null;
    _hoverStartTime = null;
    notifyListeners();
    onHidden?.call();
  }

  void clearString() {
    _builtString = '';
    _anchorKey = null;
    notifyListeners();
  }

  // Calculate which key is under the finger
  String? _calculateHoveredKey(Offset dragPos) {
    final center = Offset(config.centerX, config.centerY);
    final dragVector = dragPos - center;
    final angle = atan2(dragVector.dy, dragVector.dx);

    final ring = config.getRingAtPosition(dragPos);
    if (ring == null) return null;

    switch (ring) {
      case SpinnerRing.center:
        return null; // Center is for predictions, not key selection

      case SpinnerRing.letters:
        return _findClosestLetter(angle);

      case SpinnerRing.numbers:
        return _findClosestNumber(angle);

      case SpinnerRing.punctuation:
        return _findClosestPunctuation(angle);
    }
  }

  String? _findClosestLetter(double targetAngle) {
    String? closest;
    double smallestDiff = double.infinity;

    for (final entry in _letterAngles.entries) {
      var diff = (targetAngle - entry.value).abs();
      if (diff > pi) diff = 2 * pi - diff;

      if (diff < smallestDiff) {
        smallestDiff = diff;
        closest = entry.key;
      }
    }

    return closest;
  }

  String? _findClosestNumber(double targetAngle) {
    int? closestIndex;
    double smallestDiff = double.infinity;

    for (var i = 0; i < numbers.length; i++) {
      final angle = -pi / 2 + (2 * pi / numbers.length) * i;
      var diff = (targetAngle - angle).abs();
      if (diff > pi) diff = 2 * pi - diff;

      if (diff < smallestDiff) {
        smallestDiff = diff;
        closestIndex = i;
      }
    }

    return closestIndex != null ? numbers[closestIndex] : null;
  }

  String? _findClosestPunctuation(double targetAngle) {
    int? closestIndex;
    double smallestDiff = double.infinity;

    for (var i = 0; i < punctuation.length; i++) {
      final angle = -pi / 2 + (2 * pi / punctuation.length) * i;
      var diff = (targetAngle - angle).abs();
      if (diff > pi) diff = 2 * pi - diff;

      if (diff < smallestDiff) {
        smallestDiff = diff;
        closestIndex = i;
      }
    }

    return closestIndex != null ? punctuation[closestIndex] : null;
  }

  @override
  void dispose() {
    onStringCompleted = null;
    onKeySelected = null;
    onActivated = null;
    onHidden = null;
    super.dispose();
  }
}

/// State machine for spinner keyboard
enum SpinnerState {
  hidden, // Not visible
  activating, // Long press detected, about to show
  visible, // Visible, waiting for interaction
  dragging, // User is dragging to select keys
}
