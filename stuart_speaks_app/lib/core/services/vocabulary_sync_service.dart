import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Service for synchronizing vocabulary with the server
class VocabularySyncService {
  static const String _vocabKey = 'user_vocabulary';
  static const String _historyKey = 'text_history';

  final ApiClient _apiClient;
  final AuthService _authService;
  final SharedPreferences _prefs;

  VocabularySyncService({
    required ApiClient apiClient,
    required AuthService authService,
    required SharedPreferences prefs,
  })  : _apiClient = apiClient,
        _authService = authService,
        _prefs = prefs;

  /// Check if sync is available
  bool get canSync =>
      _authService.isAuthenticated && _apiClient.isServerConfigured;

  /// Upload vocabulary to server
  Future<bool> uploadVocabulary() async {
    if (!canSync) return false;

    try {
      final vocabJson = _prefs.getString(_vocabKey);
      final historyJson = _prefs.getString(_historyKey);

      final data = {
        'vocabulary': vocabJson != null ? jsonDecode(vocabJson) : {},
        'textHistory': historyJson != null ? jsonDecode(historyJson) : [],
      };

      final response = await _apiClient.post('/api/vocabulary', body: data);
      return response.isSuccess;
    } catch (e) {
      return false;
    }
  }

  /// Download vocabulary from server
  Future<bool> downloadVocabulary() async {
    if (!canSync) return false;

    try {
      final response = await _apiClient.get('/api/vocabulary');

      if (!response.isSuccess) return false;

      final data = response.jsonMap;
      if (data == null) return false;

      // Save vocabulary
      if (data['vocabulary'] != null) {
        await _prefs.setString(_vocabKey, jsonEncode(data['vocabulary']));
      }

      // Save history
      if (data['textHistory'] != null) {
        await _prefs.setString(_historyKey, jsonEncode(data['textHistory']));
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sync vocabulary - merge local and remote, upload merged result
  Future<SyncVocabResult> syncVocabulary() async {
    if (!canSync) {
      return SyncVocabResult.error('Not authenticated');
    }

    try {
      // Get local vocabulary
      final localVocabJson = _prefs.getString(_vocabKey);
      final localHistoryJson = _prefs.getString(_historyKey);

      Map<String, dynamic> localVocab = {};
      List<String> localHistory = [];

      if (localVocabJson != null) {
        localVocab = Map<String, dynamic>.from(jsonDecode(localVocabJson));
      }
      if (localHistoryJson != null) {
        localHistory = List<String>.from(jsonDecode(localHistoryJson));
      }

      // Get remote vocabulary
      final response = await _apiClient.get('/api/vocabulary');

      Map<String, dynamic> remoteVocab = {};
      List<String> remoteHistory = [];

      if (response.isSuccess && response.jsonMap != null) {
        final data = response.jsonMap!;
        if (data['vocabulary'] != null) {
          remoteVocab = Map<String, dynamic>.from(data['vocabulary']);
        }
        if (data['textHistory'] != null) {
          remoteHistory = List<String>.from(data['textHistory']);
        }
      } else {
      }

      // Merge vocabularies
      final mergedVocab = _mergeVocabularies(localVocab, remoteVocab);

      // Merge histories (dedupe, keep most recent first)
      final mergedHistory = _mergeHistories(localHistory, remoteHistory);

      // Save merged locally
      await _prefs.setString(_vocabKey, jsonEncode(mergedVocab));
      await _prefs.setString(_historyKey, jsonEncode(mergedHistory));

      // Upload merged to server
      final uploadData = {
        'vocabulary': mergedVocab,
        'textHistory': mergedHistory,
      };
      final uploadResponse = await _apiClient.post('/api/vocabulary', body: uploadData);

      return SyncVocabResult.success(
        wordsAdded: mergedVocab.length - localVocab.length,
        wordsMerged: _countMergedWords(localVocab, remoteVocab),
      );
    } catch (e) {
      return SyncVocabResult.error('Sync failed: $e');
    }
  }

  /// Merge two vocabulary maps, summing usage counts
  Map<String, dynamic> _mergeVocabularies(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final merged = Map<String, dynamic>.from(local);

    for (final entry in remote.entries) {
      final key = entry.key;
      final remoteWord = entry.value as Map<String, dynamic>;

      if (merged.containsKey(key)) {
        // Merge existing word - sum usage counts
        final localWord = merged[key] as Map<String, dynamic>;
        merged[key] = _mergeWordData(localWord, remoteWord);
      } else {
        // New word from remote
        merged[key] = remoteWord;
      }
    }

    return merged;
  }

  /// Merge word data, summing counts
  Map<String, dynamic> _mergeWordData(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final merged = Map<String, dynamic>.from(local);

    // Sum usage count
    final localCount = (local['usageCount'] as num?) ?? 0;
    final remoteCount = (remote['usageCount'] as num?) ?? 0;
    merged['usageCount'] = localCount + remoteCount;

    // Sum position counts
    merged['firstWordCount'] =
        ((local['firstWordCount'] as num?) ?? 0) +
        ((remote['firstWordCount'] as num?) ?? 0);
    merged['secondWordCount'] =
        ((local['secondWordCount'] as num?) ?? 0) +
        ((remote['secondWordCount'] as num?) ?? 0);
    merged['otherWordCount'] =
        ((local['otherWordCount'] as num?) ?? 0) +
        ((remote['otherWordCount'] as num?) ?? 0);

    // Merge followsWords (bigrams)
    final localFollows = (local['followsWords'] as Map<String, dynamic>?) ?? {};
    final remoteFollows = (remote['followsWords'] as Map<String, dynamic>?) ?? {};
    final mergedFollows = Map<String, dynamic>.from(localFollows);

    for (final entry in remoteFollows.entries) {
      mergedFollows[entry.key] =
          ((mergedFollows[entry.key] as num?) ?? 0) + (entry.value as num);
    }
    merged['followsWords'] = mergedFollows;

    // Keep most recent lastUsed
    final localLastUsed = local['lastUsed'] as String?;
    final remoteLastUsed = remote['lastUsed'] as String?;
    if (localLastUsed != null && remoteLastUsed != null) {
      final localDate = DateTime.tryParse(localLastUsed);
      final remoteDate = DateTime.tryParse(remoteLastUsed);
      if (localDate != null && remoteDate != null) {
        merged['lastUsed'] = localDate.isAfter(remoteDate)
            ? localLastUsed
            : remoteLastUsed;
      }
    }

    return merged;
  }

  /// Merge text histories, deduplicating
  List<String> _mergeHistories(List<String> local, List<String> remote) {
    final seen = <String>{};
    final merged = <String>[];

    // Add local first (more recent)
    for (final text in local) {
      if (!seen.contains(text)) {
        seen.add(text);
        merged.add(text);
      }
    }

    // Add remote items not in local
    for (final text in remote) {
      if (!seen.contains(text)) {
        seen.add(text);
        merged.add(text);
      }
    }

    // Limit to 50 items
    if (merged.length > 50) {
      return merged.sublist(0, 50);
    }

    return merged;
  }

  int _countMergedWords(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    int count = 0;
    for (final key in remote.keys) {
      if (local.containsKey(key)) {
        count++;
      }
    }
    return count;
  }
}

class SyncVocabResult {
  final bool success;
  final int wordsAdded;
  final int wordsMerged;
  final String? errorMessage;

  SyncVocabResult._({
    required this.success,
    this.wordsAdded = 0,
    this.wordsMerged = 0,
    this.errorMessage,
  });

  factory SyncVocabResult.success({int wordsAdded = 0, int wordsMerged = 0}) {
    return SyncVocabResult._(
      success: true,
      wordsAdded: wordsAdded,
      wordsMerged: wordsMerged,
    );
  }

  factory SyncVocabResult.error(String message) {
    return SyncVocabResult._(success: false, errorMessage: message);
  }
}
