/// Represents a word in the user's vocabulary with usage statistics
class Word {
  final String text;
  final String phonetic; // Simplified phonetic representation
  int usageCount;
  DateTime lastUsed;
  final List<String> categories;
  final String? customIcon;

  Word({
    required this.text,
    required this.phonetic,
    this.usageCount = 0,
    DateTime? lastUsed,
    this.categories = const [],
    this.customIcon,
  }) : lastUsed = lastUsed ?? DateTime.now();

  /// Calculate priority score based on usage count and recency
  double get score => usageCount * _recencyMultiplier();

  double _recencyMultiplier() {
    final daysSinceUse = DateTime.now().difference(lastUsed).inDays;
    if (daysSinceUse < 7) return 1.2; // Recent boost
    if (daysSinceUse < 30) return 1.0; // Normal
    return 0.8; // Older words slightly demoted
  }

  /// Increment usage count and update last used timestamp
  void recordUsage() {
    usageCount++;
    lastUsed = DateTime.now();
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
        'lastUsed': lastUsed.toIso8601String(),
        'categories': categories,
        'customIcon': customIcon,
      };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        text: json['text'] as String,
        phonetic: json['phonetic'] as String,
        usageCount: json['usageCount'] as int? ?? 0,
        lastUsed: DateTime.parse(json['lastUsed'] as String),
        categories: (json['categories'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        customIcon: json['customIcon'] as String?,
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
