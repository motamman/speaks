/// Model for a quick phrase that can be spoken
class Phrase {
  final String text;
  final String? category;
  final int usageCount;

  Phrase({
    required this.text,
    this.category,
    this.usageCount = 0,
  });

  Phrase copyWith({
    String? text,
    String? category,
    int? usageCount,
  }) {
    return Phrase(
      text: text ?? this.text,
      category: category ?? this.category,
      usageCount: usageCount ?? this.usageCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      if (category != null) 'category': category,
      'usageCount': usageCount,
    };
  }

  factory Phrase.fromJson(Map<String, dynamic> json) {
    return Phrase(
      text: json['text'] as String,
      category: json['category'] as String?,
      usageCount: json['usageCount'] as int? ?? 0,
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
