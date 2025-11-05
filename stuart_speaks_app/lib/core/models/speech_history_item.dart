import 'dart:typed_data';

/// Represents a history item with cached audio
class SpeechHistoryItem {
  final String text;
  final DateTime timestamp;
  final Uint8List? cachedAudio;
  final String? mimeType;
  final int? sampleRate;

  SpeechHistoryItem({
    required this.text,
    required this.timestamp,
    this.cachedAudio,
    this.mimeType,
    this.sampleRate,
  });

  /// Create a copy with updated fields
  SpeechHistoryItem copyWith({
    String? text,
    DateTime? timestamp,
    Uint8List? cachedAudio,
    String? mimeType,
    int? sampleRate,
  }) {
    return SpeechHistoryItem(
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      cachedAudio: cachedAudio ?? this.cachedAudio,
      mimeType: mimeType ?? this.mimeType,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }

  /// Get formatted timestamp for display
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Check if audio is cached
  bool get hasCache => cachedAudio != null;
}
