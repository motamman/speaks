import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bigram_data.dart';

/// Service for managing letter bigram frequencies
/// Combines static English frequencies with personal usage learning
class LetterBigramService {
  static const _storageKey = 'personal_letter_bigrams';

  // Personal bigram counts: letter -> following letter -> count
  Map<String, Map<String, int>> _personalBigrams = {};

  // Weights for blending English and personal data
  static const double _englishWeight = 1.0;
  static const double _personalWeight = 2.0; // Personal patterns weighted higher

  /// Initialize the service, loading any saved personal data
  Future<void> initialize() async {
    await _loadPersonalBigrams();
  }

  /// Record a letter transition (for learning)
  /// Call this each time the user types a letter after another
  void recordTransition(String fromLetter, String toLetter) {
    final from = fromLetter.toUpperCase();
    final to = toLetter.toUpperCase();

    if (!from.contains(RegExp(r'[A-Z]')) || !to.contains(RegExp(r'[A-Z]'))) {
      return; // Only track letter-to-letter transitions
    }

    _personalBigrams.putIfAbsent(from, () => {});
    _personalBigrams[from]!.putIfAbsent(to, () => 0);
    _personalBigrams[from]![to] = _personalBigrams[from]![to]! + 1;

    // Debounce saving to avoid too many writes
    _debouncedSave();
  }

  /// Get combined frequencies for letters following the given letter
  /// Returns map of letter -> frequency (0.0 to 1.0)
  Map<String, double> getFrequencies(String letter) {
    final upper = letter.toUpperCase();
    if (!upper.contains(RegExp(r'[A-Z]'))) {
      return {};
    }

    // Get English frequencies
    final englishFreqs = getBigramFrequencies(upper);

    // Get personal frequencies (normalized)
    final personalFreqs = _getPersonalFrequencies(upper);

    // Blend them together
    return _blendFrequencies(englishFreqs, personalFreqs);
  }

  /// Get a sorted list of letters by predicted frequency
  List<String> getSortedLetters(String afterLetter) {
    final frequencies = getFrequencies(afterLetter);

    if (frequencies.isEmpty) {
      // No data - return letters in general frequency order
      return 'ETAOINSHRDLCUMWFGYPBVKJXQZ'.split('');
    }

    // Sort by frequency descending
    final entries = frequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final result = entries.map((e) => e.key).toList();

    // Add any missing letters at the end
    for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
      if (!result.contains(letter)) {
        result.add(letter);
      }
    }

    return result;
  }

  /// Get personal frequencies normalized to 0.0-1.0
  Map<String, double> _getPersonalFrequencies(String letter) {
    final counts = _personalBigrams[letter];
    if (counts == null || counts.isEmpty) {
      return {};
    }

    final total = counts.values.reduce((a, b) => a + b);
    if (total == 0) return {};

    final result = <String, double>{};
    for (final entry in counts.entries) {
      result[entry.key] = entry.value / total;
    }
    return result;
  }

  /// Blend English and personal frequencies
  Map<String, double> _blendFrequencies(
    Map<String, double> english,
    Map<String, double> personal,
  ) {
    final result = <String, double>{};

    // Get all letters from both sources
    final allLetters = {...english.keys, ...personal.keys};

    for (final letter in allLetters) {
      final englishVal = english[letter] ?? 0;
      final personalVal = personal[letter] ?? 0;

      // Weighted average (personal data weighted higher if available)
      if (personalVal > 0) {
        result[letter] = (englishVal * _englishWeight + personalVal * _personalWeight) /
            (_englishWeight + _personalWeight);
      } else {
        result[letter] = englishVal;
      }
    }

    // Normalize to sum to 1.0
    final total = result.values.fold(0.0, (a, b) => a + b);
    if (total > 0) {
      for (final key in result.keys) {
        result[key] = result[key]! / total;
      }
    }

    return result;
  }

  // Debounced save
  bool _pendingSave = false;

  void _debouncedSave() {
    if (_pendingSave) return;
    _pendingSave = true;

    Future.delayed(const Duration(seconds: 5), () async {
      _pendingSave = false;
      await _savePersonalBigrams();
    });
  }

  /// Load personal bigrams from storage
  Future<void> _loadPersonalBigrams() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data != null) {
        final Map<String, dynamic> decoded = jsonDecode(data);
        _personalBigrams = decoded.map((key, value) =>
            MapEntry(key, (value as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, v as int))));
      }
    } catch (e) {
      debugPrint('Error loading personal bigrams: $e');
      _personalBigrams = {};
    }
  }

  /// Save personal bigrams to storage
  Future<void> _savePersonalBigrams() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_personalBigrams);
      await prefs.setString(_storageKey, data);
    } catch (e) {
      debugPrint('Error saving personal bigrams: $e');
    }
  }

  /// Clear all personal learning data
  Future<void> clearPersonalData() async {
    _personalBigrams = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('Error clearing personal bigrams: $e');
    }
  }

  /// Get stats about personal learning
  Map<String, int> getPersonalStats() {
    int totalTransitions = 0;
    int uniquePairs = 0;

    for (final fromLetter in _personalBigrams.values) {
      for (final count in fromLetter.values) {
        totalTransitions += count;
        uniquePairs++;
      }
    }

    return {
      'totalTransitions': totalTransitions,
      'uniquePairs': uniquePairs,
      'lettersWithData': _personalBigrams.length,
    };
  }
}
