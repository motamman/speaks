import 'package:flutter_test/flutter_test.dart';
import 'package:stuart_speaks_app/core/utils/phrase_sanitizer.dart';

void main() {
  group('isCorrupted', () {
    test('detects a single-wrapped record', () {
      expect(
        PhraseSanitizer.isCorrupted(
            '{id: 84771262-7aa9-4d89-863e-df9115448345, text: hello there}'),
        isTrue,
      );
    });

    test('detects a nested record', () {
      expect(
        PhraseSanitizer.isCorrupted(
            '{id: a7ab8d50-c514-44a3-849b-3c0c7d2ea263, text: {id: a02c924d-0578-4f21-9f00-111111111111, text: hello}}'),
        isTrue,
      );
    });

    test('does not flag normal phrases', () {
      expect(PhraseSanitizer.isCorrupted('Alexa, !!!!'), isFalse);
      expect(PhraseSanitizer.isCorrupted('Did you know, there is a better way?'),
          isFalse);
      expect(PhraseSanitizer.isCorrupted('{hello}'), isFalse);
    });
  });

  group('recover', () {
    test('unwraps a single-wrapped record', () {
      expect(
        PhraseSanitizer.recover(
            '{id: e3ca8b90-8596-4e24-a1c9-40fe69673792, text: the presidents action to take}'),
        'the presidents action to take',
      );
    });

    test('unwraps a doubly-nested record', () {
      expect(
        PhraseSanitizer.recover(
            '{id: 8317d98a-6f52-489c-9490-523c015c70dd, text: {id: 30d6f946-fc0e-465e-8888-222222222222, text: good morning}}'),
        'good morning',
      );
    });

    test('unwraps a triply-nested record', () {
      const inner = 'I need help please';
      const wrapped =
          '{id: 11111111-1111-1111-1111-111111111111, text: {id: 22222222-2222-2222-2222-222222222222, text: {id: 33333333-3333-3333-3333-333333333333, text: $inner}}}';
      expect(PhraseSanitizer.recover(wrapped), inner);
    });

    test('returns normal phrases unchanged', () {
      expect(PhraseSanitizer.recover('Alexa, !!!!'), 'Alexa, !!!!');
    });

    test('keeps text that never matched the wrapper, even if odd-looking', () {
      // Truncated record: does not match the wrapper shape, so it is kept
      // rather than risk deleting something that might be a real phrase
      const truncated =
          '{id: c90ccd82-9cfc-48fe-a7d7-d87dc1af0b7f, text: {id: a8cc3c80-82a2-473c';
      expect(PhraseSanitizer.recover(truncated), truncated);
    });

    test('keeps a legitimate phrase containing "{id:"', () {
      const phrase = 'the log said {id: deadbeef} failed';
      expect(PhraseSanitizer.recover(phrase), phrase);
    });

    test('keeps a wrapped phrase containing "{id:" as normal text', () {
      expect(
        PhraseSanitizer.recover(
            '{id: 77777777-7777-7777-7777-777777777777, text: the log said {id: x} failed}'),
        'the log said {id: x} failed',
      );
    });

    test('drops a record with empty text', () {
      expect(
        PhraseSanitizer.recover(
            '{id: 44444444-4444-4444-4444-444444444444, text: }'),
        isNull,
      );
    });

    test('drops a wrapper whose contents are still record-shaped', () {
      expect(
        PhraseSanitizer.recover(
            '{id: 55555555-5555-5555-5555-555555555555, text: {id: 66666666-truncated}'),
        isNull,
      );
    });
  });

  group('repairAll', () {
    test('repairs, dedupes, and records renames and removals', () {
      final result = PhraseSanitizer.repairAll([
        'Alexa, !!!!',
        '{id: 11111111-1111-1111-1111-111111111111, text: good morning}',
        'good morning',
        '{id: 44444444-4444-4444-4444-444444444444, text: }',
      ]);
      expect(result.phrases, ['Alexa, !!!!', 'good morning']);
      expect(result.renamed, {
        '{id: 11111111-1111-1111-1111-111111111111, text: good morning}':
            'good morning',
      });
      expect(result.removed, [
        'good morning', // duplicate of the repaired entry before it
        '{id: 44444444-4444-4444-4444-444444444444, text: }',
      ]);
      expect(result.changed, isTrue);
    });

    test('reports no change for a clean list', () {
      final result = PhraseSanitizer.repairAll(['hello', 'goodbye']);
      expect(result.phrases, ['hello', 'goodbye']);
      expect(result.changed, isFalse);
    });
  });
}
