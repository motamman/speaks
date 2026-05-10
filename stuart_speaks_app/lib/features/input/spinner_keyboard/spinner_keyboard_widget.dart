import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/word_usage_tracker.dart';
import 'spinner_keyboard_config.dart';
import 'spinner_keyboard_controller.dart';
import 'spinner_keyboard_painter.dart';

/// Main spinner keyboard widget
/// Long-press to activate, drag to select keys, release to complete word
class SpinnerKeyboardWidget extends StatefulWidget {
  /// Callback when a complete word/string is entered
  final void Function(String)? onStringCompleted;

  /// Callback when each individual key is selected
  final void Function(String)? onKeySelected;

  /// Callback when a word prediction is selected
  final void Function(String)? onWordPredictionSelected;

  /// Word tracker for predictions (optional)
  final WordUsageTracker? wordTracker;

  /// Optional pre-built controller (useful for testing or external control)
  final SpinnerKeyboardController? controller;

  /// Whether to always show the keyboard (for debugging)
  final bool alwaysVisible;

  /// Whether the user is left-handed (affects shift button position and magnifier)
  final bool isLeftHanded;

  /// Callback for backspace when built string is empty (to operate on text field)
  final void Function()? onBackspaceToTextField;

  /// Callback for clear word when built string is empty (to operate on text field)
  final void Function()? onClearWordInTextField;

  const SpinnerKeyboardWidget({
    super.key,
    this.onStringCompleted,
    this.onKeySelected,
    this.onWordPredictionSelected,
    this.onBackspaceToTextField,
    this.onClearWordInTextField,
    this.wordTracker,
    this.controller,
    this.alwaysVisible = false,
    this.isLeftHanded = false,
  });

  @override
  State<SpinnerKeyboardWidget> createState() => _SpinnerKeyboardWidgetState();
}

class _SpinnerKeyboardWidgetState extends State<SpinnerKeyboardWidget> {
  late SpinnerKeyboardController _controller;
  Timer? _longPressTimer;
  Timer? _periodicTimer; // Handles dwell selection and backspace checking
  bool _isLongPressActive = false;
  bool _initialized = false;
  bool _isShiftActive = false;
  bool _isShiftPressed = false;
  bool _isBackspacePressed = false;
  int? _activePointerId; // Track active pointer to ignore multi-touch
  double _lastDwellProgress = 0.0; // Track for optimized rebuilds

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      // Will be initialized properly in didChangeDependencies with MediaQuery
      _controller = SpinnerKeyboardController(
        config: const SpinnerKeyboardConfig(
          centerX: 200,
          centerY: 200,
          letterRingRadius: 170,
          numberRingRadius: 120,
          punctuationRingRadius: 76,
        ),
      );
    }

    _updateCallbacks();
  }

  void _updateCallbacks() {
    // Wrap onStringCompleted to apply shift case conversion
    _controller.onStringCompleted = (text) {
      if (widget.onStringCompleted != null) {
        // Apply shift: if shift was active at start, capitalize first letter
        // The built string already has correct case applied per-key
        widget.onStringCompleted!(text);
      }
      // Reset shift after word is completed
      if (_isShiftActive) {
        setState(() {
          _isShiftActive = false;
        });
      }
    };

    // Wrap onKeySelected to apply shift case conversion
    _controller.onKeySelected = (key) {
      if (widget.onKeySelected != null) {
        // Apply shift to letters
        String outputKey = key;
        if (SpinnerKeyboardController.letters.contains(key.toUpperCase())) {
          outputKey = _isShiftActive ? key.toUpperCase() : key.toLowerCase();
        }
        widget.onKeySelected!(outputKey);
      }
    };

    _controller.onWordPredictionSelected = widget.onWordPredictionSelected;

    if (widget.wordTracker != null) {
      _controller.setWordTracker(widget.wordTracker!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller == null) {
      final screenSize = MediaQuery.of(context).size;
      final newConfig = SpinnerKeyboardConfig.responsive(screenSize);

      // Recreate if size changed (low threshold for responsive sizing)
      if ((newConfig.centerX - _controller.config.centerX).abs() > 1) {
        _controller.dispose();
        _controller = SpinnerKeyboardController(config: newConfig);
        _updateCallbacks();
        _initialized = false;
      }

      // Initialize controller if not done yet
      if (!_initialized) {
        _controller.initialize(wordTracker: widget.wordTracker);
        _initialized = true;
      }
    }
  }

  @override
  void didUpdateWidget(SpinnerKeyboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCallbacks();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _periodicTimer?.cancel();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Offset? _pointerDownPosition;
  DateTime? _pointerDownTime;
  bool _isLongPress = false;
  static const Duration _longPressDuration = Duration(milliseconds: 500);
  static const double _dragThreshold = 30.0;

  void _onPointerDown(PointerDownEvent event) {
    // Ignore additional pointers (multi-touch)
    if (_activePointerId != null) return;
    _activePointerId = event.pointer;

    _longPressTimer?.cancel();
    _periodicTimer?.cancel();

    final position = _scalePosition(event.localPosition);
    _pointerDownPosition = position;
    _pointerDownTime = DateTime.now();
    _isLongPress = false;

    _controller.updateDrag(position);

    // Start timer for long press detection
    _longPressTimer = Timer(_longPressDuration, () {
      _isLongPress = true;
      HapticFeedback.mediumImpact();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointerId) return;

    final position = _scalePosition(event.localPosition);

    // Only update hovered key display if not in long press mode
    // Long press mode is for drag gestures, not key selection
    if (!_isLongPress) {
      final previousHovered = _controller.hoveredKey;
      _controller.updateDrag(position);

      // Haptic feedback on key change
      if (_controller.hoveredKey != previousHovered && _controller.hoveredKey != null) {
        HapticFeedback.selectionClick();
      }
    }

    if (mounted) setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) return;

    _longPressTimer?.cancel();
    _periodicTimer?.cancel();
    _activePointerId = null;

    final position = _scalePosition(event.localPosition);
    final downPos = _pointerDownPosition;
    final isInCenter = _controller.isInCenterHub(position);

    if (_isLongPress && downPos != null) {
      // Long press gestures
      final center = Offset(_controller.config.centerX, _controller.config.centerY);
      final downDistance = (downPos - center).distance;
      final upDistance = (position - center).distance;
      final dragDelta = upDistance - downDistance;

      if (dragDelta > _dragThreshold) {
        // Dragged outward - send word
        if (_controller.builtString.isNotEmpty) {
          widget.onStringCompleted?.call(_controller.builtString);
          _controller.clearString();
          HapticFeedback.heavyImpact();
        }
      }
    } else {
      // Tap gestures
      if (isInCenter) {
        // Check if tapping on a prediction
        if (_controller.hasPredictions) {
          final predictionIndex = _controller.getPredictionIndexAtPosition(position);
          if (predictionIndex != null) {
            // Tap on prediction - complete with that word
            _controller.selectPrediction(predictionIndex);
            widget.onStringCompleted?.call(_controller.builtString);
            _controller.clearString();
            HapticFeedback.heavyImpact();
          } else if (_controller.builtString.isNotEmpty) {
            // Tap on center (not on prediction) - send current word
            widget.onStringCompleted?.call(_controller.builtString);
            _controller.clearString();
            HapticFeedback.heavyImpact();
          }
        } else if (_controller.builtString.isNotEmpty) {
          // No predictions, tap on center - send word
          widget.onStringCompleted?.call(_controller.builtString);
          _controller.clearString();
          HapticFeedback.heavyImpact();
        }
      } else if (_controller.hoveredKey != null) {
        // Tap on letter - select it (apply shift state)
        final key = _controller.hoveredKey!;
        final outputKey = _isShiftActive ? key.toUpperCase() : key.toLowerCase();
        _controller.selectKey(outputKey);
        HapticFeedback.selectionClick();
      }
    }

    _pointerDownPosition = null;
    _pointerDownTime = null;
    _isLongPress = false;
    if (mounted) setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;

    _longPressTimer?.cancel();
    _periodicTimer?.cancel();
    _activePointerId = null;
    _pointerDownPosition = null;
    _pointerDownTime = null;
    _isLongPress = false;
  }

  Offset _scalePosition(Offset position) {
    // Scale position if widget size differs from controller config
    // For now, assume 1:1 scaling - will be updated if needed
    return position;
  }

  void _toggleShift() {
    setState(() {
      _isShiftActive = !_isShiftActive;
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final isLeftHanded = widget.isLeftHanded;

    // Use LayoutBuilder to get actual available size and scale accordingly
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use the smaller dimension to maintain square aspect ratio
        final availableSize = min(constraints.maxWidth, constraints.maxHeight);
        final wheelSize = Size(availableSize, availableSize);

        // Update controller config if size changed significantly
        if ((availableSize - _controller.config.centerX * 2).abs() > 5) {
          // Schedule config update for next frame to avoid build-time setState
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final newConfig = SpinnerKeyboardConfig(
                centerX: availableSize / 2,
                centerY: availableSize / 2,
                letterRingRadius: availableSize * 0.425,
                numberRingRadius: availableSize * 0.30,
                punctuationRingRadius: availableSize * 0.19,
                centerHubRadius: availableSize * 0.11,
              );
              if ((_controller.config.centerX - newConfig.centerX).abs() > 5) {
                _controller.dispose();
                _controller = SpinnerKeyboardController(config: newConfig);
                _updateCallbacks();
                _controller.initialize(wordTracker: widget.wordTracker);
                setState(() {});
              }
            }
          });
        }

        return Center(
          child: SizedBox(
            width: wheelSize.width,
            height: wheelSize.height,
            child: Stack(
        children: [
          // Visual layer (always rendered when visible)
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (!widget.alwaysVisible && !_controller.isVisible) {
                return const SizedBox.shrink();
              }

              return IgnorePointer(
                child: CustomPaint(
                  painter: SpinnerKeyboardPainter(
                    controller: _controller,
                    isHolding: _controller.state == SpinnerState.dragging ||
                        _controller.state == SpinnerState.visible,
                    dwellProgress: _controller.dwellProgress,
                    isLeftHanded: isLeftHanded,
                    isShiftActive: _isShiftActive,
                  ),
                  size: wheelSize,
                ),
              );
            },
          ),

          // Gesture capture layer (always active)
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: Container(color: Colors.transparent),
          ),

          // Shift button - positioned based on handedness (from user's perspective)
          // Right-handed users: buttons on LEFT (out of way of right hand)
          // Left-handed users: buttons on RIGHT (out of way of left hand)
          Positioned(
            top: 8,
            left: isLeftHanded ? null : 8,
            right: isLeftHanded ? 8 : null,
            child: AbsorbPointer(
              absorbing: _isLongPressActive,
              child: Semantics(
                button: true,
                label: _isShiftActive ? 'Shift on, tap to turn off' : 'Shift off, tap to turn on',
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _isShiftPressed = true),
                  onTapUp: (_) {
                    setState(() => _isShiftPressed = false);
                    _toggleShift();
                  },
                  onTapCancel: () => setState(() => _isShiftPressed = false),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _isShiftPressed
                          ? const Color(0xFF1E40AF) // Darker when pressed
                          : _isShiftActive
                              ? const Color(0xFF2563EB)
                              : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isShiftActive
                            ? const Color(0xFF1D4ED8)
                            : Colors.grey[600]!,
                        width: 2,
                      ),
                      boxShadow: _isShiftPressed
                          ? [] // No shadow when pressed
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Icon(
                      Icons.arrow_upward,
                      color: (_isShiftActive || _isShiftPressed) ? Colors.white : Colors.grey[800],
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Backspace button - below shift button
          // Tap = delete one character, Long press = clear whole word
          Positioned(
            top: 72, // 8 + 56 + 8 (below shift with gap)
            left: isLeftHanded ? null : 8,
            right: isLeftHanded ? 8 : null,
            child: AbsorbPointer(
              absorbing: _isLongPressActive,
              child: Semantics(
                button: true,
                label: 'Backspace, long press to clear word',
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _isBackspacePressed = true),
                  onTapUp: (_) {
                    setState(() => _isBackspacePressed = false);
                    if (_controller.builtString.isNotEmpty) {
                      _controller.backspace();
                    } else {
                      widget.onBackspaceToTextField?.call();
                    }
                    HapticFeedback.mediumImpact();
                  },
                  onTapCancel: () => setState(() => _isBackspacePressed = false),
                  onLongPressStart: (_) => setState(() => _isBackspacePressed = true),
                  onLongPressEnd: (_) {
                    setState(() => _isBackspacePressed = false);
                    if (_controller.builtString.isNotEmpty) {
                      _controller.clearString();
                    } else {
                      widget.onClearWordInTextField?.call();
                    }
                    HapticFeedback.heavyImpact();
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _isBackspacePressed
                          ? Colors.grey[400] // Darker when pressed
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey[600]!,
                        width: 2,
                      ),
                      boxShadow: _isBackspacePressed
                          ? [] // No shadow when pressed
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Icon(
                      Icons.backspace_outlined,
                      color: Colors.grey[800],
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
      },
    );
  }
}

/// A simpler version that's always visible (for testing/demo)
class SpinnerKeyboardDemo extends StatelessWidget {
  final void Function(String)? onStringCompleted;

  const SpinnerKeyboardDemo({super.key, this.onStringCompleted});

  @override
  Widget build(BuildContext context) {
    return SpinnerKeyboardWidget(
      onStringCompleted: onStringCompleted,
      alwaysVisible: true,
    );
  }
}
