import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'phrase_sanitizer.dart';

/// Loads the stored custom phrases, repairing entries corrupted by the old
/// sync bug. When anything changed, the repaired list is persisted and usage
/// counts and cached audio are migrated from the old text to the repaired
/// text. Returns the repaired list.
Future<List<String>> repairStoredCustomPhrases(SharedPreferences prefs) async {
  final customPhrasesJson = prefs.getString('custom_phrases');
  if (customPhrasesJson == null) return [];

  final List<dynamic> customList = jsonDecode(customPhrasesJson);
  final repair =
      PhraseSanitizer.repairAll(customList.map((e) => e.toString()));
  if (repair.changed) {
    await prefs.setString('custom_phrases', jsonEncode(repair.phrases));
    await _migrateRepairedPhraseData(prefs, repair);
  }
  return repair.phrases;
}

/// After repairing corrupted phrase text, move usage counts and cached
/// audio stored under the old text to the repaired text, and drop entries
/// for phrases that were removed entirely.
Future<void> _migrateRepairedPhraseData(
  SharedPreferences prefs,
  PhraseRepairResult repair,
) async {
  // The phrase a removed entry folds into, if any
  String? survivorOf(String old) {
    final recovered = PhraseSanitizer.recover(old);
    return recovered == null || recovered.isEmpty ? null : recovered;
  }

  // Usage counts
  final usageJson = prefs.getString('phrase_usage');
  if (usageJson != null) {
    final Map<String, dynamic> raw = jsonDecode(usageJson);
    final usage = raw.map((key, value) => MapEntry(key, (value as num).toInt()));
    var usageChanged = false;
    void moveCount(String from, String? to) {
      if (from == to) return;
      final count = usage.remove(from);
      if (count == null) return;
      usageChanged = true;
      if (to != null) {
        usage[to] = (usage[to] ?? 0) + count;
      }
    }

    repair.renamed.forEach(moveCount);
    for (final old in repair.removed) {
      // A removed duplicate folds its count into the surviving phrase
      moveCount(old, survivorOf(old));
    }
    if (usageChanged) {
      await prefs.setString('phrase_usage', jsonEncode(usage));
    }
  }

  // Cached audio
  Future<void> moveAudio(String from, String? to) async {
    if (from == to) return;
    final fromKey = 'phrase_audio_$from';
    final audio = prefs.getString(fromKey);
    if (audio == null) return;
    if (to != null && prefs.getString('phrase_audio_$to') == null) {
      await prefs.setString('phrase_audio_$to', audio);
    }
    await prefs.remove(fromKey);
  }

  for (final entry in repair.renamed.entries) {
    await moveAudio(entry.key, entry.value);
  }
  for (final old in repair.removed) {
    await moveAudio(old, survivorOf(old));
  }
}
