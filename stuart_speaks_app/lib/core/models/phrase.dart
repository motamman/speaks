/// Model for a quick phrase that can be spoken
class Phrase {
  final String text;
  final String? category;
  final int usageCount;
  final DateTime? lastModified; // For sync tracking

  Phrase({
    required this.text,
    this.category,
    this.usageCount = 0,
    this.lastModified,
  });

  Phrase copyWith({
    String? text,
    String? category,
    int? usageCount,
    DateTime? lastModified,
  }) {
    return Phrase(
      text: text ?? this.text,
      category: category ?? this.category,
      usageCount: usageCount ?? this.usageCount,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  /// Create a copy with updated modification timestamp
  Phrase withUpdatedTimestamp() {
    return copyWith(lastModified: DateTime.now());
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      if (category != null) 'category': category,
      'usageCount': usageCount,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
    };
  }

  factory Phrase.fromJson(Map<String, dynamic> json) {
    DateTime? lastMod;
    if (json['lastModified'] != null) {
      try {
        lastMod = DateTime.parse(json['lastModified'] as String);
      } catch (_) {
        // Ignore invalid dates
      }
    }

    return Phrase(
      text: json['text'] as String,
      category: json['category'] as String?,
      usageCount: json['usageCount'] as int? ?? 0,
      lastModified: lastMod,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Phrase && other.text == text;
  }

  @override
  int get hashCode => text.hashCode;
}
