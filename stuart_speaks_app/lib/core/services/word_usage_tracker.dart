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
  void trackWordUsage(String wordText, {int? position, String? previousWord}) {
    final key = wordText.toLowerCase();

    if (_vocabulary.containsKey(key)) {
      _vocabulary[key]!.recordUsage(position: position, previousWord: previousWord);
    } else {
      // First time using this word - add to vocabulary
      final newWord = Word(
        text: wordText,
        phonetic: _generateSimplePhonetic(wordText),
        usageCount: 1,
        lastUsed: DateTime.now(),
      );
      // Record position on first use
      if (position != null) {
        newWord.recordUsage(position: position, previousWord: previousWord);
      }
      _vocabulary[key] = newWord;
    }

    _saveVocabulary();
  }

  /// Track a complete sentence/phrase
  void trackSentence(String sentence) {
    // Split into sentences by common punctuation
    final sentences = sentence.split(RegExp(r'[.!?]+\s*'));

    for (final sent in sentences) {
      if (sent.trim().isEmpty) continue;

      // Track individual words with position and bigrams
      final words = sent.trim().split(RegExp(r'\s+'));
      String? previousWord;

      for (int i = 0; i < words.length; i++) {
        final cleaned = words[i].replaceAll(RegExp(r'[^\w]'), '');
        if (cleaned.isNotEmpty) {
          // Skip numerals
          if (RegExp(r'^\d+$').hasMatch(cleaned.toLowerCase())) continue;

          // Position: 1 = first word, 2 = second word, 3+ = other
          final position = i == 0 ? 1 : (i == 1 ? 2 : 3);

          // Track bigram: pass previous word when tracking position 2
          trackWordUsage(
            cleaned,
            position: position,
            previousWord: (position == 2) ? previousWord : null,
          );

          // Update previousWord for next iteration
          previousWord = cleaned;
        }
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

  /// Get word suggestions for a given input with position awareness
  /// Position: 1 = first word, 2 = second word, 3+ = other positions
  /// For position 2, can provide previousWord for context-aware bigram suggestions
  List<Word> getSuggestions(
    String input, {
    int limit = 12,
    int? position,
    String? previousWord,
  }) {
    if (input.isEmpty) {
      // Return most frequently used words for this position
      return _getMostUsedWordsForPosition(limit, position, previousWord: previousWord);
    }

    // Filter by prefix match and exclude numerals
    final matches = _vocabulary.values
        .where((word) => word.matches(input) && !RegExp(r'^\d+$').hasMatch(word.text))
        .toList();

    // Sort by position-specific usage score if position provided
    if (position != null) {
      matches.sort((a, b) => b
          .getPositionScore(position, previousWord: previousWord)
          .compareTo(a.getPositionScore(position, previousWord: previousWord)));
    } else {
      // Fall back to general usage score
      matches.sort((a, b) => b.score.compareTo(a.score));
    }

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

  /// Remove a word from vocabulary
  Future<void> removeWord(String wordText) async {
    final key = wordText.toLowerCase();
    _vocabulary.remove(key);
    await _saveVocabulary();
  }

  /// Record usage of a word (for manually adding words)
  Future<void> recordUsage(String wordText) async {
    trackWordUsage(wordText);
  }

  /// Import vocabulary from raw text with position tracking
  /// This will parse the text into sentences and track word positions
  Future<ImportStats> importFromText(
    String text, {
    int minFrequency = 1,
  }) async {
    int added = 0;
    int updated = 0;
    int skipped = 0;

    // Track word usage by position
    final Map<String, Map<int, int>> wordPositionCounts = {};

    // Track bigrams: map of "secondWord" -> {"firstWord" -> count}
    final Map<String, Map<String, int>> bigramCounts = {};

    // Split into sentences by common punctuation
    final sentences = text.split(RegExp(r'[.!?]+\s*'));

    for (final sent in sentences) {
      if (sent.trim().isEmpty) continue;

      // Track individual words with position and bigrams
      final words = sent.trim().split(RegExp(r'\s+'));
      String? previousWord;

      for (int i = 0; i < words.length; i++) {
        final cleaned = words[i].replaceAll(RegExp(r'[^\w]'), '');
        if (cleaned.isEmpty) continue;

        final key = cleaned.toLowerCase();

        // Skip numerals
        if (RegExp(r'^\d+$').hasMatch(key)) continue;

        // Position: 1 = first word, 2 = second word, 3+ = other
        final position = i == 0 ? 1 : (i == 1 ? 2 : 3);

        // Track position counts
        wordPositionCounts.putIfAbsent(key, () => {1: 0, 2: 0, 3: 0});
        wordPositionCounts[key]![position] = (wordPositionCounts[key]![position] ?? 0) + 1;

        // Track bigram for second word
        if (position == 2 && previousWord != null) {
          bigramCounts.putIfAbsent(key, () => {});
          bigramCounts[key]![previousWord] = (bigramCounts[key]![previousWord] ?? 0) + 1;
        }

        // Update previousWord for next iteration
        previousWord = cleaned.toLowerCase();
      }
    }

    // Apply to vocabulary
    for (final entry in wordPositionCounts.entries) {
      final word = entry.key;
      final positionCounts = entry.value;
      final totalFrequency = positionCounts.values.reduce((a, b) => a + b);

      // Skip if below minimum frequency
      if (totalFrequency < minFrequency) {
        skipped++;
        continue;
      }

      if (_vocabulary.containsKey(word)) {
        // Update existing word with position data
        final existingWord = _vocabulary[word]!;
        existingWord.firstWordCount += positionCounts[1] ?? 0;
        existingWord.secondWordCount += positionCounts[2] ?? 0;
        existingWord.otherWordCount += positionCounts[3] ?? 0;
        existingWord.usageCount += totalFrequency;
        existingWord.lastUsed = DateTime.now();

        // Update bigram data
        if (bigramCounts.containsKey(word)) {
          for (final bigramEntry in bigramCounts[word]!.entries) {
            final prevWord = bigramEntry.key;
            final count = bigramEntry.value;
            existingWord.followsWords[prevWord] =
                (existingWord.followsWords[prevWord] ?? 0) + count;
          }
        }

        updated++;
      } else {
        // Add new word with position data
        _vocabulary[word] = Word(
          text: word,
          phonetic: _generateSimplePhonetic(word),
          usageCount: totalFrequency,
          firstWordCount: positionCounts[1] ?? 0,
          secondWordCount: positionCounts[2] ?? 0,
          otherWordCount: positionCounts[3] ?? 0,
          lastUsed: DateTime.now(),
          followsWords: bigramCounts[word] ?? {},
        );
        added++;
      }
    }

    await _saveVocabulary();

    return ImportStats(
      added: added,
      updated: updated,
      skipped: skipped,
      total: wordPositionCounts.length,
    );
  }

  /// Import word usage from text analysis (frequency map only, no position data)
  /// This will add/update words in the vocabulary based on their frequency in the analyzed text
  Future<ImportStats> importFromTextAnalysis(
    Map<String, int> wordFrequencies, {
    bool overwriteExisting = false,
    int minFrequency = 1,
  }) async {
    int added = 0;
    int updated = 0;
    int skipped = 0;

    for (final entry in wordFrequencies.entries) {
      final word = entry.key;
      final frequency = entry.value;

      // Skip if below minimum frequency
      if (frequency < minFrequency) {
        skipped++;
        continue;
      }

      final key = word.toLowerCase();

      if (_vocabulary.containsKey(key)) {
        if (overwriteExisting) {
          // Update existing word with imported frequency
          final existingWord = _vocabulary[key]!;
          _vocabulary[key] = Word(
            text: existingWord.text,
            phonetic: existingWord.phonetic,
            usageCount: existingWord.usageCount + frequency,
            firstWordCount: existingWord.firstWordCount,
            secondWordCount: existingWord.secondWordCount,
            otherWordCount: existingWord.otherWordCount,
            lastUsed: DateTime.now(),
          );
          updated++;
        } else {
          // Just increment usage count
          for (var i = 0; i < frequency; i++) {
            _vocabulary[key]!.recordUsage();
          }
          updated++;
        }
      } else {
        // Add new word with imported frequency
        _vocabulary[key] = Word(
          text: word,
          phonetic: _generateSimplePhonetic(word),
          usageCount: frequency,
          lastUsed: DateTime.now(),
        );
        added++;
      }
    }

    await _saveVocabulary();

    return ImportStats(
      added: added,
      updated: updated,
      skipped: skipped,
      total: wordFrequencies.length,
    );
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

  /// Get most frequently used words for a specific position
  List<Word> _getMostUsedWordsForPosition(
    int limit,
    int? position, {
    String? previousWord,
  }) {
    // Filter out numerals
    final words = _vocabulary.values
        .where((word) => !RegExp(r'^\d+$').hasMatch(word.text))
        .toList();

    if (position != null) {
      // Sort by position-specific score (with context if provided)
      words.sort((a, b) => b
          .getPositionScore(position, previousWord: previousWord)
          .compareTo(a.getPositionScore(position, previousWord: previousWord)));
    } else {
      // Fall back to general usage score
      words.sort((a, b) => b.score.compareTo(a.score));
    }

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

/// Statistics from importing word usage data
class ImportStats {
  final int added; // New words added
  final int updated; // Existing words updated
  final int skipped; // Words skipped (below threshold)
  final int total; // Total words in import

  const ImportStats({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.total,
  });

  @override
  String toString() {
    return 'ImportStats(added: $added, updated: $updated, skipped: $skipped, total: $total)';
  }
}
