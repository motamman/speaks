/// Repairs phrase text corrupted by a sync bug that stored stringified
/// server records ("{id: <uuid>, text: <phrase>}") as phrase text. Each sync
/// cycle nested the wrapper one level deeper, so recovery unwraps repeatedly.
class PhraseSanitizer {
  PhraseSanitizer._();

  static final RegExp _wrapper = RegExp(
    r'^\{id:\s*[0-9a-fA-F-]{8,},\s*text:\s*(.*)\}$',
    dotAll: true,
  );

  /// Whether [text] is a stringified server record rather than a real phrase.
  static bool isCorrupted(String text) => _wrapper.hasMatch(text.trim());

  /// Recovers the innermost real phrase from a corrupted wrapper.
  ///
  /// Text that never matched the wrapper shape is returned unchanged (trimmed)
  /// - a real phrase is never dropped just for containing unusual characters.
  /// Returns null only for text that matched the wrapper but holds no usable
  /// phrase inside (empty, or still record-shaped after unwrapping).
  static String? recover(String text) {
    var current = text.trim();
    var match = _wrapper.firstMatch(current);
    if (match == null) return current;
    while (match != null) {
      current = match.group(1)!.trim();
      match = _wrapper.firstMatch(current);
    }
    if (current.isEmpty || current.contains('{id:')) return null;
    return current;
  }

  /// Repairs a stored phrase list in one pass: recovers corrupted entries,
  /// drops unrecoverable ones, and removes duplicates while preserving order.
  /// The result records every rename and removal so callers can migrate data
  /// keyed by the old text (usage counts, cached audio).
  static PhraseRepairResult repairAll(Iterable<String> phrases) {
    final repaired = <String>[];
    final renamed = <String, String>{};
    final removed = <String>[];
    for (final text in phrases) {
      final clean = recover(text);
      if (clean == null || repaired.contains(clean)) {
        removed.add(text);
      } else {
        repaired.add(clean);
        if (clean != text) {
          renamed[text] = clean;
        }
      }
    }
    return PhraseRepairResult._(repaired, renamed, removed);
  }
}

/// Outcome of [PhraseSanitizer.repairAll].
class PhraseRepairResult {
  PhraseRepairResult._(this.phrases, this.renamed, this.removed);

  /// The cleaned list, in original order.
  final List<String> phrases;

  /// Entries whose text changed: original -> recovered.
  final Map<String, String> renamed;

  /// Entries dropped entirely (unrecoverable, or duplicates after repair).
  final List<String> removed;

  bool get changed => renamed.isNotEmpty || removed.isNotEmpty;
}
