# Word Wheel Complete Redesign

## Executive Summary

The current word wheel implementation has fundamental architectural flaws that make it fragile and unreliable, particularly on iOS. This document outlines a complete redesign with a robust, testable architecture.

## Current Architecture Problems

### 1. Gesture Detection Issues

**Problem**: The `GestureDetector` is wrapped inside a `Visibility` widget that collapses to zero size when hidden.

```dart
// CURRENT BROKEN APPROACH
return GestureDetector(
  behavior: _isVisible ? HitTestBehavior.opaque : HitTestBehavior.translucent,
  onLongPressStart: _onLongPressStart,
  child: Visibility(
    visible: _isVisible || _isHolding,
    maintainSize: false, // ← PROBLEM: No size = no gesture detection
    child: CustomPaint(...),
  ),
);
```

**Why it fails**:
- When `visible: false` and `maintainSize: false`, the widget has no layout bounds
- Gesture detectors need layout bounds to capture events
- iOS text selection intercepts long-press before Flutter can capture it
- `HitTestBehavior.translucent` doesn't help with zero-size widgets

### 2. Multi-Layer Confusion

**Problem**: Gesture handling and visual rendering are tightly coupled.

```dart
Stack(
  children: [
    TextField(...), // Layer 1: Text input
    Positioned( // Layer 2: Word wheel overlay
      child: IgnorePointer( // ← Blocks gestures when suggestions show
        ignoring: _currentSuggestions.isNotEmpty && !_showWheel,
        child: WordWheelWidget(...),
      ),
    ),
  ],
)
```

**Issues**:
- `IgnorePointer` was preventing wheel activation entirely
- Z-ordering conflicts between text field and wheel
- Parent (tts_screen) and child (word_wheel) both manage visibility state
- State can desync

### 3. iOS-Specific Conflicts

**Problem**: iOS native text editing gestures conflict with custom gestures.

- Long-press on TextField → iOS shows magnifying glass and text selection
- TextField `enableInteractiveSelection` only partially helps
- Flutter's gesture arena doesn't always win against iOS native gestures

### 4. Fragile State Management

**Problem**: Multiple boolean flags lead to inconsistent states.

```dart
// Parent state (tts_screen.dart)
bool _showWheel = false;

// Child state (word_wheel_widget.dart)
bool _isVisible = false;
bool _isHolding = false;
```

Possible states:
- `_showWheel: true, _isVisible: false` → Inconsistent
- `_isHolding: true, _isVisible: false` → Wheel activating but not shown
- Timer in `_onTapDown` can fire after widget disposed

### 5. Hard-Coded Sizing

**Problem**: 400x400 pixel size doesn't adapt to device.

```dart
const Size(400, 400) // ← Fixed size
```

- Too large on iPhone SE
- Too small on iPad Pro
- Doesn't account for safe areas
- Can overflow stack bounds

---

## Proposed New Architecture

### Design Principles

1. **Separation of Concerns**: Decouple gesture capture, visual rendering, and state management
2. **Single Source of Truth**: One controller manages all wheel state
3. **Responsive**: Adapt to screen size and safe areas
4. **Testable**: Pure functions for calculations, mockable gesture handling
5. **iOS-Friendly**: Work with iOS gestures, not against them

### New Component Structure

```
WordWheelController (State Management)
├── GestureCaptureLayer (Always active, transparent)
│   └── RawGestureDetector with custom recognizers
├── WheelVisualLayer (Visual feedback only)
│   ├── WheelPainter (Draw wheel, words, indicators)
│   └── AnimatedOpacity (Smooth show/hide)
└── WordWheelModel (Pure data, calculations)
    ├── Position calculations
    ├── Angle calculations
    └── Hit detection
```

---

## Implementation Plan

### Phase 1: Core Controller

**File**: `lib/features/input/word_wheel/word_wheel_controller.dart`

```dart
/// Single source of truth for word wheel state
class WordWheelController extends ChangeNotifier {
  // State
  WheelState _state = WheelState.hidden;
  List<Word> _words = [];
  Word? _hoveredWord;
  Offset? _dragPosition;
  bool _isExpanded = false;

  // Configuration
  late final WordWheelConfig _config;

  // Getters
  WheelState get state => _state;
  bool get isActive => _state != WheelState.hidden;
  bool get isVisible => _state == WheelState.visible || _state == WheelState.dragging;
  List<Word> get visibleWords => _isExpanded ? _words.take(12).toList() : _words.take(4).toList();
  Word? get hoveredWord => _hoveredWord;

  // Actions
  void activate(Offset position) {
    _state = WheelState.activating;
    _dragPosition = position;
    notifyListeners();
  }

  void show() {
    _state = WheelState.visible;
    notifyListeners();
  }

  void updateDrag(Offset position) {
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
  }

  // Callbacks
  void Function(Word)? onWordSelected;
  VoidCallback? onActivated;
  VoidCallback? onHidden;

  @override
  void dispose() {
    super.dispose();
  }
}

enum WheelState {
  hidden,      // Not visible, not capturing gestures on visual
  activating,  // Long press detected, about to show
  visible,     // Visible, waiting for interaction
  dragging,    // User is dragging to select word
}
```

### Phase 2: Gesture Capture Layer

**File**: `lib/features/input/word_wheel/gesture_capture_layer.dart`

```dart
/// Always-active transparent layer that captures gestures
/// This layer ALWAYS has a size and can always capture gestures
class GestureCaptureLayer extends StatefulWidget {
  final WordWheelController controller;
  final Size wheelSize;

  const GestureCaptureLayer({
    required this.controller,
    required this.wheelSize,
  });

  @override
  State<GestureCaptureLayer> createState() => _GestureCaptureLayerState();
}

class _GestureCaptureLayerState extends State<GestureCaptureLayer> {
  late LongPressGestureRecognizer _longPressRecognizer;

  @override
  void initState() {
    super.initState();
    _longPressRecognizer = LongPressGestureRecognizer(
      duration: const Duration(milliseconds: 500),
    )
      ..onLongPressStart = _handleLongPressStart
      ..onLongPressMoveUpdate = _handleLongPressMoveUpdate
      ..onLongPressEnd = _handleLongPressEnd;
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    HapticFeedback.mediumImpact();
    widget.controller.activate(details.localPosition);

    // Small delay before showing to prevent accidental activations
    Future.delayed(const Duration(milliseconds: 100), () {
      if (widget.controller.state == WheelState.activating) {
        widget.controller.show();
      }
    });
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    widget.controller.updateDrag(details.localPosition);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    widget.controller.release();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.wheelSize.width,
      height: widget.wheelSize.height,
      child: RawGestureDetector(
        gestures: {
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => _longPressRecognizer,
            (instance) {}, // Already configured in initState
          ),
        },
        behavior: HitTestBehavior.translucent,
        child: Container(
          color: Colors.transparent, // Required for hit testing
        ),
      ),
    );
  }

  @override
  void dispose() {
    _longPressRecognizer.dispose();
    super.dispose();
  }
}
```

### Phase 3: Visual Layer

**File**: `lib/features/input/word_wheel/wheel_visual_layer.dart`

```dart
/// Visual representation of the wheel
/// This layer is IgnorePointer - all gestures handled by GestureCaptureLayer
class WheelVisualLayer extends StatelessWidget {
  final WordWheelController controller;
  final Size wheelSize;

  const WheelVisualLayer({
    required this.controller,
    required this.wheelSize,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return AnimatedOpacity(
          opacity: controller.isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            child: CustomPaint(
              painter: WheelPainter(
                words: controller.visibleWords,
                isExpanded: controller._isExpanded,
                hoveredWord: controller.hoveredWord,
                dragPosition: controller._dragPosition,
                config: controller._config,
              ),
              size: wheelSize,
            ),
          ),
        );
      },
    );
  }
}
```

### Phase 4: Main Widget

**File**: `lib/features/input/word_wheel/word_wheel_widget_v2.dart`

```dart
/// New word wheel implementation with clean separation of concerns
class WordWheelWidgetV2 extends StatefulWidget {
  final List<Word> words;
  final Function(Word) onWordSelected;
  final VoidCallback? onWheelShown;
  final VoidCallback? onWheelHidden;

  const WordWheelWidgetV2({
    super.key,
    required this.words,
    required this.onWordSelected,
    this.onWheelShown,
    this.onWheelHidden,
  });

  @override
  State<WordWheelWidgetV2> createState() => _WordWheelWidgetV2State();
}

class _WordWheelWidgetV2State extends State<WordWheelWidgetV2> {
  late WordWheelController _controller;
  late Size _wheelSize;

  @override
  void initState() {
    super.initState();

    // Calculate responsive size
    _wheelSize = _calculateWheelSize();

    _controller = WordWheelController(
      config: WordWheelConfig(
        centerX: _wheelSize.width / 2,
        centerY: _wheelSize.height / 2,
        innerRingDistance: _wheelSize.width * 0.25,
        outerRingDistance: _wheelSize.width * 0.45,
      ),
    )
      ..onWordSelected = widget.onWordSelected
      ..onActivated = widget.onWheelShown
      ..onHidden = widget.onWheelHidden;
  }

  Size _calculateWheelSize() {
    // Get screen size
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;

    // Adaptive sizing
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

  @override
  void didUpdateWidget(WordWheelWidgetV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.words != oldWidget.words) {
      _controller.updateWords(widget.words);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _wheelSize.width,
      height: _wheelSize.height,
      child: Stack(
        children: [
          // Layer 1: Always-active gesture capture (bottom)
          Positioned.fill(
            child: GestureCaptureLayer(
              controller: _controller,
              wheelSize: _wheelSize,
            ),
          ),

          // Layer 2: Visual wheel (top, only when active)
          Positioned.fill(
            child: WheelVisualLayer(
              controller: _controller,
              wheelSize: _wheelSize,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### Phase 5: Configuration Model

**File**: `lib/features/input/word_wheel/word_wheel_config.dart`

```dart
/// Configuration for word wheel sizing and layout
class WordWheelConfig {
  final double centerX;
  final double centerY;
  final double innerRingDistance;
  final double outerRingDistance;
  final double deadZoneRadius;
  final Duration activationDelay;
  final Duration hideAnimationDuration;

  const WordWheelConfig({
    required this.centerX,
    required this.centerY,
    required this.innerRingDistance,
    required this.outerRingDistance,
    this.deadZoneRadius = 30.0,
    this.activationDelay = const Duration(milliseconds: 500),
    this.hideAnimationDuration = const Duration(milliseconds: 200),
  });

  // Helper to create responsive config from screen size
  factory WordWheelConfig.responsive(Size screenSize) {
    final wheelSize = screenSize.shortestSide < 768
        ? Size(400, 400)
        : Size(500, 500);

    return WordWheelConfig(
      centerX: wheelSize.width / 2,
      centerY: wheelSize.height / 2,
      innerRingDistance: wheelSize.width * 0.25,
      outerRingDistance: wheelSize.width * 0.45,
    );
  }
}
```

---

## Integration with TTS Screen

### Current Integration (Problematic)

```dart
// tts_screen.dart - CURRENT
Stack(
  children: [
    TextField(...),
    Positioned(
      child: IgnorePointer( // ← Prevents activation
        ignoring: _currentSuggestions.isNotEmpty && !_showWheel,
        child: WordWheelWidget(...),
      ),
    ),
  ],
)
```

### New Integration (Clean)

```dart
// tts_screen.dart - NEW
Stack(
  children: [
    // Layer 1: Text input
    TextField(
      enableInteractiveSelection: false, // Disable iOS text selection
      ...
    ),

    // Layer 2: Word wheel (always captures gestures)
    Positioned(
      left: 0,
      right: 0,
      top: 40,
      child: Center(
        child: WordWheelWidgetV2(
          words: _currentSuggestions,
          onWordSelected: _onWordSelected,
          onWheelShown: () {
            FocusScope.of(context).unfocus();
            setState(() => _showWheel = true);
          },
          onWheelHidden: () {
            setState(() => _showWheel = false);
            _textFieldFocus.requestFocus();
          },
        ),
      ),
    ),

    // Layer 3: Word suggestions bar (only when wheel hidden)
    if (!_showWheel && _currentSuggestions.isNotEmpty)
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: SuggestionBar(...),
      ),
  ],
)
```

---

## Testing Strategy

### Unit Tests

```dart
// word_wheel_controller_test.dart
void main() {
  group('WordWheelController', () {
    test('starts in hidden state', () {
      final controller = WordWheelController();
      expect(controller.state, WheelState.hidden);
      expect(controller.isVisible, false);
    });

    test('activates on long press', () {
      final controller = WordWheelController();
      controller.activate(Offset(100, 100));
      expect(controller.state, WheelState.activating);
    });

    test('calculates hovered word correctly', () {
      final controller = WordWheelController(
        words: [Word(text: 'hello'), Word(text: 'world')],
      );
      controller.show();
      controller.updateDrag(Offset(200, 100)); // Top position
      expect(controller.hoveredWord?.text, 'hello');
    });

    test('expands when dragged far from center', () {
      final controller = WordWheelController(
        words: List.generate(12, (i) => Word(text: 'word$i')),
      );
      controller.show();
      controller.updateDrag(Offset(400, 200)); // Far from center
      expect(controller.isExpanded, true);
      expect(controller.visibleWords.length, 12);
    });
  });
}
```

### Widget Tests

```dart
// word_wheel_widget_test.dart
void main() {
  testWidgets('activates on long press', (tester) async {
    bool wheelShown = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordWheelWidgetV2(
            words: [Word(text: 'test')],
            onWordSelected: (_) {},
            onWheelShown: () => wheelShown = true,
          ),
        ),
      ),
    );

    // Long press in center
    await tester.longPress(find.byType(WordWheelWidgetV2));
    await tester.pump(Duration(milliseconds: 600));

    expect(wheelShown, true);
  });
}
```

### Integration Tests

```dart
// wheel_integration_test.dart
void main() {
  testWidgets('full word selection flow', (tester) async {
    Word? selectedWord;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordWheelWidgetV2(
            words: [
              Word(text: 'hello'),
              Word(text: 'world'),
            ],
            onWordSelected: (word) => selectedWord = word,
          ),
        ),
      ),
    );

    // 1. Long press to activate
    final wheelFinder = find.byType(WordWheelWidgetV2);
    await tester.longPress(wheelFinder);
    await tester.pump(Duration(milliseconds: 600));

    // 2. Drag to word position
    await tester.drag(wheelFinder, Offset(0, -100));
    await tester.pump();

    // 3. Release to select
    await tester.pumpAndSettle();

    expect(selectedWord?.text, 'hello');
  });
}
```

---

## Migration Strategy

### Phase 1: Parallel Implementation (1-2 days)
- Create new files alongside existing ones
- Suffix with `_v2` to distinguish
- No changes to existing code

### Phase 2: Testing & Refinement (1 day)
- Write unit tests for controller
- Write widget tests for gesture capture
- Test on both iPhone and iPad
- Test on iOS simulator and physical devices

### Phase 3: Gradual Migration (1 day)
- Add feature flag: `useNewWordWheel`
- Make it easy to switch between old and new
- Deploy to TestFlight for real-world testing

### Phase 4: Full Cutover (1 day)
- Remove old implementation
- Remove `_v2` suffixes
- Update documentation

---

## Benefits of New Architecture

1. **Reliability**: Gesture capture always works, even when wheel hidden
2. **Testability**: Controller is pure Dart, easy to unit test
3. **Maintainability**: Clear separation of concerns
4. **Responsiveness**: Adapts to screen size
5. **Performance**: No unnecessary rebuilds, proper use of `ChangeNotifier`
6. **iOS Compatibility**: Works with iOS gestures instead of fighting them
7. **Debuggability**: Single source of truth for state

---

## Potential Issues & Solutions

### Issue: iOS Still Intercepts Long Press

**Solution**: Use `excludeFromSemantics` and custom gesture recognizer with higher priority:

```dart
RawGestureDetector(
  gestures: {
    LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
      () => LongPressGestureRecognizer(
        duration: Duration(milliseconds: 400), // Slightly faster than iOS
      ),
      (instance) {
        instance.onLongPressStart = _handleLongPressStart;
      },
    ),
  },
  excludeFromSemantics: true,
  behavior: HitTestBehavior.opaque, // Changed from translucent
  ...
)
```

### Issue: Performance with Many Words

**Solution**: Limit visible words and use efficient hit detection:

```dart
// Only calculate positions for visible words
final visibleWords = _isExpanded ? words.take(12) : words.take(4);

// Use spatial hashing for hit detection instead of checking all words
final hoveredWord = _spatialHash.query(dragPosition);
```

### Issue: Animation Jank

**Solution**: Use `AnimatedBuilder` and optimize paint calls:

```dart
@override
bool shouldRepaint(WheelPainter oldDelegate) {
  // Only repaint when something actually changed
  return oldDelegate.hoveredWord != hoveredWord ||
         oldDelegate.dragPosition != dragPosition ||
         oldDelegate.isExpanded != isExpanded;
}
```

---

## Next Steps

1. Review this design document
2. Get approval for rebuild approach
3. Create feature branch: `feature/word-wheel-v2`
4. Implement Phase 1 (Controller)
5. Implement Phase 2 (Gesture Layer)
6. Test on physical iPad
7. Iterate based on real device behavior

---

## Questions to Resolve

1. Should we support tap-to-select in addition to drag-to-select?
2. Should wheel size be user-configurable?
3. Do we need accessibility support (VoiceOver, Switch Control)?
4. Should we add sound effects in addition to haptics?
5. Do we want customizable themes/colors?

---

**Author**: Claude Code Assistant
**Date**: 2025-01-08
**Status**: Proposal / Design Document
**Next Review**: After user feedback
