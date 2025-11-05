import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/word.dart';

/// Manages user vocabulary and tracks word usage patterns
class WordUsageTracker {
  static const String _vocabKey = 'user_vocabulary';
  static const String _historyKey = 'text_history';
  static const int _maxHistoryItems = 50;

  final SharedPreferences _prefs;
  Map<String, Word> _vocabulary = {};
  List<String> _textHistory = [];

  WordUsageTracker(this._prefs);

  /// Initialize and load vocabulary from storage
  Future<void> initialize() async {
    await _loadVocabulary();
    await _loadHistory();
  }

  /// Track when a word is used
  void trackWordUsage(String wordText) {
    final key = wordText.toLowerCase();

    if (_vocabulary.containsKey(key)) {
      _vocabulary[key]!.recordUsage();
    } else {
      // First time using this word - add to vocabulary
      _vocabulary[key] = Word(
        text: wordText,
        phonetic: _generateSimplePhonetic(wordText),
        usageCount: 1,
        lastUsed: DateTime.now(),
      );
    }

    _saveVocabulary();
  }

  /// Track a complete sentence/phrase
  void trackSentence(String sentence) {
    // Track individual words
    final words = sentence.split(RegExp(r'\s+'));
    for (final word in words) {
      final cleaned = word.replaceAll(RegExp(r'[^\w]'), '');
      if (cleaned.isNotEmpty) {
        trackWordUsage(cleaned);
      }
    }

    // Add to history
    if (!_textHistory.contains(sentence)) {
      _textHistory.insert(0, sentence);

      // Limit history size
      if (_textHistory.length > _maxHistoryItems) {
        _textHistory = _textHistory.sublist(0, _maxHistoryItems);
      }

      _saveHistory();
    }
  }

  /// Get word suggestions for a given input
  List<Word> getSuggestions(String input, {int limit = 12}) {
    if (input.isEmpty) {
      // Return most frequently used words
      return _getMostUsedWords(limit);
    }

    // Filter by prefix match
    final matches = _vocabulary.values
        .where((word) => word.matches(input))
        .toList();

    // Sort by usage score (frequency + recency)
    matches.sort((a, b) => b.score.compareTo(a.score));

    return matches.take(limit).toList();
  }

  /// Get most frequently used words for sentence starters
  List<Word> getSentenceStarters({int limit = 8}) {
    // Common sentence starter words
    final starterWords = [
      'I',
      'You',
      'Can',
      'Want',
      'Need',
      'Help',
      'Please',
      'Thank'
    ];

    final starters = <Word>[];

    for (final starter in starterWords) {
      final key = starter.toLowerCase();
      if (_vocabulary.containsKey(key)) {
        starters.add(_vocabulary[key]!);
      } else {
        // Create placeholder with zero usage
        starters.add(Word(
          text: starter,
          phonetic: starter.toLowerCase(),
          usageCount: 0,
        ));
      }
    }

    // Sort by usage
    starters.sort((a, b) => b.usageCount.compareTo(a.usageCount));

    return starters.take(limit).toList();
  }

  /// Get text history
  List<String> get textHistory => List.unmodifiable(_textHistory);

  /// Delete item from history
  void deleteFromHistory(String text) {
    _textHistory.remove(text);
    _saveHistory();
  }

  /// Clear all history
  void clearHistory() {
    _textHistory.clear();
    _saveHistory();
  }

  /// Get total vocabulary size
  int get vocabularySize => _vocabulary.length;

  /// Get all words sorted by usage
  List<Word> getAllWords() {
    final words = _vocabulary.values.toList();
    words.sort((a, b) => b.score.compareTo(a.score));
    return words;
  }

  /// Reset all usage statistics
  Future<void> resetStatistics() async {
    _vocabulary.clear();
    _textHistory.clear();
    await _prefs.remove(_vocabKey);
    await _prefs.remove(_historyKey);
    await _loadCoreVocabulary();
  }

  // Private methods

  List<Word> _getMostUsedWords(int limit) {
    final words = _vocabulary.values.toList();
    words.sort((a, b) => b.score.compareTo(a.score));
    return words.take(limit).toList();
  }

  Future<void> _loadVocabulary() async {
    final json = _prefs.getString(_vocabKey);

    if (json != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(json);
        _vocabulary = data.map(
          (key, value) => MapEntry(
            key,
            Word.fromJson(value as Map<String, dynamic>),
          ),
        );
      } catch (e) {
        // If parsing fails, start fresh
        _vocabulary = {};
      }
    }

    // If empty, load core vocabulary
    if (_vocabulary.isEmpty) {
      await _loadCoreVocabulary();
    }
  }

  Future<void> _saveVocabulary() async {
    final data = _vocabulary.map((key, word) => MapEntry(key, word.toJson()));
    await _prefs.setString(_vocabKey, jsonEncode(data));
  }

  Future<void> _loadHistory() async {
    final json = _prefs.getString(_historyKey);

    if (json != null) {
      try {
        final List<dynamic> data = jsonDecode(json);
        _textHistory = data.map((e) => e as String).toList();
      } catch (e) {
        _textHistory = [];
      }
    }
  }

  Future<void> _saveHistory() async {
    await _prefs.setString(_historyKey, jsonEncode(_textHistory));
  }

  /// Load core AAC vocabulary (high-frequency words)
  Future<void> _loadCoreVocabulary() async {
    final coreWords = [
      // Pronouns
      ('I', 100),
      ('you', 90),
      ('he', 80),
      ('she', 80),
      ('we', 75),
      ('they', 75),
      ('it', 70),
      // Common verbs
      ('want', 85),
      ('need', 85),
      ('go', 80),
      ('help', 80),
      ('like', 75),
      ('have', 75),
      ('get', 70),
      ('make', 70),
      ('stop', 65),
      ('can', 85),
      ('will', 80),
      ('do', 75),
      // Common nouns
      ('water', 70),
      ('food', 70),
      ('bathroom', 65),
      ('home', 65),
      ('bed', 60),
      ('pain', 60),
      // Social words
      ('yes', 90),
      ('no', 90),
      ('please', 85),
      ('thank', 80),
      ('sorry', 75),
      ('hello', 70),
      ('goodbye', 70),
      // Descriptors
      ('more', 80),
      ('good', 75),
      ('bad', 75),
      ('hot', 70),
      ('cold', 70),
      ('happy', 70),
      ('sad', 70),
      ('tired', 65),
      ('hungry', 65),
      ('thirsty', 65),
      // Question words
      ('what', 75),
      ('where', 75),
      ('when', 75),
      ('who', 75),
      ('why', 75),
      ('how', 75),
      // Common phrases
      ('love', 70),
      ('okay', 70),
    ];

    for (final (text, initialCount) in coreWords) {
      _vocabulary[text.toLowerCase()] = Word(
        text: text,
        phonetic: text.toLowerCase(),
        usageCount: initialCount,
      );
    }

    await _saveVocabulary();
  }

  String _generateSimplePhonetic(String word) {
    // Simplified phonetic - just lowercase for now
    // Could be enhanced with actual phonetic rules later
    return word.toLowerCase().trim();
  }
}
