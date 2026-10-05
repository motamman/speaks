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

    test('reverts deleteBackward + insert ". " sequence', () {
      final formatter = SentenceInputFormatter();
      // Step 1: UIKit deletes the first space (looks like a normal backspace)
      final afterDelete = formatter.formatEditUpdate(
        value('hello ', 6),
        value('hello', 5),
      );
      expect(afterDelete.text, 'hello');
      // Step 2: UIKit inserts ". "
      final result = formatter.formatEditUpdate(
        afterDelete,
        value('hello. ', 7),
      );
      expect(result.text, 'hello ');
      expect(result.selection.baseOffset, 6);
    });

    test('reverts deleteBackward + insert ". " mid-text', () {
      final formatter = SentenceInputFormatter();
      final result = formatter.formatEditUpdate(
        value('hello world', 5),
        value('hello.  world', 7),
      );
      expect(result.text, 'hello  world');
      expect(result.selection.baseOffset, 6);
    });

    test('reverts replace-with-period + insert space sequence', () {
      final formatter = SentenceInputFormatter();
      // Step 1: UIKit replaces the space before the caret with '.'
      final afterReplace = formatter.formatEditUpdate(
        value('hello ', 6),
        value('hello.', 6),
      );
      expect(afterReplace.text, 'hello ');
      expect(afterReplace.selection.baseOffset, 6);
      // Step 2: UIKit inserts the trailing space, which is swallowed
      final result = formatter.formatEditUpdate(
        afterReplace,
        value('hello  ', 7),
      );
      expect(result.text, 'hello ');
      expect(result.selection.baseOffset, 6);
    });

    test('a later space after a reverted shortcut is not swallowed', () {
      final formatter = SentenceInputFormatter();
      final afterReplace = formatter.formatEditUpdate(
        value('hello ', 6),
        value('hello.', 6),
      );
      final typed = formatter.formatEditUpdate(
        afterReplace,
        value('hello w', 7),
      );
      expect(typed.text, 'hello w');
      final spaced = formatter.formatEditUpdate(typed, value('hello w ', 8));
      expect(spaced.text, 'hello w ');
    });

    test('typing period then space keeps the period', () {
      final formatter = SentenceInputFormatter();
      final period = formatter.formatEditUpdate(
        value('hello', 5),
        value('hello.', 6),
      );
      expect(period.text, 'hello.');
      final space = formatter.formatEditUpdate(period, value('hello. ', 7));
      expect(space.text, 'hello. ');
    });

    test('does not fire the two-step shapes after punctuation', () {
      final formatter = SentenceInputFormatter();
      expect(
        formatter.formatEditUpdate(value('hi!', 3), value('hi!. ', 5)).text,
        'hi!. ',
      );
      expect(
        formatter.formatEditUpdate(value('hi! ', 4), value('hi!.', 4)).text,
        'hi!.',
      );
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
