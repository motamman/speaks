/// Utility class for chunking text into manageable pieces for TTS
class TextChunker {
  static const int minChunkLength = 50;
  static const int maxChunkLength = 100;

  /// Split text into chunks based on sentences
  static List<String> chunkText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];
    if (trimmed.length <= maxChunkLength) return [trimmed];

    // Split by sentences
    final sentences = _splitIntoSentences(trimmed);

    if (sentences.isEmpty) return [trimmed];
    if (sentences.length == 1) return [trimmed];

    return _combineIntoChunks(sentences);
  }

  /// Split text into sentences
  static List<String> _splitIntoSentences(String text) {
    // Match sentences ending with . ! ? followed by space or end of string
    final pattern = RegExp(r'[^.!?]+[.!?]+');
    final matches = pattern.allMatches(text);

    final sentences = matches
        .map((match) => match.group(0)?.trim())
        .where((s) => s != null && s.isNotEmpty)
        .map((s) => s!)
        .toList();

    // If no matches, return the whole text
    if (sentences.isEmpty) {
      return [text];
    }

    // Check if there's remaining text after the last sentence
    final lastMatchEnd = matches.isEmpty ? 0 : matches.last.end;
    if (lastMatchEnd < text.length) {
      final remainder = text.substring(lastMatchEnd).trim();
      if (remainder.isNotEmpty) {
        sentences.add(remainder);
      }
    }

    return sentences;
  }

  /// Combine sentences into chunks
  static List<String> _combineIntoChunks(List<String> sentences) {
    final chunks = <String>[];
    String currentChunk = '';

    for (final sentence in sentences) {
      final potentialChunk = currentChunk.isEmpty
          ? sentence
          : '$currentChunk $sentence';

      // Check if adding this sentence would exceed max length
      if (currentChunk.isNotEmpty &&
          potentialChunk.length > maxChunkLength &&
          currentChunk.length >= minChunkLength) {
        // Save current chunk and start new one
        chunks.add(currentChunk);
        currentChunk = sentence;
      } else {
        // Add sentence to current chunk
        currentChunk = potentialChunk;
      }
    }

    // Add the last chunk if not empty
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }

    // Handle case where first chunk is too short
    if (chunks.length > 1 && chunks[0].length < minChunkLength) {
      chunks[0] = '${chunks[0]} ${chunks[1]}';
      chunks.removeAt(1);
    }

    return chunks;
  }

  /// Check if text needs chunking
  static bool needsChunking(String text) {
    return text.trim().length > maxChunkLength;
  }

  /// Get estimated number of chunks
  static int estimateChunkCount(String text) {
    if (!needsChunking(text)) return 1;

    final sentences = _splitIntoSentences(text.trim());
    if (sentences.isEmpty) return 1;

    final chunks = _combineIntoChunks(sentences);
    return chunks.length;
  }
}
