import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import '../../core/models/phrase.dart';
import '../../core/models/tts_request.dart';
import '../../core/services/audio_playback_service.dart';
import '../../core/services/tts_provider_manager.dart';
import '../../core/services/app_logger.dart';
import '../../core/services/error_handler.dart';
import '../../core/services/phrase_exclusion_tracker.dart';
import '../../core/utils/input_validator.dart';
import '../../core/constants/accessibility_constants.dart';
import '../../core/providers/tts_provider.dart';

/// Screen displaying quick phrases that can be spoken with one tap
class PhrasesScreen extends StatefulWidget {
  final TTSProviderManager providerManager;
  final AudioPlaybackService audioService;

  const PhrasesScreen({
    super.key,
    required this.providerManager,
    required this.audioService,
  });

  @override
  State<PhrasesScreen> createState() => _PhrasesScreenState();
}

class _PhrasesScreenState extends State<PhrasesScreen> {
  final AppLogger _logger = AppLogger('PhrasesScreen');
  final ErrorHandler _errorHandler = ErrorHandler();

  List<Phrase> _phrases = [];
  final Map<String, Uint8List?> _audioCache = {};
  final Map<String, String?> _audioCacheMimeTypes = {};
  final Map<String, int?> _audioCacheSampleRates = {};
  bool _isLoading = true;
  String? _currentlySpeaking;
  PhraseExclusionTracker? _exclusionTracker;

  @override
  void initState() {
    super.initState();
    _loadPhrases();
  }

  Future<void> _loadPhrases() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Initialize exclusion tracker
      _exclusionTracker = PhraseExclusionTracker(prefs);
      await _exclusionTracker!.initialize();

      // Load cached audio from persistent storage
      await _loadAudioCache();

      // Load default phrases from assets
      final String jsonString = await rootBundle.loadString('assets/default_phrases.json');
      final List<dynamic> defaultList = jsonDecode(jsonString);
      final defaultPhrases = defaultList.map((e) => e.toString()).toList();

      // Load custom phrases (user-added, not from defaults)
      final customPhrasesJson = prefs.getString('custom_phrases');
      List<String> customPhrases = [];

      if (customPhrasesJson != null) {
        final List<dynamic> customList = jsonDecode(customPhrasesJson);
        customPhrases = customList.map((e) => e.toString()).toList();
      }

      // Combine both lists, filtering out excluded phrases
      final allPhrases = <String>[];

      // Add default phrases that aren't excluded
      for (final phrase in defaultPhrases) {
        if (!_exclusionTracker!.isExcluded(phrase)) {
          allPhrases.add(phrase);
        }
      }

      // Add custom phrases
      allPhrases.addAll(customPhrases);

      // Load usage counts from preferences
      final usageJson = prefs.getString('phrase_usage');
      Map<String, int> usageCounts = {};

      if (usageJson != null) {
        final Map<String, dynamic> usage = jsonDecode(usageJson);
        usageCounts = usage.map((key, value) => MapEntry(key, value as int));
      }

      setState(() {
        _phrases = allPhrases
            .map((text) => Phrase(
                  text: text,
                  usageCount: usageCounts[text] ?? 0,
                ))
            .toList();

        // Sort by usage count descending
        _phrases.sort((a, b) => b.usageCount.compareTo(a.usageCount));

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Error loading phrases: ${e.toString()}');
    }
  }

  Future<void> _savePhrases() async {
    final prefs = await SharedPreferences.getInstance();

    // Load defaults to determine which are custom
    final String jsonString = await rootBundle.loadString('assets/default_phrases.json');
    final List<dynamic> defaultList = jsonDecode(jsonString);
    final defaultPhrases = defaultList.map((e) => e.toString()).toSet();

    // Only save custom (user-added) phrases
    final customPhrases = _phrases
        .map((p) => p.text)
        .where((text) => !defaultPhrases.contains(text))
        .toList();

    await prefs.setString('custom_phrases', jsonEncode(customPhrases));
  }

  /// Load audio cache from persistent storage
  Future<void> _loadAudioCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKeys = prefs.getKeys().where((key) => key.startsWith('phrase_audio_'));
    final corruptedKeys = <String>[];

    for (final key in cacheKeys) {
      final phraseText = key.substring('phrase_audio_'.length);
      final cacheJson = prefs.getString(key);
      if (cacheJson != null) {
        try {
          // Try to parse as JSON (new format with metadata)
          final cacheData = jsonDecode(cacheJson) as Map<String, dynamic>;
          final audioBase64 = cacheData['audioBase64'] as String?;
          final mimeType = cacheData['mimeType'] as String?;
          final sampleRate = cacheData['sampleRate'] as int?;

          if (audioBase64 != null) {
            _audioCache[phraseText] = base64Decode(audioBase64);
            _audioCacheMimeTypes[phraseText] = mimeType;
            _audioCacheSampleRates[phraseText] = sampleRate;
          } else {
            corruptedKeys.add(key);
          }
        } catch (e) {
          // Try old format (plain base64 string) - mark for removal
          try {
            base64Decode(cacheJson);
            _logger.info('Found old format cache for: $phraseText, will be regenerated');
            corruptedKeys.add(key);
          } catch (_) {
            _logger.warning('Failed to load cached audio for: $phraseText', error: e);
            corruptedKeys.add(key);
          }
        }
      }
    }

    // Clean up corrupted/old format entries
    if (corruptedKeys.isNotEmpty) {
      _logger.info('Cleaning up ${corruptedKeys.length} old/corrupted cache entries');
      for (final key in corruptedKeys) {
        await prefs.remove(key);
      }
    }
  }

  /// Save audio to persistent cache with metadata
  Future<void> _saveAudioToCache(
    String phraseText,
    Uint8List audioBytes, {
    String? mimeType,
    int? sampleRate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'audioBase64': base64Encode(audioBytes),
      'mimeType': mimeType,
      'sampleRate': sampleRate,
    };
    await prefs.setString('phrase_audio_$phraseText', jsonEncode(cacheData));
  }

  Future<void> _deletePhrase(Phrase phrase) async {
    // Check if this is a default phrase
    final String jsonString = await rootBundle.loadString('assets/default_phrases.json');
    final List<dynamic> defaultList = jsonDecode(jsonString);
    final defaultPhrases = defaultList.map((e) => e.toString()).toSet();

    final isDefault = defaultPhrases.contains(phrase.text);

    if (isDefault) {
      // Exclude default phrase (hide it)
      await _exclusionTracker?.exclude(phrase.text);
    } else {
      // Actually delete custom phrase
      await _savePhrases();
    }

    setState(() {
      _phrases.remove(phrase);
    });

    // Also remove from audio cache and metadata (both memory and persistent)
    _audioCache.remove(phrase.text);
    _audioCacheMimeTypes.remove(phrase.text);
    _audioCacheSampleRates.remove(phrase.text);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('phrase_audio_${phrase.text}');
  }

  Future<void> _addPhrase(String text) async {
    // Validate input
    final validation = InputValidator.validatePhraseInput(text);
    if (!validation.isValid) {
      _showError(validation.errorMessage ?? 'Invalid phrase');
      return;
    }

    final trimmed = text.trim();

    // Check if already exists
    if (_phrases.any((p) => p.text == trimmed)) {
      _showError('Phrase already exists');
      return;
    }

    setState(() {
      _phrases.insert(0, Phrase(text: trimmed, usageCount: 0));
    });
    await _savePhrases();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phrase added successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAddPhraseDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Phrase'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter phrase...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _addPhrase(controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Replay phrase with fresh audio (removes cache first)
  Future<void> _replayPhrase(Phrase phrase) async {
    if (widget.providerManager.activeProvider == null) {
      _showError('Please configure a TTS provider in settings first');
      return;
    }

    setState(() {
      _currentlySpeaking = phrase.text;
    });

    try {
      // Remove cached audio and metadata
      _audioCache.remove(phrase.text);
      _audioCacheMimeTypes.remove(phrase.text);
      _audioCacheSampleRates.remove(phrase.text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('phrase_audio_${phrase.text}');

      // Generate fresh audio using streaming if supported
      _logger.info('Generating fresh speech for: ${phrase.text}');

      final provider = widget.providerManager.activeProvider!;
      Uint8List audioBytes;
      String? mimeType;
      int? sampleRate;

      // Use streaming if supported (same logic as _speakPhrase)
      if (provider.supportsStreaming) {
        final stream = provider.generateSpeechStream(
          TTSRequest(text: phrase.text),
        );

        if (stream != null) {
          // Collect all chunks
          final chunks = <int>[];
          await for (final chunk in stream) {
            chunks.addAll(chunk);
          }
          audioBytes = Uint8List.fromList(chunks);

          // Determine MIME type based on provider
          if (provider.id == 'cartesia') {
            mimeType = 'audio/pcm';
            sampleRate = int.tryParse(provider.config['sampleRate'] ?? '44100') ?? 44100;
          } else if (provider.id == 'fish_audio' || provider.id == 'elevenlabs') {
            mimeType = 'audio/mpeg';
          }
        } else {
          // Fallback to non-streaming
          audioBytes = await widget.providerManager.generateSpeech(phrase.text);
        }
      } else {
        // Non-streaming
        audioBytes = await widget.providerManager.generateSpeech(phrase.text);
      }

      // Cache with metadata
      _audioCache[phrase.text] = audioBytes;
      _audioCacheMimeTypes[phrase.text] = mimeType;
      _audioCacheSampleRates[phrase.text] = sampleRate;

      // Save to persistent storage with metadata
      await _saveAudioToCache(phrase.text, audioBytes, mimeType: mimeType, sampleRate: sampleRate);
      _logger.debug('Cached fresh audio for: ${phrase.text}');

      await widget.audioService.play(audioBytes, mimeType: mimeType, sampleRate: sampleRate);

      // Track usage
      await _trackUsage(phrase);
    } on TTSProviderException catch (e, stackTrace) {
      _logger.error('TTS Provider Error', error: e, stackTrace: stackTrace);
      if (mounted) {
        _errorHandler.showErrorSnackbar(context, e, stackTrace: stackTrace);
      }
    } catch (e, stackTrace) {
      _logger.error('Unexpected error replaying phrase', error: e, stackTrace: stackTrace);
      if (mounted) {
        _errorHandler.showErrorSnackbar(context, e, stackTrace: stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _currentlySpeaking = null;
        });
      }
    }
  }

  /// Edit phrase - removes cache and returns to main screen with phrase in text box
  void _editPhrase(Phrase phrase) {
    // Remove cached audio and metadata
    _audioCache.remove(phrase.text);
    _audioCacheMimeTypes.remove(phrase.text);
    _audioCacheSampleRates.remove(phrase.text);
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('phrase_audio_${phrase.text}');
    });

    // Return to main screen with phrase text
    Navigator.pop(context, phrase.text);
  }

  /// Share cached audio file
  Future<void> _shareAudio(Phrase phrase) async {
    final cachedAudio = _audioCache[phrase.text];
    if (cachedAudio == null) {
      _showError('No audio available to share. Please play the phrase first.');
      return;
    }

    try {
      // Write audio to temporary file
      final tempDir = Directory.systemTemp;
      final extension = 'mp3'; // Default to mp3 for phrases
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'speaks_phrase_$timestamp.$extension';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(cachedAudio);

      // Share the file
      final xFile = XFile(tempFile.path);
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      await Share.shareXFiles(
        [xFile],
        subject: 'Phrase from Speaks',
        text: phrase.text,
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      _showError('Failed to share audio: ${e.toString()}');
    }
  }

  Future<void> _speakPhrase(Phrase phrase) async {
    if (widget.providerManager.activeProvider == null) {
      _showError('Please configure a TTS provider in settings first');
      return;
    }

    setState(() {
      _currentlySpeaking = phrase.text;
    });

    try {
      // Check cache first
      final cachedAudio = _audioCache[phrase.text];
      if (cachedAudio != null) {
        _logger.debug('Playing cached audio for: ${phrase.text}');
        final mimeType = _audioCacheMimeTypes[phrase.text];
        final sampleRate = _audioCacheSampleRates[phrase.text];
        await widget.audioService.play(cachedAudio, mimeType: mimeType, sampleRate: sampleRate);
      } else {
        // Generate and cache using streaming if supported (like main screen)
        _logger.info('Generating speech for: ${phrase.text}');

        final provider = widget.providerManager.activeProvider!;
        Uint8List audioBytes;
        String? mimeType;
        int? sampleRate;

        // Use streaming if supported for lower latency (same as main screen)
        if (provider.supportsStreaming) {
          final stream = provider.generateSpeechStream(
            TTSRequest(text: phrase.text),
          );

          if (stream != null) {
            // Collect all chunks
            final chunks = <int>[];
            await for (final chunk in stream) {
              chunks.addAll(chunk);
            }
            audioBytes = Uint8List.fromList(chunks);

            // Determine MIME type based on provider (same logic as main screen)
            if (provider.id == 'cartesia') {
              mimeType = 'audio/pcm';
              sampleRate = int.tryParse(provider.config['sampleRate'] ?? '44100') ?? 44100;
            } else if (provider.id == 'fish_audio' || provider.id == 'elevenlabs') {
              mimeType = 'audio/mpeg';
            }
          } else {
            // Fallback to non-streaming
            audioBytes = await widget.providerManager.generateSpeech(phrase.text);
          }
        } else {
          // Non-streaming
          audioBytes = await widget.providerManager.generateSpeech(phrase.text);
        }

        // Cache with metadata
        _audioCache[phrase.text] = audioBytes;
        _audioCacheMimeTypes[phrase.text] = mimeType;
        _audioCacheSampleRates[phrase.text] = sampleRate;

        // Save to persistent storage with metadata
        await _saveAudioToCache(phrase.text, audioBytes, mimeType: mimeType, sampleRate: sampleRate);
        _logger.debug('Cached audio for: ${phrase.text}');

        await widget.audioService.play(audioBytes, mimeType: mimeType, sampleRate: sampleRate);
      }

      // Track usage
      await _trackUsage(phrase);
    } on TTSProviderException catch (e, stackTrace) {
      _logger.error('TTS Provider Error', error: e, stackTrace: stackTrace);
      if (mounted) {
        _errorHandler.showErrorSnackbar(context, e, stackTrace: stackTrace);
      }
    } catch (e, stackTrace) {
      _logger.error('Unexpected error speaking phrase', error: e, stackTrace: stackTrace);
      if (mounted) {
        _errorHandler.showErrorSnackbar(context, e, stackTrace: stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _currentlySpeaking = null;
        });
      }
    }
  }

  Future<void> _trackUsage(Phrase phrase) async {
    final prefs = await SharedPreferences.getInstance();
    final usageJson = prefs.getString('phrase_usage');
    Map<String, int> usageCounts = {};

    if (usageJson != null) {
      final Map<String, dynamic> usage = jsonDecode(usageJson);
      usageCounts = usage.map((key, value) => MapEntry(key, value as int));
    }

    // Increment count
    usageCounts[phrase.text] = (usageCounts[phrase.text] ?? 0) + 1;
    await prefs.setString('phrase_usage', jsonEncode(usageCounts));

    // Update local state
    setState(() {
      final index = _phrases.indexWhere((p) => p.text == phrase.text);
      if (index != -1) {
        _phrases[index] = phrase.copyWith(usageCount: usageCounts[phrase.text]);
        // Re-sort by usage
        _phrases.sort((a, b) => b.usageCount.compareTo(a.usageCount));
      }
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Phrases'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Phrase',
            onPressed: _showAddPhraseDialog,
          ),
        ],
      ),
      body: _phrases.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No phrases loaded',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _phrases.map((phrase) {
                  return SizedBox(
                    width: (MediaQuery.of(context).size.width - 44) / 2, // 16 padding each side + 12 spacing
                    child: _buildPhraseButton(phrase),
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildPhraseButton(Phrase phrase) {
    final isSpeaking = _currentlySpeaking == phrase.text;
    final hasCache = _audioCache.containsKey(phrase.text);

    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isSpeaking ? null : () => _speakPhrase(phrase),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSpeaking
                  ? const Color(0xFF2563EB)
                  : Colors.grey[300]!,
              width: isSpeaking ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row with badges
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Usage count badge
                  if (phrase.usageCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${phrase.usageCount}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (phrase.usageCount > 0 && hasCache)
                    const SizedBox(width: 4),

                  // Cache indicator
                  if (hasCache)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),

              // Main content area with faint play icon
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Faint play icon background
                    Icon(
                      Icons.play_circle_outline,
                      size: 60,
                      color: Colors.grey.withValues(alpha: 0.1),
                    ),

                    // Text
                    isSpeaking
                        ? const CircularProgressIndicator()
                        : Text(
                            phrase.text,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E3A8A),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ],
                ),
              ),

              // Action buttons at bottom
              const Divider(height: 8),
              Row(
                children: [
                  // Edit button
                  Expanded(
                    child: _buildIconButton(
                      icon: Icons.edit,
                      color: const Color(0xFF2563EB),
                      onPressed: () => _editPhrase(phrase),
                      tooltip: 'Edit',
                    ),
                  ),

                  // Regenerate button
                  Expanded(
                    child: _buildIconButton(
                      icon: Icons.refresh,
                      color: const Color(0xFF2563EB),
                      onPressed: () => _replayPhrase(phrase),
                      tooltip: 'Regenerate',
                    ),
                  ),

                  // Share button (only if cached)
                  if (hasCache)
                    Expanded(
                      child: _buildIconButton(
                        icon: Icons.share,
                        color: const Color(0xFF2563EB),
                        onPressed: () => _shareAudio(phrase),
                        tooltip: 'Share',
                      ),
                    ),

                  // Delete button
                  Expanded(
                    child: _buildIconButton(
                      icon: Icons.delete_outline,
                      color: Colors.red[400]!,
                      onPressed: () => _confirmDeletePhrase(phrase),
                      tooltip: 'Delete',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color,
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints(
        minWidth: 36,
        minHeight: 36,
      ),
      padding: EdgeInsets.zero,
    );
  }

  void _showPhraseOptions(Phrase phrase) {
    final hasCache = _audioCache.containsKey(phrase.text);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF2563EB)),
              title: const Text('Edit in Text Box'),
              minVerticalPadding: AccessibilityConstants.comfortableSpacing,
              onTap: () {
                Navigator.pop(context);
                _editPhrase(phrase);
              },
            ),
            if (hasCache)
              ListTile(
                leading: const Icon(Icons.refresh, color: Color(0xFF2563EB)),
                title: const Text('Replay (Remove Cache)'),
                minVerticalPadding: AccessibilityConstants.comfortableSpacing,
                onTap: () {
                  Navigator.pop(context);
                  _replayPhrase(phrase);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete/Hide Phrase'),
              minVerticalPadding: AccessibilityConstants.comfortableSpacing,
              onTap: () {
                Navigator.pop(context);
                _confirmDeletePhrase(phrase);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Confirm before deleting phrase (motor impairment safety)
  Future<void> _confirmDeletePhrase(Phrase phrase) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Phrase?'),
        content: Text('Remove "${phrase.text}" from your quick phrases?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(
                AccessibilityConstants.minTapTargetSize,
                AccessibilityConstants.standardButtonHeight,
              ),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size(
                AccessibilityConstants.minTapTargetSize,
                AccessibilityConstants.standardButtonHeight,
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deletePhrase(phrase);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phrase deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
