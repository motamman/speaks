import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/tts_request.dart';
import '../../core/models/word.dart';
import '../../core/models/speech_history_item.dart';
import '../../core/services/word_usage_tracker.dart';
import '../../core/services/audio_playback_service.dart';
import '../../core/services/tts_provider_manager.dart';
import '../../core/services/text_chunker.dart';
import '../../core/services/app_logger.dart';
import '../../core/services/error_handler.dart';
import '../../core/services/rate_limiter.dart';
import '../../core/utils/input_validator.dart';
import '../../core/constants/accessibility_constants.dart';
import '../../core/providers/tts_provider.dart';
import '../input/word_wheel/word_wheel_widget_v2.dart';
import '../settings/settings_screen.dart';
import '../phrases/phrases_screen.dart';

/// Main TTS screen with predictive word wheel
class TTSScreen extends StatefulWidget {
  const TTSScreen({super.key});

  @override
  State<TTSScreen> createState() => _TTSScreenState();
}

class _TTSScreenState extends State<TTSScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocus = FocusNode();
  final GlobalKey _textFieldKey = GlobalKey();
  final AppLogger _logger = AppLogger('TTSScreen');
  final ErrorHandler _errorHandler = ErrorHandler();
  late final RateLimiter _rateLimiter;

  WordUsageTracker? _usageTracker;
  AudioPlaybackService? _audioService;
  TTSProviderManager? _providerManager;
  List<Word> _currentSuggestions = [];
  List<SpeechHistoryItem> _speechHistory = [];
  bool _isLoading = true;
  bool _isSpeaking = false;
  bool _initializationFailed = false;
  String? _initializationError;
  static const int _maxHistoryItems = 10;

  @override
  void initState() {
    super.initState();
    _rateLimiter = RateLimiter(
      minimumDelay: const Duration(milliseconds: 500),
      logger: _logger,
    );
    _initialize();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textFieldFocus.dispose();
    _audioService?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Initialize usage tracker
      final tracker = WordUsageTracker(prefs);
      await tracker.initialize();
      _usageTracker = tracker;

      // Initialize audio service
      _audioService = AudioPlaybackService();

      // Initialize provider manager
      final providerManager = TTSProviderManager();
      await providerManager.loadSavedConfiguration();
      _providerManager = providerManager;

      if (mounted) {
        setState(() {
          _isLoading = false;
          _initializationFailed = false;
        });
      }

      _logger.info('Initialization completed successfully');
    } catch (e, stackTrace) {
      _logger.error('Initialization failed', error: e, stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _initializationFailed = true;
          _initializationError = 'Failed to initialize app. Please restart.';
        });
      }
    }
  }

  /// Reload the usage tracker to pick up newly imported vocabulary
  Future<void> _reloadUsageTracker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracker = WordUsageTracker(prefs);
      await tracker.initialize();
      _usageTracker = tracker;

      _logger.info('Usage tracker reloaded');
    } catch (e) {
      _logger.error('Failed to reload usage tracker', error: e);
    }
  }

  void _onTextChanged() {
    final tracker = _usageTracker;
    if (tracker == null) return;

    final text = _textController.text;
    final cursorPos = _textController.selection.baseOffset;

    // Get the current word being typed
    String currentWord = '';
    if (cursorPos > 0 && text.isNotEmpty) {
      final beforeCursor = text.substring(0, cursorPos);
      final words = beforeCursor.split(RegExp(r'\s+'));
      currentWord = words.isNotEmpty ? words.last : '';
    }

    setState(() {
      if (currentWord.isEmpty) {
        // No current word - clear suggestions
        _currentSuggestions = [];
      } else {
        // Show word suggestions for the current word
        _currentSuggestions = tracker.getSuggestions(currentWord);
      }
    });
  }

  void _onWordSelected(Word word) {
    final text = _textController.text;
    final cursorPos = _textController.selection.baseOffset;

    if (cursorPos == 0 || text.isEmpty) {
      // Insert at beginning
      _textController.text = '${word.text} ';
      _textController.selection = TextSelection.collapsed(
        offset: word.text.length + 1,
      );
    } else {
      // Replace current word
      final beforeCursor = text.substring(0, cursorPos);
      final afterCursor = text.substring(cursorPos);

      final words = beforeCursor.split(RegExp(r'\s+'));
      if (words.isNotEmpty) {
        words[words.length - 1] = word.text;
        final newBeforeCursor = '${words.join(' ')} ';
        final newText = newBeforeCursor + afterCursor;

        _textController.text = newText;
        _textController.selection = TextSelection.collapsed(
          offset: newBeforeCursor.length,
        );
      }
    }

    // Track word usage
    _usageTracker?.trackWordUsage(word.text);
  }

  Future<void> _onSpeak() async {
    final text = _textController.text.trim();

    // Validate input
    final validation = InputValidator.validateTTSInput(text);
    if (!validation.isValid) {
      _showError(validation.errorMessage ?? 'Invalid input');
      return;
    }

    // Check if services are initialized
    final providerManager = _providerManager;
    final audioService = _audioService;

    if (providerManager == null || audioService == null) {
      _showError('App not fully initialized. Please restart.');
      return;
    }

    // Check if provider is configured
    if (providerManager.activeProvider == null) {
      _showError('Please configure a TTS provider in settings first');
      return;
    }

    // Apply rate limiting
    if (!_rateLimiter.canPerform('speak')) {
      final waitTime = _rateLimiter.getRemainingWait('speak');
      _showError('Please wait ${(waitTime.inMilliseconds / 1000).toStringAsFixed(1)}s before speaking again');
      return;
    }

    setState(() {
      _isSpeaking = true;
    });

    try {
      await _rateLimiter.throttle('speak', () async {
        // Track sentence usage
        _usageTracker?.trackSentence(text);

        // Check if we need to chunk the text
        if (TextChunker.needsChunking(text)) {
          await _speakWithChunking(text);
        } else {
          await _speakSimple(text);
        }
      });

      // Clear text box after successful playback
      if (mounted) {
        _textController.clear();
      }
    } on TTSProviderException catch (e, stackTrace) {
      _logger.error('TTS Provider Error', error: e, stackTrace: stackTrace);
      if (mounted) {
        _errorHandler.showErrorSnackbar(context, e, stackTrace: stackTrace);
      }
    } catch (e, stackTrace) {
      _logger.error('Unexpected error during speech', error: e, stackTrace: stackTrace);
      if (mounted) {
        _errorHandler.showErrorSnackbar(context, e, stackTrace: stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  /// Speak text without chunking
  Future<void> _speakSimple(String text) async {
    final providerManager = _providerManager;
    final audioService = _audioService;

    if (providerManager == null || audioService == null) {
      throw StateError('Services not initialized');
    }

    final provider = providerManager.activeProvider;
    if (provider == null) {
      throw StateError('No active provider');
    }

    Uint8List? cachedAudio;
    String? mimeType;
    int? sampleRate;

    // Use streaming if supported for lower latency
    if (provider.supportsStreaming) {
      cachedAudio = await _speakWithStreaming(text);
      // Set mime type based on provider
      if (provider.id == 'cartesia') {
        mimeType = 'audio/pcm';
        sampleRate = int.tryParse(provider.config['sampleRate'] ?? '44100') ?? 44100;
      } else if (provider.id == 'fish_audio' || provider.id == 'elevenlabs') {
        mimeType = 'audio/mpeg';
      }
    } else {
      // Generate audio (non-streaming)
      cachedAudio = await providerManager.generateSpeech(text);
      // Play audio
      await audioService.play(cachedAudio);
    }

    // Add to history with cached audio
    _addToHistory(text, cachedAudio, mimeType, sampleRate);
  }

  /// Speak text with streaming (real-time audio)
  Future<Uint8List?> _speakWithStreaming(String text) async {
    final providerManager = _providerManager;
    final audioService = _audioService;

    if (providerManager == null || audioService == null) {
      throw StateError('Services not initialized');
    }

    final provider = providerManager.activeProvider;
    if (provider == null) {
      throw StateError('No active provider');
    }

    final stream = provider.generateSpeechStream(
      TTSRequest(text: text),
    );

    if (stream == null) {
      // Fallback to non-streaming
      final audioBytes = await providerManager.generateSpeech(text);
      await audioService.play(audioBytes);
      return audioBytes;
    }

    // Collect all chunks and concatenate
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
      _logger.debug('Streaming: received ${chunk.length} bytes, total: ${chunks.length}');
    }

    // Play complete audio
    if (chunks.isNotEmpty) {
      _logger.info('Streaming complete: ${chunks.length} total bytes');

      // Determine MIME type based on provider
      String? mimeType;
      int? sampleRate;

      if (provider.id == 'cartesia') {
        // Cartesia streams raw PCM
        mimeType = 'audio/pcm';
        sampleRate = int.tryParse(provider.config['sampleRate'] ?? '44100') ?? 44100;
      } else if (provider.id == 'fish_audio' || provider.id == 'elevenlabs') {
        // Fish.Audio and ElevenLabs stream MP3
        mimeType = 'audio/mpeg';
      }

      final audioBytes = Uint8List.fromList(chunks);
      await audioService.play(
        audioBytes,
        mimeType: mimeType,
        sampleRate: sampleRate,
      );
      return audioBytes;
    }

    return null;
  }

  /// Speak text with chunking for long sentences
  Future<void> _speakWithChunking(String text) async {
    final providerManager = _providerManager;
    final audioService = _audioService;

    if (providerManager == null || audioService == null) {
      throw StateError('Services not initialized');
    }

    final provider = providerManager.activeProvider;
    if (provider == null) {
      throw StateError('No active provider');
    }

    final chunks = TextChunker.chunkText(text);

    // Use streaming for each chunk if supported
    if (provider.supportsStreaming) {
      final audioChunks = <Uint8List>[];

      // Generate each chunk sequentially (better for rate limits)
      for (final chunk in chunks) {
        final stream = provider.generateSpeechStream(TTSRequest(text: chunk));

        if (stream != null) {
          final chunkData = <int>[];
          await for (final audioChunk in stream) {
            chunkData.addAll(audioChunk);
          }
          if (chunkData.isNotEmpty) {
            audioChunks.add(Uint8List.fromList(chunkData));
          }
        }
      }

      // Play all chunks in sequence
      // Determine MIME type based on provider
      String? mimeType;
      int? sampleRate;

      if (provider.id == 'cartesia') {
        // Cartesia streams raw PCM
        mimeType = 'audio/pcm';
        sampleRate = int.tryParse(provider.config['sampleRate'] ?? '44100') ?? 44100;
      } else if (provider.id == 'fish_audio' || provider.id == 'elevenlabs') {
        // Fish.Audio and ElevenLabs stream MP3
        mimeType = 'audio/mpeg';
      }

      // Combine all chunks into single audio
      if (audioChunks.isNotEmpty) {
        final combinedBytes = Uint8List.fromList(audioChunks.expand((x) => x).toList());
        await audioService.play(combinedBytes, mimeType: mimeType, sampleRate: sampleRate);
      }
    } else {
      // Fallback to concurrent generation for non-streaming providers
      final futures = chunks.map((chunk) => providerManager.generateSpeech(chunk));
      final audioChunks = await Future.wait(futures);

      // Combine and play
      if (audioChunks.isNotEmpty) {
        final combinedBytes = Uint8List.fromList(audioChunks.expand((x) => x).toList());
        await audioService.play(combinedBytes);
      }
    }
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

  /// Add item to speech history
  void _addToHistory(String text, Uint8List? audioBytes, String? mimeType, int? sampleRate) {
    setState(() {
      // Remove duplicate if exists
      _speechHistory.removeWhere((item) => item.text == text);

      // Add to beginning
      _speechHistory.insert(
        0,
        SpeechHistoryItem(
          text: text,
          timestamp: DateTime.now(),
          cachedAudio: audioBytes,
          mimeType: mimeType,
          sampleRate: sampleRate,
        ),
      );

      // Limit history size
      if (_speechHistory.length > _maxHistoryItems) {
        _speechHistory = _speechHistory.sublist(0, _maxHistoryItems);
      }
    });
  }

  /// Replay audio from history
  Future<void> _replayFromHistory(SpeechHistoryItem item) async {
    final audioService = _audioService;
    final cachedAudio = item.cachedAudio;

    if (cachedAudio == null || audioService == null) {
      _showError('No cached audio available');
      return;
    }

    setState(() {
      _isSpeaking = true;
    });

    try {
      await audioService.play(
        cachedAudio,
        mimeType: item.mimeType,
        sampleRate: item.sampleRate,
      );
    } catch (e, stackTrace) {
      _logger.error('Error playing cached audio', error: e, stackTrace: stackTrace);
      if (mounted) {
        _errorHandler.showErrorSnackbar(context, e, stackTrace: stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  /// Confirm before deleting item from history (motor impairment safety)
  Future<void> _confirmDeleteFromHistory(SpeechHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from History?'),
        content: Text('Remove "${item.text}" from your speech history?'),
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

    if (confirmed == true) {
      _deleteFromHistory(item);
    }
  }

  /// Delete item from history
  void _deleteFromHistory(SpeechHistoryItem item) {
    setState(() {
      _speechHistory.remove(item);
    });
  }

  /// Edit history item - removes cache and adds to text box
  void _editHistoryItem(SpeechHistoryItem item) {
    final currentText = _textController.text;
    if (currentText.isEmpty) {
      _textController.text = item.text;
    } else {
      // Append with space
      _textController.text = '$currentText ${item.text}';
    }
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
  }

  /// Add text to quick phrases
  Future<void> _addToQuickPhrases(String text, {Uint8List? cachedAudio}) async {
    final prefs = await SharedPreferences.getInstance();
    final customPhrasesJson = prefs.getString('custom_phrases');
    List<String> phrases = [];

    if (customPhrasesJson != null) {
      final List<dynamic> existingPhrases = jsonDecode(customPhrasesJson);
      phrases = existingPhrases.map((e) => e.toString()).toList();
    }

    // Check if already exists
    if (phrases.contains(text)) {
      _showError('Phrase already exists in Quick Phrases');
      return;
    }

    // Add to beginning of list
    phrases.insert(0, text);
    await prefs.setString('custom_phrases', jsonEncode(phrases));

    // If we have cached audio, save it to persistent storage
    if (cachedAudio != null) {
      final audioBase64 = base64Encode(cachedAudio);
      await prefs.setString('phrase_audio_$text', audioBase64);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to Quick Phrases'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
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

    // Show error screen if initialization failed
    if (_initializationFailed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Stuart Speaks'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Failed',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _initializationError ?? 'Failed to initialize app',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _initializationFailed = false;
                    });
                    _initialize();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Detect device type and orientation
    final mediaQuery = MediaQuery.of(context);
    final isTablet = mediaQuery.size.width >= 600;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return Scaffold(
      // Never resize - we handle keyboard manually
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/stuart.png',
              height: 40,
              width: 40,
            ),
            const SizedBox(width: 12),
            const Text('Stuart Speaks'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Quick Phrases',
            onPressed: _navigateToPhrasesScreen,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final providerManager = _providerManager;

              if (providerManager != null) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsScreen(
                      providerManager: providerManager,
                    ),
                  ),
                );
                // Reload usage tracker to pick up any imported vocabulary
                await _reloadUsageTracker();
                // Refresh state after returning from settings
                setState(() {});
              } else {
                _showError('App not fully initialized');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            // Detect swipe velocity to determine if it's a swipe gesture
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity!.abs() > 500) {
                // Velocity threshold met - navigate to phrases screen
                _navigateToPhrasesScreen();
              }
            }
          },
          child: isTablet
              ? (isLandscape ? _buildTabletLandscapeLayout() : _buildTabletPortraitLayout())
              : _buildPhoneLayout(),
        ),
      ),
    );
  }

  /// Navigate to phrases screen
  Future<void> _navigateToPhrasesScreen() async {
    final providerManager = _providerManager;
    final audioService = _audioService;

    if (providerManager != null && audioService != null) {
      final phraseToEdit = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => PhrasesScreen(
            providerManager: providerManager,
            audioService: audioService,
          ),
        ),
      );

      // If a phrase was selected for editing, add it to text box
      if (phraseToEdit != null && mounted) {
        final currentText = _textController.text;
        if (currentText.isEmpty) {
          _textController.text = phraseToEdit;
        } else {
          // Append with space
          _textController.text = '$currentText $phraseToEdit';
        }
        _textController.selection = TextSelection.collapsed(
          offset: _textController.text.length,
        );
      }
    } else {
      _showError('App not fully initialized');
    }
  }

  /// Phone layout - vertical stack (current layout)
  Widget _buildPhoneLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top 2/3 - Text entry and word wheel (NOT scrollable)
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text input area
              _buildInputArea(),

              // Word wheel - fills remaining space
              Expanded(
                child: Center(child: _buildWordWheel()),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Bottom 1/3 - Recent phrases (full width, scrollable)
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: _speechHistory.isEmpty
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: _buildPhrasesList(),
                  ),
          ),
        ),
      ],
    );
  }

  /// Tablet portrait layout - 2/3 top (text entry + wheel), 1/3 bottom (recent phrases)
  Widget _buildTabletPortraitLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top 2/3 - Text entry and word wheel (NOT scrollable)
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text input area
              _buildInputArea(),

              // Word wheel - fills remaining space
              Expanded(
                child: Center(child: _buildWordWheel()),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Bottom 1/3 - Recent phrases (full width, scrollable)
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: _speechHistory.isEmpty
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: _buildPhrasesList(),
                  ),
          ),
        ),
      ],
    );
  }

  /// Tablet landscape layout - 2/3 top (input full width), 1/3 bottom (wheel left, phrases right)
  Widget _buildTabletLandscapeLayout() {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final bottomSectionHeight = availableHeight * 0.33; // Fixed 1/3 of available space
        final topSectionHeight = keyboardHeight > 0
            ? availableHeight - keyboardHeight // With keyboard: fill space above keyboard
            : availableHeight * 0.67; // No keyboard: take 2/3

        return Stack(
          children: [
            // Top - Input area (shrinks when keyboard appears, stays visible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topSectionHeight,
              child: _buildInputArea(isLandscape: true),
            ),

            // Bottom - Wheel and Phrases (fixed at bottom, gets covered by keyboard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: bottomSectionHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Word wheel (left half) - centered in quadrant
                  Expanded(
                    child: Center(child: _buildWordWheel()),
                  ),

                  // Phrases list (right half) - flush left and top
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SingleChildScrollView(
                        child: _buildPhrasesList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Build input area with text field, suggestions, and speak button
  Widget _buildInputArea({bool isLandscape = false}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: isLandscape ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // Text field - expandable in landscape, fixed in portrait
          isLandscape
              ? Expanded(
                  child: TextField(
                    key: _textFieldKey,
                    controller: _textController,
                    focusNode: _textFieldFocus,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type here...',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.blue,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                )
              : TextField(
                  key: _textFieldKey,
                  controller: _textController,
                  focusNode: _textFieldFocus,
                  maxLines: 6,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type here...',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),

          // Word suggestions bar - always reserve space for consistent layout
          Container(
            margin: const EdgeInsets.only(top: 8),
            height: 50,
            child: _currentSuggestions.isNotEmpty
                ? ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _currentSuggestions.take(8).length,
                    itemBuilder: (context, index) {
                      final word = _currentSuggestions[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: 8.0,
                          left: index == 0 ? 0 : 0,
                        ),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          elevation: 2,
                          child: InkWell(
                            onTap: () => _onWordSelected(word),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: index == 0
                                      ? const Color(0xFF2563EB)
                                      : Colors.grey[300]!,
                                  width: index == 0 ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                word.text,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: index == 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: index == 0
                                      ? const Color(0xFF2563EB)
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(), // Empty space when no suggestions
          ),

          const SizedBox(height: 16),

          // Speak button
          SizedBox(
            width: double.infinity,
            height: 70,
            child: ElevatedButton(
              onPressed: _isSpeaking ? null : _onSpeak,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: _isSpeaking
                  ? const CircularProgressIndicator(
                      color: Colors.white,
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.volume_up, size: 32),
                        SizedBox(width: 12),
                        Text(
                          'SPEAK NOW',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build word wheel - scales to fill available area
  Widget _buildWordWheel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the size to fill the available space
        // Use the smaller dimension to maintain aspect ratio
        final size = constraints.maxHeight.isFinite && constraints.maxWidth.isFinite
            ? (constraints.maxHeight < constraints.maxWidth
                ? constraints.maxHeight
                : constraints.maxWidth) * 0.9  // 90% of available space for padding
            : 400.0;  // fallback size

        return SizedBox(
          width: size,
          height: size,
          child: WordWheelWidgetV2(
            words: _currentSuggestions.isEmpty
                ? (_usageTracker?.getSuggestions('', limit: 12) ?? [])
                : _currentSuggestions,
            onWordSelected: _onWordSelected,
            onWheelShown: () {},
            onWheelHidden: () {},
            alwaysVisible: true,
          ),
        );
      },
    );
  }

  /// Build phrases/history list
  Widget _buildPhrasesList() {
    if (_speechHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Text(
                  'Recent Phrases',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2563EB),
                        fontSize: 20,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_speechHistory.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _speechHistory.length,
            itemBuilder: (context, index) {
              return _buildHistoryItem(_speechHistory[index]);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(SpeechHistoryItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: item.hasCache ? () => _replayFromHistory(item) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Play button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item.hasCache
                        ? const Color(0xFF2563EB).withAlpha(25)
                        : Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    color: item.hasCache
                        ? const Color(0xFF2563EB)
                        : Colors.grey[400],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A8A),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            item.formattedTime,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (item.hasCache) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'cached',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Edit button
                IconButton(
                  icon: const Icon(
                    Icons.edit,
                    color: Color(0xFF2563EB),
                    size: AccessibilityConstants.standardIconSize,
                  ),
                  onPressed: () => _editHistoryItem(item),
                  constraints: AccessibleTapTarget.minimum(),
                  tooltip: 'Edit in text box',
                ),

                const SizedBox(width: AccessibilityConstants.minSpacing),

                // Add to Quick Phrases button
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFF2563EB),
                    size: AccessibilityConstants.standardIconSize,
                  ),
                  onPressed: () => _addToQuickPhrases(item.text, cachedAudio: item.cachedAudio),
                  constraints: AccessibleTapTarget.minimum(),
                  tooltip: 'Add to Quick Phrases',
                ),

                const SizedBox(width: AccessibilityConstants.minSpacing),

                // Delete button
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.grey[600],
                    size: AccessibilityConstants.standardIconSize,
                  ),
                  onPressed: () => _confirmDeleteFromHistory(item),
                  constraints: AccessibleTapTarget.minimum(),
                  tooltip: 'Delete from history',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
