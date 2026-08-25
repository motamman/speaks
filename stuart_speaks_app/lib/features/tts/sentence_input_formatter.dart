import 'dart:async';

import 'package:flutter/services.dart';

/// Sanitizes TTS input text.
///
/// - Newlines never land in the field: a bare Enter insertion is dropped and
///   reported via [onEnterDetected] (so the screen can speak the text), and
///   newlines arriving any other way (multi-line paste, IME artifacts) are
///   converted to spaces.
/// - Reverts iOS's system-wide double-space "." shortcut, which replaces the
///   trailing space before the caret with '. ' in a single editing update.
///   Deliberately typed periods don't match that signature and pass through.
class SentenceInputFormatter extends TextInputFormatter {
  SentenceInputFormatter({this.onEnterDetected});

  /// Called (asynchronously) when the user pressed Enter via the text-input
  /// channel rather than a hardware key event.
  final VoidCallback? onEnterDetected;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var value = newValue;

    if (value.text.contains('\n')) {
      final isBareEnter = !oldValue.text.contains('\n') &&
          value.text.length == oldValue.text.length + 1 &&
          value.text.replaceFirst('\n', '') == oldValue.text;
      if (isBareEnter) {
        final callback = onEnterDetected;
        if (callback != null) {
          scheduleMicrotask(callback);
        }
        return oldValue;
      }
      final stripped = value.text.replaceAll('\n', ' ');
      value = TextEditingValue(
        text: stripped,
        selection: TextSelection.collapsed(
          offset: value.selection.baseOffset.clamp(0, stripped.length).toInt(),
        ),
        composing: TextRange.empty,
      );
    }

    return _revertDoubleSpacePeriod(oldValue, value) ?? value;
  }

  TextEditingValue? _revertDoubleSpacePeriod(
    TextEditingValue o,
    TextEditingValue n,
  ) {
    final sel = n.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final c = sel.baseOffset;
    // Signature of the OS shortcut: the ' ' at c-2 became '. ' in one update.
    if (c < 2 || n.text.length != o.text.length + 1) return null;
    if (n.text.substring(c - 2, c) != '. ') return null;
    if (!o.selection.isValid ||
        !o.selection.isCollapsed ||
        o.selection.baseOffset != c - 1) {
      return null;
    }
    if (o.text[c - 2] != ' ') return null;
    if (o.text.substring(0, c - 2) != n.text.substring(0, c - 2)) return null;
    if (o.text.substring(c - 1) != n.text.substring(c)) return null;
    // Only a word character before the space matches the real shortcut shape.
    if (c >= 3 && !RegExp(r"[A-Za-z0-9']").hasMatch(n.text[c - 3])) return null;

    return TextEditingValue(
      text: o.text,
      selection: TextSelection.collapsed(offset: c - 1),
      composing: TextRange.empty,
    );
  }
}
