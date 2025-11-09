import 'dart:io';

/// Analyzes text files for word usage patterns
class TextAnalyzer {
  /// Common English stop words that should be excluded from analysis
  static const Set<String> _stopWords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from',
    'has', 'he', 'in', 'is', 'it', 'its', 'of', 'on', 'that', 'the',
    'to', 'was', 'will', 'with', 'i', 'you', 'we', 'they', 'them',
    'this', 'but', 'had', 'have', 'can', 'could', 'would', 'should',
    'been', 'were', 'what', 'when', 'where', 'who', 'which', 'why',
    'how', 'all', 'each', 'every', 'both', 'few', 'more', 'most',
    'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own',
    'same', 'so', 'than', 'too', 'very', 's', 't', 'just', 'don',
    'now', 'there', 'my', 'your', 'our', 'their', 'his', 'her',
  };

  /// Analyze a text file and return word frequencies
  Future<TextAnalysisResult> analyzeFile(
    File file, {
    bool excludeStopWords = true,
    int minWordLength = 2,
    int maxWords = 1000,
  }) async {
    final content = await file.readAsString();
    return analyzeText(
      content,
      excludeStopWords: excludeStopWords,
      minWordLength: minWordLength,
      maxWords: maxWords,
    );
  }

  /// Analyze text content and return word frequencies
  TextAnalysisResult analyzeText(
    String text, {
    bool excludeStopWords = true,
    int minWordLength = 2,
    int maxWords = 1000,
  }) {
    // Tokenize: split on whitespace and punctuation, convert to lowercase
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Replace punctuation with spaces
        .split(RegExp(r'\s+')) // Split on whitespace
        .where((word) => word.isNotEmpty)
        .toList();

    // Count word frequencies
    final wordCounts = <String, int>{};
    for (final word in words) {
      // Apply filters
      if (word.length < minWordLength) continue;
      if (excludeStopWords && _stopWords.contains(word)) continue;

      wordCounts[word] = (wordCounts[word] ?? 0) + 1;
    }

    // Sort by frequency (descending)
    final sortedEntries = wordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Limit to maxWords
    final topWords = sortedEntries.take(maxWords).toList();

    return TextAnalysisResult(
      totalWords: words.length,
      uniqueWords: wordCounts.length,
      topWords: Map.fromEntries(topWords),
    );
  }

  /// Analyze multiple files and merge results
  Future<TextAnalysisResult> analyzeMultipleFiles(
    List<File> files, {
    bool excludeStopWords = true,
    int minWordLength = 2,
    int maxWords = 1000,
  }) async {
    final mergedCounts = <String, int>{};
    int totalWords = 0;

    for (final file in files) {
      final result = await analyzeFile(
        file,
        excludeStopWords: excludeStopWords,
        minWordLength: minWordLength,
        maxWords: 999999, // Don't limit individual files
      );

      totalWords += result.totalWords;

      // Merge word counts
      result.topWords.forEach((word, count) {
        mergedCounts[word] = (mergedCounts[word] ?? 0) + count;
      });
    }

    // Sort and limit
    final sortedEntries = mergedCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topWords = sortedEntries.take(maxWords).toList();

    return TextAnalysisResult(
      totalWords: totalWords,
      uniqueWords: mergedCounts.length,
      topWords: Map.fromEntries(topWords),
    );
  }
}

/// Result of text analysis
class TextAnalysisResult {
  final int totalWords;
  final int uniqueWords;
  final Map<String, int> topWords; // word -> frequency

  const TextAnalysisResult({
    required this.totalWords,
    required this.uniqueWords,
    required this.topWords,
  });

  /// Get top N words
  List<MapEntry<String, int>> getTopN(int n) {
    return topWords.entries.take(n).toList();
  }

  /// Get words with frequency >= threshold
  List<MapEntry<String, int>> getWordsWithMinFrequency(int threshold) {
    return topWords.entries.where((entry) => entry.value >= threshold).toList();
  }
}
