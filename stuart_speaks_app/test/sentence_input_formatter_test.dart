import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stuart_speaks_app/features/tts/sentence_input_formatter.dart';

TextEditingValue value(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

void main() {
  group('double-space period revert', () {
    test('reverts the iOS shortcut at end of text', () {
      final formatter = SentenceInputFormatter();
      final result = formatter.formatEditUpdate(
        value('hello ', 6),
        value('hello. ', 7),
      );
      expect(result.text, 'hello ');
      expect(result.selection.baseOffset, 6);
    });

    test('reverts the iOS shortcut mid-text', () {
      final formatter = SentenceInputFormatter();
      final result = formatter.formatEditUpdate(
        value('hello world', 6),
        value('hello. world', 7),
      );
      expect(result.text, 'hello world');
      expect(result.selection.baseOffset, 6);
    });

    test('leaves a deliberately typed period alone', () {
      final formatter = SentenceInputFormatter();
      // Typing '.' after "hello" (no preceding space at c-2)
      final result = formatter.formatEditUpdate(
        value('hello', 5),
        value('hello.', 6),
      );
      expect(result.text, 'hello.');
    });

    test('leaves "space then period" alone', () {
      final formatter = SentenceInputFormatter();
      // Typing '.' after "hello " -> "hello ." (no trailing space after '.')
      final result = formatter.formatEditUpdate(
        value('hello ', 6),
        value('hello .', 7),
      );
      expect(result.text, 'hello .');
    });

    test('leaves a pasted ". " alone (length delta +2)', () {
      final formatter = SentenceInputFormatter();
      final result = formatter.formatEditUpdate(
        value('hello ', 6),
        value('hello . ', 8),
      );
      expect(result.text, 'hello . ');
    });

    test('does not fire after punctuation', () {
      final formatter = SentenceInputFormatter();
      // "hi! " -> "hi!. " should not be treated as the shortcut
      final result = formatter.formatEditUpdate(
        value('hi! ', 4),
        value('hi!. ', 5),
      );
      expect(result.text, 'hi!. ');
    });

    test('passes through non-collapsed selections', () {
      final formatter = SentenceInputFormatter();
      final result = formatter.formatEditUpdate(
        value('hello ', 6),
        const TextEditingValue(
          text: 'hello. ',
          selection: TextSelection(baseOffset: 0, extentOffset: 7),
        ),
      );
      expect(result.text, 'hello. ');
    });
  });

  group('newline handling', () {
    test('bare Enter is dropped and reported', () async {
      var fired = 0;
      final formatter = SentenceInputFormatter(onEnterDetected: () => fired++);
      final result = formatter.formatEditUpdate(
        value('hello', 5),
        value('hello\n', 6),
      );
      expect(result.text, 'hello');
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1);
    });

    test('Enter mid-text is dropped and reported', () async {
      var fired = 0;
      final formatter = SentenceInputFormatter(onEnterDetected: () => fired++);
      final result = formatter.formatEditUpdate(
        value('hello world', 5),
        value('hello\n world', 6),
      );
      expect(result.text, 'hello world');
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1);
    });

    test('multi-line paste becomes spaces without submitting', () async {
      var fired = 0;
      final formatter = SentenceInputFormatter(onEnterDetected: () => fired++);
      final result = formatter.formatEditUpdate(
        value('', 0),
        value('line one\nline two\nline three', 28),
      );
      expect(result.text, 'line one line two line three');
      expect(result.text.contains('\n'), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(fired, 0);
    });

    test('plain typing passes through untouched', () {
      final formatter = SentenceInputFormatter();
      final result = formatter.formatEditUpdate(
        value('hell', 4),
        value('hello', 5),
      );
      expect(result.text, 'hello');
      expect(result.selection.baseOffset, 5);
    });
  });
}
