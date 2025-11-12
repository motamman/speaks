/// Represents a word in the user's vocabulary with usage statistics
class Word {
  final String text;
  final String phonetic; // Simplified phonetic representation
  int usageCount;
  int firstWordCount; // How often used as first word in sentence
  int secondWordCount; // How often used as second word in sentence
  int otherWordCount; // How often used in other positions
  DateTime lastUsed;
  final List<String> categories;
  final String? customIcon;

  // Bigram tracking: maps previous word -> count of times this word followed it
  // e.g., for "am": {"I": 50, "you": 20} means "am" followed "I" 50 times, "you" 20 times
  Map<String, int> followsWords;

  Word({
    required this.text,
    required this.phonetic,
    this.usageCount = 0,
    this.firstWordCount = 0,
    this.secondWordCount = 0,
    this.otherWordCount = 0,
    DateTime? lastUsed,
    this.categories = const [],
    this.customIcon,
    Map<String, int>? followsWords,
  })  : lastUsed = lastUsed ?? DateTime.now(),
        followsWords = followsWords ?? {};

  /// Calculate priority score based on usage count and recency
  double get score => usageCount * _recencyMultiplier();

  double _recencyMultiplier() {
    final daysSinceUse = DateTime.now().difference(lastUsed).inDays;
    if (daysSinceUse < 7) return 1.2; // Recent boost
    if (daysSinceUse < 30) return 1.0; // Normal
    return 0.8; // Older words slightly demoted
  }

  /// Increment usage count and update last used timestamp
  void recordUsage({int? position, String? previousWord}) {
    usageCount++;
    lastUsed = DateTime.now();

    // Track position-specific usage
    if (position != null) {
      if (position == 1) {
        firstWordCount++;
      } else if (position == 2) {
        secondWordCount++;
        // Track bigram: this word follows previousWord
        if (previousWord != null) {
          final key = previousWord.toLowerCase();
          followsWords[key] = (followsWords[key] ?? 0) + 1;
        }
      } else {
        otherWordCount++;
      }
    }
  }

  /// Get count of how often this word follows a specific previous word
  int getFollowCount(String previousWord) {
    return followsWords[previousWord.toLowerCase()] ?? 0;
  }

  /// Get position-specific score for ranking suggestions
  /// For position 2, can provide previousWord for context-aware bigram scoring
  double getPositionScore(int position, {String? previousWord}) {
    double positionCount;
    if (position == 1) {
      positionCount = firstWordCount.toDouble();
    } else if (position == 2) {
      // For second word, prefer bigram statistics if available
      if (previousWord != null) {
        final bigramCount = getFollowCount(previousWord);
        if (bigramCount > 0) {
          // Use bigram count with high weight (prioritize context-specific usage)
          positionCount = bigramCount.toDouble() * 2.0;
        } else {
          // Fall back to general second-word usage
          positionCount = secondWordCount.toDouble();
        }
      } else {
        positionCount = secondWordCount.toDouble();
      }
    } else {
      positionCount = otherWordCount.toDouble();
    }

    // Combine position-specific count with recency
    return positionCount * _recencyMultiplier();
  }

  /// Check if this word matches a given input string (spelling-based)
  bool matches(String input) {
    final lowerInput = input.toLowerCase();
    return text.toLowerCase().startsWith(lowerInput) ||
        phonetic.toLowerCase().startsWith(lowerInput);
  }

  // JSON serialization
  Map<String, dynamic> toJson() => {
        'text': text,
        'phonetic': phonetic,
        'usageCount': usageCount,
        'firstWordCount': firstWordCount,
        'secondWordCount': secondWordCount,
        'otherWordCount': otherWordCount,
        'lastUsed': lastUsed.toIso8601String(),
        'categories': categories,
        'customIcon': customIcon,
        'followsWords': followsWords,
      };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        text: json['text'] as String,
        phonetic: json['phonetic'] as String,
        usageCount: json['usageCount'] as int? ?? 0,
        firstWordCount: json['firstWordCount'] as int? ?? 0,
        secondWordCount: json['secondWordCount'] as int? ?? 0,
        otherWordCount: json['otherWordCount'] as int? ?? 0,
        lastUsed: DateTime.parse(json['lastUsed'] as String),
        categories: (json['categories'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        customIcon: json['customIcon'] as String?,
        followsWords: (json['followsWords'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as int)) ??
            {},
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Word &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Word($text, usage: $usageCount)';
}
