import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stuart_speaks_app/core/utils/phrase_storage_repair.dart';

const _id1 = '84771262-7aa9-4d89-863e-df9115448345';
const _id2 = 'a02c924d-0578-4f21-9f00-111111111111';

String _wrap(String text, [String id = _id1]) => '{id: $id, text: $text}';

Future<SharedPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Map<String, dynamic> _usage(SharedPreferences prefs) =>
    jsonDecode(prefs.getString('phrase_usage')!) as Map<String, dynamic>;

void main() {
  test('returns empty list when nothing is stored', () async {
    final prefs = await _prefsWith({});

    expect(await repairStoredCustomPhrases(prefs), isEmpty);
    expect(prefs.getString('custom_phrases'), isNull);
  });

  test('leaves clean data untouched', () async {
    final prefs = await _prefsWith({
      'custom_phrases': jsonEncode(['hello', 'thank you']),
      'phrase_usage': jsonEncode({'hello': 3}),
      'phrase_audio_hello': 'audio-hello',
    });

    expect(await repairStoredCustomPhrases(prefs), ['hello', 'thank you']);
    expect(_usage(prefs), {'hello': 3});
    expect(prefs.getString('phrase_audio_hello'), 'audio-hello');
  });

  test('repairs corrupted phrases and persists the cleaned list', () async {
    final prefs = await _prefsWith({
      'custom_phrases': jsonEncode([_wrap(_wrap('hello', _id2)), 'thanks']),
    });

    final phrases = await repairStoredCustomPhrases(prefs);

    expect(phrases, ['hello', 'thanks']);
    expect(jsonDecode(prefs.getString('custom_phrases')!), ['hello', 'thanks']);
  });

  test('moves usage count and cached audio to the repaired text', () async {
    final corrupted = _wrap('hello');
    final prefs = await _prefsWith({
      'custom_phrases': jsonEncode([corrupted]),
      'phrase_usage': jsonEncode({corrupted: 4}),
      'phrase_audio_$corrupted': 'audio-corrupted',
    });

    await repairStoredCustomPhrases(prefs);

    expect(_usage(prefs), {'hello': 4});
    expect(prefs.getString('phrase_audio_hello'), 'audio-corrupted');
    expect(prefs.getString('phrase_audio_$corrupted'), isNull);
  });

  test('folds a corrupted duplicate into the surviving phrase', () async {
    final corrupted = _wrap('hello');
    final prefs = await _prefsWith({
      'custom_phrases': jsonEncode(['hello', corrupted]),
      'phrase_usage': jsonEncode({'hello': 2, corrupted: 5}),
      'phrase_audio_hello': 'audio-clean',
      'phrase_audio_$corrupted': 'audio-corrupted',
    });

    expect(await repairStoredCustomPhrases(prefs), ['hello']);
    expect(_usage(prefs), {'hello': 7});
    // The survivor's own audio wins; the duplicate's copy is dropped
    expect(prefs.getString('phrase_audio_hello'), 'audio-clean');
    expect(prefs.getString('phrase_audio_$corrupted'), isNull);
  });

  test('keeps usage and audio when a plain duplicate is removed', () async {
    // Regression: moving data from "hello" to "hello" used to delete the
    // survivor's cached audio
    final prefs = await _prefsWith({
      'custom_phrases': jsonEncode(['hello', 'hello']),
      'phrase_usage': jsonEncode({'hello': 3}),
      'phrase_audio_hello': 'audio-hello',
    });

    expect(await repairStoredCustomPhrases(prefs), ['hello']);
    expect(_usage(prefs), {'hello': 3});
    expect(prefs.getString('phrase_audio_hello'), 'audio-hello');
  });

  test('drops unrecoverable and empty entries with their data', () async {
    final unrecoverable = _wrap('');
    final prefs = await _prefsWith({
      'custom_phrases': jsonEncode([unrecoverable, '', 'hello']),
      'phrase_usage': jsonEncode({unrecoverable: 2, 'hello': 1}),
      'phrase_audio_$unrecoverable': 'audio-garbage',
    });

    expect(await repairStoredCustomPhrases(prefs), ['hello']);
    expect(_usage(prefs), {'hello': 1});
    expect(prefs.getString('phrase_audio_$unrecoverable'), isNull);
  });
}
