import 'dart:async';

import '../models/phrase.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline,
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final int phrasesAdded;
  final int phrasesRemoved;
  final int conflictsResolved;
  final String? errorMessage;
  final List<Phrase>? mergedPhrases;

  SyncResult({
    required this.success,
    this.phrasesAdded = 0,
    this.phrasesRemoved = 0,
    this.conflictsResolved = 0,
    this.errorMessage,
    this.mergedPhrases,
  });

  factory SyncResult.error(String message) {
    return SyncResult(success: false, errorMessage: message);
  }

  factory SyncResult.success({
    int added = 0,
    int removed = 0,
    int conflicts = 0,
    List<Phrase>? phrases,
  }) {
    return SyncResult(
      success: true,
      phrasesAdded: added,
      phrasesRemoved: removed,
      conflictsResolved: conflicts,
      mergedPhrases: phrases,
    );
  }
}

/// Service for synchronizing phrases with the server
class SyncService {
  final ApiClient _apiClient;
  final AuthService _authService;

  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncTime;
  final _statusController = StreamController<SyncStatus>.broadcast();

  SyncService({
    required ApiClient apiClient,
    required AuthService authService,
  })  : _apiClient = apiClient,
        _authService = authService;

  /// Current sync status
  SyncStatus get status => _status;

  /// Stream of sync status changes
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// Last successful sync time
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Check if sync is available (authenticated and server configured)
  bool get canSync =>
      _authService.isAuthenticated && _apiClient.isServerConfigured;

  void _setStatus(SyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  /// Fetch phrases from the server
  Future<List<String>?> fetchRemotePhrases() async {
    if (!canSync) return null;

    final response = await _apiClient.get('/api/phrases');

    if (response.isSuccess) {
      // Backend returns { success: true, phrases: [...] }
      final map = response.jsonMap;
      if (map != null && map['phrases'] is List) {
        final phrases = (map['phrases'] as List).map((e) => e.toString()).toList();
        return phrases;
      }
    }

    return null;
  }

  /// Push a new phrase to the server
  Future<bool> pushPhrase(String text) async {
    if (!canSync) return false;

    final response = await _apiClient.post(
      '/api/phrases',
      body: {'phrase': text.trim()},
    );

    return response.isSuccess;
  }

  /// Delete a phrase from the server
  Future<bool> deleteRemotePhrase(String text) async {
    if (!canSync) return false;

    // URL-encode the phrase text
    final encodedText = Uri.encodeComponent(text.trim());
    final response = await _apiClient.delete('/api/phrases/$encodedText');

    return response.isSuccess || response.isNotFound;
  }

  /// Sync phrases with the server
  /// Returns merged list of phrases with conflict resolution applied
  Future<SyncResult> syncPhrases(List<Phrase> localPhrases) async {
    if (!canSync) {
      return SyncResult.error('Not authenticated or server not configured');
    }

    _setStatus(SyncStatus.syncing);

    try {
      // Fetch remote phrases
      final remotePhrases = await fetchRemotePhrases();
      if (remotePhrases == null) {
        _setStatus(SyncStatus.error);
        return SyncResult.error('Failed to fetch remote phrases');
      }

      // Merge and resolve conflicts
      final mergeResult = _mergePhraseLists(localPhrases, remotePhrases);

      // Push local-only phrases to server
      for (final phrase in mergeResult.toAdd) {
        await pushPhrase(phrase.text);
      }

      _lastSyncTime = DateTime.now();
      _setStatus(SyncStatus.success);

      return SyncResult.success(
        added: mergeResult.fromRemote,
        conflicts: mergeResult.conflictsResolved,
        phrases: mergeResult.merged,
      );
    } catch (e) {
      _setStatus(SyncStatus.error);
      return SyncResult.error('Sync failed: $e');
    }
  }

  /// Merge local and remote phrase lists
  /// Conflict resolution: dedupe by text, sum usage counts
  _MergeResult _mergePhraseLists(
      List<Phrase> local, List<String> remoteTexts) {
    final merged = <String, Phrase>{};
    final toAdd = <Phrase>[]; // Phrases to push to server
    int fromRemote = 0;
    int conflictsResolved = 0;

    // Create set of remote texts for quick lookup
    final remoteSet = remoteTexts.map((t) => t.trim()).toSet();

    // Add all local phrases to merged map
    for (final phrase in local) {
      final normalizedText = phrase.text.trim();
      merged[normalizedText] = phrase;

      // If not on server, mark for upload
      if (!remoteSet.contains(normalizedText)) {
        toAdd.add(phrase);
      }
    }

    // Add remote phrases not in local
    for (final text in remoteTexts) {
      final normalizedText = text.trim();
      if (!merged.containsKey(normalizedText)) {
        // New from remote
        merged[normalizedText] = Phrase(
          text: normalizedText,
          usageCount: 0,
          lastModified: DateTime.now(),
        );
        fromRemote++;
      } else {
        // Exists in both - this is a "conflict" but we just keep local
        // Usage count conflict resolution would happen here if server tracked it
        conflictsResolved++;
      }
    }

    return _MergeResult(
      merged: merged.values.toList(),
      toAdd: toAdd,
      fromRemote: fromRemote,
      conflictsResolved: conflictsResolved,
    );
  }

  /// Dispose resources
  void dispose() {
    _statusController.close();
  }
}

class _MergeResult {
  final List<Phrase> merged;
  final List<Phrase> toAdd;
  final int fromRemote;
  final int conflictsResolved;

  _MergeResult({
    required this.merged,
    required this.toAdd,
    required this.fromRemote,
    required this.conflictsResolved,
  });
}
