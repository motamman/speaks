import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import 'package:path_provider/path_provider.dart';

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
import '../../core/services/user_profile_service.dart';
import '../../core/services/input_method_service.dart';
import '../../core/services/vocabulary_sync_service.dart';
import '../../core/services/api_client.dart';
import '../../core/services/auth_service.dart';
import '../../core/config/server_config.dart';
import '../../core/utils/input_validator.dart';
import '../../core/constants/accessibility_constants.dart';
import '../../core/providers/tts_provider.dart';
import '../input/word_wheel/word_wheel_widget_v2.dart';
import '../input/spinner_keyboard/spinner_keyboard_widget.dart';
import '../settings/main_settings_screen.dart';
import '../phrases/phrases_screen.dart';
import 'sentence_input_formatter.dart';

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
  UserProfileService? _profileService;
  InputMethodService? _inputMethodService;
  VocabularySyncService? _vocabSyncService;
  RateLimiter? _vocabSyncLimiter;
  List<Word> _currentSuggestions = [];
  int _currentPosition = 1; // Track current word position for color coding
  String? _currentPreviousWord; // Track previous word for bigram detection
  List<SpeechHistoryItem> _speechHistory = [];
  bool _isLoading = true;
  bool _isSpeaking = false;
  bool _initializationFailed = false;
  String? _initializationError;
  InputMethod _inputMethod = InputMethod.wordWheel;
  bool _disableSystemKeyboard = false;
  InputMode _inputMode = InputMode.typeOnly;
  late final SentenceInputFormatter _sentenceFormatter;
  DateTime _lastEnterSubmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _historyExpanded = false;
  static const int _maxHistoryItems = 10;
  static final Map<LogicalKeyboardKey, int> _fKeyIndex = {
    LogicalKeyboardKey.f1: 0,
    LogicalKeyboardKey.f2: 1,
    LogicalKeyboardKey.f3: 2,
    LogicalKeyboardKey.f4: 3,
    LogicalKeyboardKey.f5: 4,
    LogicalKeyboardKey.f6: 5,
    LogicalKeyboardKey.f7: 6,
    LogicalKeyboardKey.f8: 7,
    LogicalKeyboardKey.f9: 8,
    LogicalKeyboardKey.f10: 9,
    LogicalKeyboardKey.f11: 10,
    LogicalKeyboardKey.f12: 11,
  };

  @override
  void initState() {
    super.initState();
    _rateLimiter = RateLimiter(
      minimumDelay: const Duration(milliseconds: 500),
      logger: _logger,
    );
    _sentenceFormatter = SentenceInputFormatter(onEnterDetected: _submitFromEnter);
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

      // Initialize user profile service
      _profileService = UserProfileService(prefs);

      // Initialize input method service
      _inputMethodService = InputMethodService(prefs);
      _inputMethod = _inputMethodService!.getInputMethod();
      _disableSystemKeyboard = _inputMethodService!.isSystemKeyboardDisabled();
      _inputMode = _inputMethodService!.getInputMode();

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

      // Initialize sync services and perform startup sync
      await _initializeSyncServices(prefs);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _initializationFailed = false;
        });
        // Populate initial suggestions so the type-only grid (and F1-F12
        // shortcuts) work before the first keystroke.
        _onTextChanged();
        if (_inputMode == InputMode.typeOnly) {
          _textFieldFocus.requestFocus();
        }
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

  /// Reload the usage tracker and settings to pick up changes
  Future<void> _reloadUsageTracker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracker = WordUsageTracker(prefs);
      await tracker.initialize();
      _usageTracker = tracker;

      // Also reload input method setting in case it changed
      _inputMethodService = InputMethodService(prefs);
      final newInputMethod = _inputMethodService!.getInputMethod();
      final newDisableKeyboard = _inputMethodService!.isSystemKeyboardDisabled();
      final newInputMode = _inputMethodService!.getInputMode();
      if (newInputMethod != _inputMethod ||
          newDisableKeyboard != _disableSystemKeyboard ||
          newInputMode != _inputMode) {
        setState(() {
          _inputMethod = newInputMethod;
          _disableSystemKeyboard = newDisableKeyboard;
          _inputMode = newInputMode;
        });
      }
      if (mounted && newInputMode == InputMode.typeOnly) {
        _textFieldFocus.requestFocus();
      }

      _logger.info('Usage tracker and settings reloaded');
    } catch (e) {
      _logger.error('Failed to reload usage tracker', error: e);
    }
  }

  /// Initialize sync services and perform startup sync
  Future<void> _initializeSyncServices(SharedPreferences prefs) async {
    try {
      final serverConfig = ServerConfig(prefs);
      if (!serverConfig.isConfigured) {
        _logger.debug('Server not configured, skipping sync');
        return;
      }

      final apiClient = ApiClient(serverConfig: serverConfig);
      await apiClient.initialize();
      final authService = AuthService(
        apiClient: apiClient,
        serverConfig: serverConfig,
      );
      await authService.checkAuthStatus();

      if (!authService.isAuthenticated) {
        _logger.debug('Not authenticated, skipping sync');
        return;
      }

      // Initialize vocab sync service for use during speaking
      _vocabSyncService = VocabularySyncService(
        apiClient: apiClient,
        authService: authService,
        prefs: prefs,
      );

      // Initialize rate limiter for debounced vocab sync (5 second delay)
      _vocabSyncLimiter = RateLimiter(
        minimumDelay: const Duration(seconds: 5),
        logger: _logger,
      );

      // Perform startup sync - download vocabulary from server
      _logger.info('Performing startup vocabulary sync...');
      final result = await _vocabSyncService!.syncVocabulary();
      if (result.success) {
        _logger.info('Startup sync complete: ${result.wordsAdded} words added, ${result.wordsMerged} merged');
        // Reload tracker with synced data
        await _usageTracker?.reload();
      } else {
        _logger.warning('Startup sync failed: ${result.errorMessage}');
      }
    } catch (e) {
      _logger.error('Failed to initialize sync services', error: e);
    }
  }

  /// Upload vocabulary to server with debouncing (5 second delay)
  void _uploadVocabularyDebounced() {
    if (_vocabSyncService == null || !_vocabSyncService!.canSync) return;
    if (_vocabSyncLimiter == null) return;

    _vocabSyncLimiter!.throttle('vocab_upload', () async {
      _logger.debug('Uploading vocabulary to server...');
      final success = await _vocabSyncService!.uploadVocabulary();
      if (success) {
        _logger.debug('Vocabulary uploaded successfully');
      } else {
        _logger.warning('Failed to upload vocabulary');
      }
    });
  }

  void _onTextChanged() {
    final tracker = _usageTracker;
    if (tracker == null) return;

    final text = _textController.text;
    var cursorPos = _textController.selection.baseOffset;

    // Handle invalid cursor position
    if (cursorPos < 0 || cursorPos > text.length) {
      cursorPos = text.length;
    }

    // Get the current word being typed
    String currentWord = '';
    if (cursorPos > 0 && text.isNotEmpty) {
      final beforeCursor = text.substring(0, cursorPos);
      final words = beforeCursor.split(RegExp(r'\s+'));
      currentWord = words.isNotEmpty ? words.last : '';
    }

    // Detect word position in current sentence
    final position = _detectWordPosition(text, cursorPos);

    // For all positions except 1, extract the previous word for context-aware suggestions
    String? previousWord;
    if (position > 1) {
      previousWord = _extractPreviousWord(text, cursorPos);
    }

    setState(() {
      _currentPosition = position;
      _currentPreviousWord = previousWord;

      if (currentWord.isEmpty) {
        // No current word - show position-based suggestions
        _currentSuggestions = tracker.getSuggestions(
          '',
          limit: 12,
          position: position,
          previousWord: previousWord,
        );
      } else {
        // Show word suggestions for the current word with position awareness
        _currentSuggestions = tracker.getSuggestions(
          currentWord,
          limit: 12,
          position: position,
          previousWord: previousWord,
        );
      }
    });
  }

  /// Detect word position in current sentence
  /// Returns: 1 = first word, 2 = second word, 3 = third+ word
  int _detectWordPosition(String text, int cursorPos) {
    // Validate cursor position (should be done by caller, but double-check)
    if (cursorPos < 0 || cursorPos > text.length) {
      cursorPos = text.length;
    }

    if (text.isEmpty || cursorPos == 0) {
      return 1; // First word (empty text box)
    }

    final beforeCursor = text.substring(0, cursorPos);

    // Find the start of the current sentence by looking for sentence-ending punctuation
    final sentenceStarts = RegExp(r'[.!?]\s*');
    int sentenceStartPos = 0;

    // Find last occurrence of sentence-ending punctuation before cursor
    final matches = sentenceStarts.allMatches(beforeCursor);
    if (matches.isNotEmpty) {
      final lastMatch = matches.last;
      sentenceStartPos = lastMatch.end; // Position after punctuation and space
    }

    // Extract current sentence (from last punctuation to cursor)
    final currentSentenceRaw = beforeCursor.substring(sentenceStartPos);
    final endsWithSpace = currentSentenceRaw.endsWith(' ');
    final currentSentence = currentSentenceRaw.trim();

    if (currentSentence.isEmpty) {
      return 1; // Start of new sentence
    }

    // Count words in current sentence
    final words = currentSentence.split(RegExp(r'\s+'));
    final wordCount = words.where((w) => w.isNotEmpty).length;

    // Return position: 1 = first, 2 = second, 3+ = other
    if (wordCount == 0) {
      return 1;
    } else if (wordCount == 1) {
      // If typing first word or just finished first word
      return endsWithSpace ? 2 : 1;
    } else if (wordCount == 2) {
      // If typing second word or just finished second word
      return endsWithSpace ? 3 : 2;
    } else {
      return 3; // Third word or beyond
    }
  }

  /// Extract the previous word from the current sentence (word immediately before cursor)
  /// Returns null if no previous word can be found
  String? _extractPreviousWord(String text, int cursorPos) {
    if (text.isEmpty || cursorPos == 0) {
      return null;
    }

    final beforeCursor = text.substring(0, cursorPos);

    // Find the start of the current sentence
    final sentenceStarts = RegExp(r'[.!?]\s*');
    int sentenceStartPos = 0;

    final matches = sentenceStarts.allMatches(beforeCursor);
    if (matches.isNotEmpty) {
      final lastMatch = matches.last;
      sentenceStartPos = lastMatch.end;
    }

    // Extract current sentence
    final currentSentence = beforeCursor.substring(sentenceStartPos).trim();

    if (currentSentence.isEmpty) {
      return null;
    }

    // Get all words (clean them from punctuation)
    final words = currentSentence.split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return null;
    }

    // Return the last complete word (previous word before current typing)
    // If currently typing a word, return the word before it
    // If just finished a word (ends with space), return that last word
    if (words.length >= 2 && !beforeCursor.substring(sentenceStartPos).endsWith(' ')) {
      // Currently typing, return second-to-last word
      return words[words.length - 2];
    } else if (words.isNotEmpty && beforeCursor.substring(sentenceStartPos).endsWith(' ')) {
      // Just finished a word, return the last complete word
      return words.last;
    } else if (words.length == 1) {
      // Only one word so far
      return words.first;
    }

    return null;
  }

  /// Get subtle background color for word button based on match type
  Color _getWordButtonColor(Word word) {
    // Check for bigram match (context-aware) - all positions except 1
    if (_currentPosition > 1 && _currentPreviousWord != null) {
      final bigramCount = word.getFollowCount(_currentPreviousWord!);
      if (bigramCount > 0) {
        return const Color(0xFFE3F2FD); // Light blue - bigram match
      }
    }

    // Check position-specific matches
    if (_currentPosition == 1 && word.firstWordCount > 0) {
      return const Color(0xFFFFF3E0); // Light amber - 1st word match
    } else if (_currentPosition == 2 && word.secondWordCount > 0) {
      return const Color(0xFFE8F5E9); // Light green - 2nd word match
    } else if (_currentPosition == 3 && word.otherWordCount > 0) {
      return const Color(0xFFF3E5F5); // Light purple - 3rd+ word match
    }

    // Default - general match (no position-specific data)
    return Colors.white;
  }

  /// Called when spinner keyboard completes a string
  void _onSpinnerKeyboardComplete(String text) {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final currentText = _textController.text;
    var cursorPos = _textController.selection.baseOffset;

    // Handle invalid cursor position
    if (cursorPos < 0 || cursorPos > currentText.length) {
      cursorPos = currentText.length;
    }

    // Detect position before inserting
    final position = _detectWordPosition(currentText, cursorPos);

    // Extract previousWord for tracking
    String? previousWord;
    if (position > 1) {
      previousWord = _extractPreviousWord(currentText, cursorPos);
    }

    if (cursorPos == 0 || currentText.isEmpty) {
      // Insert at beginning
      _textController.text = '$text ';
      _textController.selection = TextSelection.collapsed(
        offset: text.length + 1,
      );
    } else {
      // Replace current word or append
      final beforeCursor = currentText.substring(0, cursorPos);
      final afterCursor = currentText.substring(cursorPos);

      final words = beforeCursor.split(RegExp(r'\s+'));
      if (words.isNotEmpty && !beforeCursor.endsWith(' ')) {
        // Replace current partial word
        words[words.length - 1] = text;
        final newBeforeCursor = '${words.join(' ')} ';
        final newText = newBeforeCursor + afterCursor;

        _textController.text = newText;
        _textController.selection = TextSelection.collapsed(
          offset: newBeforeCursor.length,
        );
      } else {
        // Append after space - avoid double spaces
        final needsSpace = !beforeCursor.endsWith(' ');
        final prefix = needsSpace ? '$beforeCursor ' : beforeCursor;
        final afterTrimmed = afterCursor.startsWith(' ') ? afterCursor.substring(1) : afterCursor;
        final newText = '$prefix$text ${afterTrimmed.isEmpty ? '' : afterTrimmed}';
        final trimmedNewText = newText.trimRight().isEmpty ? newText : '${newText.trimRight()} ';
        _textController.text = trimmedNewText.replaceAll(RegExp(r' {2,}'), ' '); // Collapse multiple spaces
        _textController.selection = TextSelection.collapsed(
          offset: prefix.length + text.length + 1,
        );
      }
    }

    // Track word usage
    _usageTracker?.trackWordUsage(
      text,
      position: position,
      previousWord: previousWord,
    );
  }

  void _onWordSelected(Word word) {
    if (_inputMode == InputMode.typeOnly) {
      // Keep focus so the hardware keyboard can continue typing / using F-keys
      _textFieldFocus.requestFocus();
    } else {
      // Dismiss keyboard when selecting a word
      FocusScope.of(context).unfocus();
    }

    final text = _textController.text;
    var cursorPos = _textController.selection.baseOffset;

    // Handle invalid cursor position
    if (cursorPos < 0 || cursorPos > text.length) {
      cursorPos = text.length;
    }

    // Detect position before inserting the word
    final position = _detectWordPosition(text, cursorPos);

    // Extract previousWord for bigram tracking (all positions except 1)
    String? previousWord;
    if (position > 1) {
      previousWord = _extractPreviousWord(text, cursorPos);
    }

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

    // Track word usage with position and context
    _usageTracker?.trackWordUsage(
      word.text,
      position: position,
      previousWord: previousWord,
    );
  }

  /// Submit the current text for speech in response to Enter (hardware key,
  /// soft-keyboard send action, or the formatter's newline backstop).
  void _submitFromEnter() {
    final now = DateTime.now();
    // Multiple Enter-detection layers can fire for one keypress
    if (now.difference(_lastEnterSubmit).inMilliseconds < 300) return;
    _lastEnterSubmit = now;
    if (_isSpeaking) return;
    if (_textController.text.trim().isEmpty) return;
    _onSpeak();
    if (_inputMode == InputMode.typeOnly) {
      _textFieldFocus.requestFocus();
    }
  }

  /// Intercept hardware Enter on the text field so it speaks instead of
  /// inserting a newline.
  KeyEventResult _handleTextFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _submitFromEnter();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Screen-level handler: in type-only mode, F1-F12 select the matching
  /// suggested word.
  KeyEventResult _handleScreenKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_inputMode == InputMode.typeOnly) {
      final index = _fKeyIndex[event.logicalKey];
      if (index != null) {
        if (index < _currentSuggestions.length) {
          _onWordSelected(_currentSuggestions[index]);
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
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

        // Debounced vocabulary upload to server
        _uploadVocabularyDebounced();

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

        // Add to history with cached audio
        _addToHistory(text, combinedBytes, mimeType, sampleRate);
      }
    } else {
      // Fallback to concurrent generation for non-streaming providers
      final futures = chunks.map((chunk) => providerManager.generateSpeech(chunk));
      final audioChunks = await Future.wait(futures);

      // Combine and play
      if (audioChunks.isNotEmpty) {
        final combinedBytes = Uint8List.fromList(audioChunks.expand((x) => x).toList());
        await audioService.play(combinedBytes);

        // Add to history with cached audio
        _addToHistory(text, combinedBytes, null, null);
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

  /// Share cached audio file
  Future<void> _shareAudioFromHistory(SpeechHistoryItem item) async {
    if (item.cachedAudio == null) {
      _showError('No audio available to share');
      return;
    }

    try {
      // Get MIME type and sample rate
      final mimeType = item.mimeType ?? 'audio/mpeg';
      final sampleRate = item.sampleRate;

      // Convert PCM to WAV if needed
      Uint8List shareableData = item.cachedAudio!;
      String shareMimeType = mimeType;
      String extension;

      if (mimeType == 'audio/pcm') {
        // Convert raw PCM to WAV format with proper headers
        shareableData = _convertPcmToWav(shareableData, sampleRate: sampleRate ?? 44100);
        shareMimeType = 'audio/wav';
        extension = 'wav';
      } else if (mimeType == 'audio/wav') {
        extension = 'wav';
      } else {
        extension = 'mp3'; // audio/mpeg or default
      }

      // Write audio to temporary file (using path_provider for iOS share compatibility)
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'speaks_audio_$timestamp.$extension';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(shareableData);

      // Share the file
      final xFile = XFile(tempFile.path, mimeType: shareMimeType);
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      await Share.shareXFiles(
        [xFile],
        subject: 'Audio from ${_profileService?.getAppTitle() ?? "Speaks"}',
        text: item.text,
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      _showError('Failed to share audio: ${e.toString()}');
    }
  }

  /// Regenerate/re-speak phrase from history
  Future<void> _regenerateFromHistory(SpeechHistoryItem item) async {
    // Put text in text box and trigger speak
    _textController.text = item.text;
    await _onSpeak();
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
            Text(_profileService?.getAppTitle() ?? 'Speaks'),
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
                    builder: (context) => MainSettingsScreen(
                      providerManager: providerManager,
                    ),
                  ),
                );
                // Reload usage tracker to pick up any imported vocabulary
                await _reloadUsageTracker();
                // Refresh state after returning from settings (including profile changes)
                setState(() {});
              } else {
                _showError('App not fully initialized');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Focus(
          onKeyEvent: _handleScreenKey,
          canRequestFocus: false,
          skipTraversal: true,
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
    // For spinner keyboard: full-width spinner with collapsible history overlay
    if (_inputMethod == InputMethod.spinnerKeyboard) {
      return Column(
        children: [
          _buildInputArea(),
          Expanded(
            child: Stack(
              children: [
                // Spinner fills available space with bottom padding
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: _buildWordWheel(),
                  ),
                ),
                // History overlay (collapsed by default, expands to cover spinner)
                if (_speechHistory.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildCollapsibleHistory(),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Type-only mode: no word wheel, history fills the freed space
    if (_inputMode == InputMode.typeOnly) {
      return _buildTypeOnlyLayout();
    }

    // For word wheel: original flex layout
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

  /// Type-only mode layout (phone and tablet portrait): input area on top,
  /// recent phrases fill the space the word wheel would have used
  Widget _buildTypeOnlyLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInputArea(),
        Expanded(
          child: SizedBox(
            width: double.infinity,
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
    // For spinner keyboard: full-width spinner with collapsible history overlay
    if (_inputMethod == InputMethod.spinnerKeyboard) {
      return Column(
        children: [
          _buildInputArea(),
          Expanded(
            child: Stack(
              children: [
                // Spinner fills available space with bottom padding
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Center(child: _buildWordWheel()),
                  ),
                ),
                // History overlay (collapsed by default, expands to cover spinner)
                if (_speechHistory.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildCollapsibleHistory(),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Type-only mode: no word wheel, history fills the freed space
    if (_inputMode == InputMode.typeOnly) {
      return _buildTypeOnlyLayout();
    }

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
    // For spinner keyboard: full-width spinner with collapsible history overlay
    if (_inputMethod == InputMethod.spinnerKeyboard) {
      return Column(
        children: [
          _buildInputArea(isLandscape: true),
          Expanded(
            child: Stack(
              children: [
                // Spinner fills available space with bottom padding
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Center(child: _buildWordWheel()),
                  ),
                ),
                // History overlay (collapsed by default, expands to cover spinner)
                if (_speechHistory.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildCollapsibleHistory(),
                  ),
              ],
            ),
          ),
        ],
      );
    }

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
                  // Word wheel (left half) - centered in quadrant; hidden in
                  // type-only mode so phrases take the full width
                  if (_inputMode != InputMode.typeOnly)
                    Expanded(
                      child: Center(child: _buildWordWheel()),
                    ),

                  // Phrases list - flush left and top
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
                  child: Focus(
                    onKeyEvent: _handleTextFieldKey,
                    child: TextField(
                      key: _textFieldKey,
                      controller: _textController,
                      focusNode: _textFieldFocus,
                      readOnly: _inputMethod == InputMethod.spinnerKeyboard && _disableSystemKeyboard,
                      showCursor: true,
                      maxLines: null,
                      expands: true,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitFromEnter(),
                      inputFormatters: [_sentenceFormatter],
                      textAlignVertical: TextAlignVertical.top,
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
                  ),
                )
              : Focus(
                  onKeyEvent: _handleTextFieldKey,
                  child: TextField(
                    key: _textFieldKey,
                    controller: _textController,
                    focusNode: _textFieldFocus,
                    readOnly: _inputMethod == InputMethod.spinnerKeyboard && _disableSystemKeyboard,
                    showCursor: true,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitFromEnter(),
                    inputFormatters: [_sentenceFormatter],
                    textAlignVertical: TextAlignVertical.top,
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
                ),

          // Word suggestions bar - always reserve space for consistent layout
          Container(
            margin: const EdgeInsets.only(top: 8),
            height: _inputMode == InputMode.typeOnly ? 110 : 50,
            child: _currentSuggestions.isNotEmpty
                ? (_inputMode == InputMode.typeOnly
                    ? _buildSuggestionGrid()
                    : _buildSuggestionScrollRow())
                : const SizedBox.shrink(), // Empty space when no suggestions
          ),

          const SizedBox(height: 16),

          // Speak button and keyboard toggle row
          Row(
            children: [
              // Toggles on LEFT for left-handed users
              if (_inputMethodService?.isLeftHanded() ?? false) ...[
                _buildInputModeToggle(),
                const SizedBox(width: 12),
                _buildKeyboardToggle(),
                const SizedBox(width: 12),
              ],
              // Speak button
              Expanded(
                child: SizedBox(
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
              ),
              // Toggles on RIGHT for right-handed users
              if (!(_inputMethodService?.isLeftHanded() ?? false)) ...[
                const SizedBox(width: 12),
                _buildKeyboardToggle(),
                const SizedBox(width: 12),
                _buildInputModeToggle(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Build a single suggestion chip; the F-key badge variant is used by the
  /// type-only grid.
  Widget _buildSuggestionChip(Word word, int index, {bool showFKeyBadge = false}) {
    return Material(
      color: _getWordButtonColor(word),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: () => _onWordSelected(word),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: showFKeyBadge
              ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: index == 0
                  ? const Color(0xFF2563EB)
                  : Colors.grey[300]!,
              width: index == 0 ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: showFKeyBadge
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'F${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: index == 0
                            ? const Color(0xFF2563EB)
                            : Colors.grey[600],
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
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
                  ],
                )
              : Text(
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
    );
  }

  /// Horizontal scrolling suggestion row (type-and-touch mode)
  Widget _buildSuggestionScrollRow() {
    return Stack(
      children: [
        ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _currentSuggestions.length, // Show all 12 suggestions
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _buildSuggestionChip(_currentSuggestions[index], index),
            );
          },
        ),

        // Right fade gradient and arrow to indicate more content
        if (_currentSuggestions.length > 4)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.95),
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.chevron_right,
                    color: Color(0xFF2563EB),
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Fixed 2x6 grid of all 12 suggestions with F-key labels (type-only mode)
  Widget _buildSuggestionGrid() {
    Widget cell(int index) => index < _currentSuggestions.length
        ? _buildSuggestionChip(_currentSuggestions[index], index, showFKeyBadge: true)
        : const SizedBox.shrink();

    Widget row(int start) => Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = start; i < start + 6; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == start + 5 ? 0 : 6),
                    child: cell(i),
                  ),
                ),
            ],
          ),
        );

    return Column(
      children: [
        row(0),
        const SizedBox(height: 6),
        row(6),
      ],
    );
  }

  /// Build input mode toggle button (type only vs type and touch)
  Widget _buildInputModeToggle() {
    final isTypeOnly = _inputMode == InputMode.typeOnly;
    return SizedBox(
      height: 70,
      child: Material(
        color: isTypeOnly ? const Color(0xFF2563EB) : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: InkWell(
          onTap: () {
            setState(() {
              _inputMode = isTypeOnly ? InputMode.typeAndTouch : InputMode.typeOnly;
            });
            _inputMethodService?.setInputMode(_inputMode);
            if (_inputMode == InputMode.typeOnly) {
              _textFieldFocus.requestFocus();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(
              isTypeOnly ? Icons.keyboard_command_key : Icons.touch_app,
              size: 32,
              color: isTypeOnly ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  /// Build keyboard toggle button
  Widget _buildKeyboardToggle() {
    return SizedBox(
      height: 70,
      child: Material(
        color: _disableSystemKeyboard
            ? const Color(0xFF2563EB)
            : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: InkWell(
          onTap: () {
            setState(() {
              _disableSystemKeyboard = !_disableSystemKeyboard;
            });
            _inputMethodService?.setSystemKeyboardDisabled(_disableSystemKeyboard);
            // Hide keyboard if disabling
            if (_disableSystemKeyboard) {
              FocusScope.of(context).unfocus();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(
              _disableSystemKeyboard
                  ? Icons.keyboard_hide
                  : Icons.keyboard,
              size: 32,
              color: _disableSystemKeyboard
                  ? Colors.white
                  : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  /// Build input method (word wheel or spinner keyboard) - scales to fill available area
  Widget _buildWordWheel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use full available width and height for elliptical wheel
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth * 0.9  // 90% of available width
            : 400.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight * 0.9  // 90% of available height
            : 400.0;

        // Check which input method to use
        if (_inputMethod == InputMethod.spinnerKeyboard) {
          final isLeftHanded = _inputMethodService?.isLeftHanded() ?? false;
          // Full screen width (use MediaQuery, not constraints which may be limited)
          final screenWidth = MediaQuery.of(context).size.width;
          return SizedBox(
            width: screenWidth,
            height: screenWidth,
            child: SpinnerKeyboardWidget(
              key: ValueKey(_usageTracker),
              wordTracker: _usageTracker,
              onStringCompleted: _onSpinnerKeyboardComplete,
              alwaysVisible: true,
              isLeftHanded: isLeftHanded,
              onBackspaceToTextField: () {
                final text = _textController.text;
                final selection = _textController.selection;
                if (text.isNotEmpty && selection.baseOffset > 0) {
                  final newText = text.substring(0, selection.baseOffset - 1) +
                      text.substring(selection.baseOffset);
                  _textController.text = newText;
                  _textController.selection = TextSelection.collapsed(
                    offset: selection.baseOffset - 1,
                  );
                }
              },
              onClearWordInTextField: () {
                final text = _textController.text;
                final selection = _textController.selection;
                if (text.isNotEmpty && selection.baseOffset > 0) {
                  // Find start of current/previous word
                  var start = selection.baseOffset - 1;
                  // Skip trailing spaces
                  while (start > 0 && text[start] == ' ') {
                    start--;
                  }
                  // Find word start
                  while (start > 0 && text[start - 1] != ' ') {
                    start--;
                  }
                  final newText = text.substring(0, start) +
                      text.substring(selection.baseOffset);
                  _textController.text = newText;
                  _textController.selection = TextSelection.collapsed(offset: start);
                }
              },
            ),
          );
        }

        // Default: Word Wheel
        // Use current suggestions (already position-aware from _onTextChanged)
        // Fallback: if empty, get position-aware suggestions
        final words = _currentSuggestions.isNotEmpty
            ? _currentSuggestions
            : () {
                final position = _detectWordPosition(
                  _textController.text,
                  _textController.selection.baseOffset,
                );
                String? previousWord;
                if (position > 1) {
                  previousWord = _extractPreviousWord(
                    _textController.text,
                    _textController.selection.baseOffset,
                  );
                }
                return _usageTracker?.getSuggestions(
                  '',
                  limit: 12,
                  position: position,
                  previousWord: previousWord,
                ) ?? [];
              }();

        return SizedBox(
          width: width,
          height: height,
          child: WordWheelWidgetV2(
            words: words,
            onWordSelected: _onWordSelected,
            onWheelShown: () {},
            onWheelHidden: () {},
            alwaysVisible: true,
            currentPosition: _currentPosition,
            previousWord: _currentPreviousWord,
          ),
        );
      },
    );
  }

  /// Build collapsible history overlay for spinner keyboard mode
  Widget _buildCollapsibleHistory() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _historyExpanded = !_historyExpanded;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Recent Phrases',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2563EB),
                      fontSize: 16,
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
                  const Spacer(),
                  Icon(
                    _historyExpanded ? Icons.expand_more : Icons.expand_less,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
            // Expanded content
            if (_historyExpanded)
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: _speechHistory.map((item) => _buildHistoryItem(item)).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text content at top with more room
                Row(
                  children: [
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
                  ],
                ),

                const SizedBox(height: 8),

                // Action buttons row below
                Row(
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

                    const Spacer(),

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

                    // Regenerate/Re-speak button
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: Color(0xFF2563EB),
                        size: AccessibilityConstants.standardIconSize,
                      ),
                      onPressed: () => _regenerateFromHistory(item),
                      constraints: AccessibleTapTarget.minimum(),
                      tooltip: 'Regenerate audio',
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

                    // Share audio button (only if cached)
                    if (item.hasCache)
                      IconButton(
                        icon: const Icon(
                          Icons.share,
                          color: Color(0xFF2563EB),
                          size: AccessibilityConstants.standardIconSize,
                        ),
                        onPressed: () => _shareAudioFromHistory(item),
                        constraints: AccessibleTapTarget.minimum(),
                        tooltip: 'Share audio file',
                      ),

                    if (item.hasCache) const SizedBox(width: AccessibilityConstants.minSpacing),

                    // Delete button
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red[400],
                        size: AccessibilityConstants.standardIconSize,
                      ),
                      onPressed: () => _confirmDeleteFromHistory(item),
                      constraints: AccessibleTapTarget.minimum(),
                      tooltip: 'Delete from history',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Convert raw PCM data to WAV format with proper headers
  Uint8List _convertPcmToWav(Uint8List pcmData, {int sampleRate = 44100, int channels = 1, int bitsPerSample = 16}) {
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // space
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * (bitsPerSample ~/ 8), Endian.little);
    header.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wavData = Uint8List(44 + dataSize);
    wavData.setRange(0, 44, header.buffer.asUint8List());
    wavData.setRange(44, 44 + dataSize, pcmData);

    return wavData;
  }
}
