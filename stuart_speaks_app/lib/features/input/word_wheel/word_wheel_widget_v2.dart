import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/word.dart';
import 'gesture_capture_layer.dart';
import 'wheel_visual_layer.dart';
import 'word_wheel_config.dart';
import 'word_wheel_controller.dart';

/// New word wheel implementation with clean separation of concerns
class WordWheelWidgetV2 extends StatefulWidget {
  final List<Word> words;
  final Function(Word) onWordSelected;
  final VoidCallback? onWheelShown;
  final VoidCallback? onWheelHidden;
  final VoidCallback? onActivated;
  final Function(Offset)? onActivatedWithPosition;
  final bool alwaysVisible;

  const WordWheelWidgetV2({
    super.key,
    required this.words,
    required this.onWordSelected,
    this.onWheelShown,
    this.onWheelHidden,
    this.onActivated,
    this.onActivatedWithPosition,
    this.alwaysVisible = false,
  });

  @override
  State<WordWheelWidgetV2> createState() => _WordWheelWidgetV2State();
}

class _WordWheelWidgetV2State extends State<WordWheelWidgetV2> {
  WordWheelController? _controller;
  Size _wheelSize = const Size(400, 400); // Default size
  Word? _lastHoveredWord;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Don't call MediaQuery here - do it in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize controller on first run
    if (!_isInitialized) {
      _wheelSize = _calculateWheelSize();

      final config = WordWheelConfig(
        centerX: _wheelSize.width / 2,
        centerY: _wheelSize.height / 2,
        innerRingDistance: _wheelSize.width * 0.25,
        outerRingDistance: _wheelSize.width * 0.45,
        innerRingDistanceY: _wheelSize.height * 0.25,
        outerRingDistanceY: _wheelSize.height * 0.45,
      );

      _controller = WordWheelController(
        config: config,
        words: widget.words,
      )
        ..onWordSelected = widget.onWordSelected
        ..onActivated = _handleActivated
        ..onHidden = _handleHidden
        ..addListener(_handleControllerChange);

      _isInitialized = true;
      return;
    }

    // Recalculate size if screen dimensions changed
    final newSize = _calculateWheelSize();
    if (newSize != _wheelSize) {
      setState(() {
        _wheelSize = newSize;

        // Update controller config with new size
        final newConfig = WordWheelConfig(
          centerX: _wheelSize.width / 2,
          centerY: _wheelSize.height / 2,
          innerRingDistance: _wheelSize.width * 0.25,
          outerRingDistance: _wheelSize.width * 0.45,
          innerRingDistanceY: _wheelSize.height * 0.25,
          outerRingDistanceY: _wheelSize.height * 0.45,
        );

        // Create new controller with updated config
        _controller?.dispose();
        _controller = WordWheelController(
          config: newConfig,
          words: widget.words,
        )
          ..onWordSelected = widget.onWordSelected
          ..onActivated = _handleActivated
          ..onHidden = _handleHidden
          ..addListener(_handleControllerChange);
      });
    }
  }

  @override
  void didUpdateWidget(WordWheelWidgetV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.words != oldWidget.words) {
      _controller?.updateWords(widget.words);
    }
  }

  Size _calculateWheelSize() {
    // The wheel will be sized by LayoutBuilder in tts_screen.dart
    // This is just a fallback - return a reasonable default
    return const Size(400, 400);
  }

  void _handleActivated() {
    widget.onActivated?.call();
    widget.onWheelShown?.call();
  }

  void _handleHidden() {
    widget.onWheelHidden?.call();
  }

  void _handleControllerChange() {
    final controller = _controller;
    if (controller == null) return;

    // Trigger haptic feedback when hovered word changes
    if (controller.hoveredWord != _lastHoveredWord) {
      if (controller.hoveredWord != null) {
        HapticFeedback.selectionClick();
      }
      _lastHoveredWord = controller.hoveredWord;
    }

    // Trigger haptic feedback on expand/collapse
    // This could be tracked with another state variable if needed
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    // Show placeholder until controller is initialized
    if (controller == null) {
      return SizedBox(
        width: _wheelSize.width,
        height: _wheelSize.height,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use parent constraints if available, otherwise use calculated size
        final Size effectiveSize;
        if (constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
          // Parent provided constraints - use them
          effectiveSize = Size(constraints.maxWidth, constraints.maxHeight);

          // Update wheel size and controller if dimensions changed
          if (effectiveSize != _wheelSize) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _wheelSize = effectiveSize;

                  // Recreate controller with new elliptical config
                  final newConfig = WordWheelConfig(
                    centerX: _wheelSize.width / 2,
                    centerY: _wheelSize.height / 2,
                    innerRingDistance: _wheelSize.width * 0.25,
                    outerRingDistance: _wheelSize.width * 0.45,
                    innerRingDistanceY: _wheelSize.height * 0.25,
                    outerRingDistanceY: _wheelSize.height * 0.45,
                  );

                  _controller?.dispose();
                  _controller = WordWheelController(
                    config: newConfig,
                    words: widget.words,
                  )
                    ..onWordSelected = widget.onWordSelected
                    ..onActivated = _handleActivated
                    ..onHidden = _handleHidden
                    ..addListener(_handleControllerChange);
                });
              }
            });
          }
        } else {
          // No parent constraints - use calculated size
          effectiveSize = _wheelSize;
        }

        return SizedBox(
          width: effectiveSize.width,
          height: effectiveSize.height,
          child: Stack(
            children: [
              // Layer 1: Always-active gesture capture (bottom)
              Positioned.fill(
                child: GestureCaptureLayer(
                  controller: controller,
                  wheelSize: effectiveSize,
                  onActivatedWithPosition: widget.onActivatedWithPosition,
                ),
              ),

              // Layer 2: Visual wheel (top, only when active)
              Positioned.fill(
                child: WheelVisualLayer(
                  controller: controller,
                  wheelSize: effectiveSize,
                  alwaysVisible: widget.alwaysVisible,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChange);
    _controller?.dispose();
    super.dispose();
  }
}
