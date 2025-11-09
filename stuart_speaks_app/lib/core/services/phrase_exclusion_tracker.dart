import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which default phrases are hidden (excluded) by the user
class PhraseExclusionTracker {
  static const String _exclusionKey = 'excluded_phrases';
  final SharedPreferences _prefs;
  Set<String> _excludedPhrases = {};

  PhraseExclusionTracker(this._prefs);

  /// Initialize and load excluded phrases
  Future<void> initialize() async {
    final excludedJson = _prefs.getString(_exclusionKey);
    if (excludedJson != null) {
      final List<dynamic> excluded = jsonDecode(excludedJson);
      _excludedPhrases = excluded.map((e) => e.toString()).toSet();
    }
  }

  /// Check if a phrase is excluded
  bool isExcluded(String phraseText) {
    return _excludedPhrases.contains(phraseText);
  }

  /// Add a phrase to the exclusion list
  Future<void> exclude(String phraseText) async {
    _excludedPhrases.add(phraseText);
    await _save();
  }

  /// Remove a phrase from the exclusion list (restore it)
  Future<void> restore(String phraseText) async {
    _excludedPhrases.remove(phraseText);
    await _save();
  }

  /// Save exclusion list to persistent storage
  Future<void> _save() async {
    await _prefs.setString(
      _exclusionKey,
      jsonEncode(_excludedPhrases.toList()),
    );
  }

  /// Get all excluded phrases
  Set<String> get excludedPhrases => Set.unmodifiable(_excludedPhrases);
}
