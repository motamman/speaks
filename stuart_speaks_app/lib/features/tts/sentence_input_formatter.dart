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

  static final RegExp _wordChar = RegExp(r"[A-Za-z0-9']");

  /// The Flutter iOS engine forwards each UIKit text call (insertText,
  /// deleteBackward, replaceRange) as its own update, so the shortcut can
  /// arrive in any of these shapes. Each is reverted so a double space leaves
  /// a single space and no period:
  ///
  /// 1. One replace: "hello " -> "hello. "
  /// 2. deleteBackward then insertText(". "): "hello " -> "hello" ->
  ///    "hello. " (the second step is caught)
  /// 3. Replace the space with "." then insertText(" "): "hello " ->
  ///    "hello." (caught) -> "hello  " (the extra space is swallowed)
  TextEditingValue? _revertDoubleSpacePeriod(
    TextEditingValue o,
    TextEditingValue n,
  ) {
    final swallowSpace = _swallowNextSpace;
    _swallowNextSpace = false;

    final sel = n.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    if (!o.selection.isValid || !o.selection.isCollapsed) return null;
    final c = sel.baseOffset;
    final oc = o.selection.baseOffset;
    if (c < 2 || c > n.text.length || oc > o.text.length) return null;

    final prefixSame = n.text.length >= c - 2 &&
        o.text.length >= c - 2 &&
        o.text.substring(0, c - 2) == n.text.substring(0, c - 2);

    // Shape 1: the ' ' at c-2 became '. ' in one update.
    if (n.text.length == o.text.length + 1 &&
        oc == c - 1 &&
        n.text.substring(c - 2, c) == '. ' &&
        o.text[c - 2] == ' ' &&
        prefixSame &&
        o.text.substring(c - 1) == n.text.substring(c) &&
        _followsWord(n.text, c - 2)) {
      return _collapsed(o.text, c - 1);
    }

    // Shape 2: '. ' inserted at the caret straight after a word. Typing
    // never inserts two characters at once.
    if (n.text.length == o.text.length + 2 &&
        oc == c - 2 &&
        n.text.substring(c - 2, c) == '. ' &&
        prefixSame &&
        o.text.substring(c - 2) == n.text.substring(c) &&
        _followsWord(n.text, c - 2)) {
      final text = n.text.replaceRange(c - 2, c, ' ');
      return _collapsed(text, c - 1);
    }

    // Shape 3, step 1: the ' ' just before the caret became '.'.
    if (n.text.length == o.text.length &&
        oc == c &&
        n.text[c - 1] == '.' &&
        o.text[c - 1] == ' ' &&
        o.text.substring(0, c - 1) == n.text.substring(0, c - 1) &&
        o.text.substring(c) == n.text.substring(c) &&
        _followsWord(n.text, c - 1)) {
      _swallowNextSpace = true;
      return _collapsed(o.text, c);
    }

    // Shape 3, step 2: drop the space UIKit inserts after the period.
    if (swallowSpace &&
        n.text.length == o.text.length + 1 &&
        oc == c - 1 &&
        n.text[c - 1] == ' ' &&
        o.text.substring(0, c - 1) == n.text.substring(0, c - 1) &&
        o.text.substring(c - 1) == n.text.substring(c)) {
      return o;
    }

    return null;
  }

  /// Set after reverting shape 3's first step; consumed by the next update.
  bool _swallowNextSpace = false;

  /// Whether the character before [index] is a word character (or [index] is
  /// the start of the text), matching where the OS shortcut fires.
  static bool _followsWord(String text, int index) =>
      index == 0 || _wordChar.hasMatch(text[index - 1]);

  static TextEditingValue _collapsed(String text, int offset) =>
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
        composing: TextRange.empty,
      );
}
