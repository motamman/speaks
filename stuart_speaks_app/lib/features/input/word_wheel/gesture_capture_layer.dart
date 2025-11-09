import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'word_wheel_controller.dart';

/// Always-active transparent layer that captures gestures
/// This layer ALWAYS has a size and can always capture gestures
class GestureCaptureLayer extends StatefulWidget {
  final WordWheelController controller;
  final Size wheelSize;
  final Function(Offset)? onActivatedWithPosition;

  const GestureCaptureLayer({
    super.key,
    required this.controller,
    required this.wheelSize,
    this.onActivatedWithPosition,
  });

  @override
  State<GestureCaptureLayer> createState() => _GestureCaptureLayerState();
}

class _GestureCaptureLayerState extends State<GestureCaptureLayer> {
  Timer? _longPressTimer;
  bool _isLongPressActive = false;

  @override
  void initState() {
    super.initState();
  }


  // Scale position from actual wheel size to controller's expected size
  Offset _scalePosition(Offset position) {
    final controllerSize = widget.controller.config.wheelSize;
    final scaleX = controllerSize.width / widget.wheelSize.width;
    final scaleY = controllerSize.height / widget.wheelSize.height;

    return Offset(
      position.dx * scaleX,
      position.dy * scaleY,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.wheelSize.width,
      height: widget.wheelSize.height,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _isLongPressActive = false;

          // Start long press timer
          _longPressTimer = Timer(widget.controller.config.activationDelay, () {
            _isLongPressActive = true;
            HapticFeedback.mediumImpact();

            widget.controller.activate(_scalePosition(event.localPosition));
            widget.onActivatedWithPosition?.call(event.position);
            widget.controller.show();
          });
        },
        onPointerMove: (event) {
          if (_isLongPressActive) {
            widget.controller.updateDrag(_scalePosition(event.localPosition));
          }
        },
        onPointerUp: (event) {
          _longPressTimer?.cancel();

          if (_isLongPressActive) {
            widget.controller.release();
            _isLongPressActive = false;
          }
        },
        onPointerCancel: (event) {
          _longPressTimer?.cancel();
          if (_isLongPressActive) {
            widget.controller.hide();
            _isLongPressActive = false;
          }
        },
        child: Container(
          color: Colors.transparent,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }
}
