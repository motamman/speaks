import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

/// Service for playing TTS audio with streaming support using flutter_sound
/// Supports true low-latency PCM streaming for AAC communication
class AudioPlaybackService {
  FlutterSoundPlayer? _player;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  bool _isStreaming = false;
  File? _currentTempFile;

  // Stream controllers for state
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  AudioPlaybackService() {
    _initialize();
  }

  /// Initialize the player
  Future<void> _initialize() async {
    try {
      _player = FlutterSoundPlayer();
      await _player!.openPlayer();
      await _player!.setSubscriptionDuration(const Duration(milliseconds: 100));

      // Listen to player state
      _player!.onProgress!.listen((event) {
        if (event.position != null) {
          _positionController.add(event.position!);
        }
      });

      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Initialized flutter_sound player');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Initialization error: $e');
      }
      rethrow;
    }
  }

  /// Stream of playback state changes
  Stream<PlaybackState> get onStateChanged => _stateController.stream;

  /// Stream of position changes
  Stream<Duration> get onPositionChanged => _positionController.stream;

  /// Play complete audio from bytes (non-streaming)
  Future<void> play(Uint8List audioBytes, {String? mimeType, int? sampleRate}) async {
    if (!_isInitialized || _player == null) {
      throw Exception('AudioPlaybackService not initialized');
    }

    await stop(); // Stop any current playback

    try {
      final detectedMimeType = mimeType ?? _detectMimeType(audioBytes);

      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Playing ${audioBytes.length} bytes, MIME: $detectedMimeType');
      }

      _isPlaying = true;
      _isPaused = false;
      _stateController.add(PlaybackState.playing);

      // Convert PCM to WAV if needed
      Uint8List playableData = audioBytes;
      Codec codec = _getCodecForMimeType(detectedMimeType);
      String fileExtension = _getFileExtension(detectedMimeType);

      if (detectedMimeType == 'audio/pcm') {
        final pcmSampleRate = sampleRate ?? 44100;
        playableData = _convertPcmToWav(audioBytes, sampleRate: pcmSampleRate);
        codec = Codec.pcm16WAV;
        fileExtension = 'wav';
      }

      // Write to temp file with correct extension (critical for Android MediaPlayer)
      final tempDir = await getTemporaryDirectory();
      _currentTempFile = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.$fileExtension');
      await _currentTempFile!.writeAsBytes(playableData);

      await _player!.startPlayer(
        fromURI: _currentTempFile!.path,
        codec: codec,
        whenFinished: () {
          if (kDebugMode) {
            debugPrint('AudioPlaybackService: Playback finished callback');
          }
          _onPlaybackComplete();
        },
      );
    } catch (e) {
      // Critical: Clean up player state on error to prevent corruption
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Playback error: $e');
      }

      try {
        await _player?.stopPlayer();
      } catch (_) {
        // Ignore errors during cleanup
      }

      _isPlaying = false;
      _isPaused = false;
      _isStreaming = false;
      _stateController.add(PlaybackState.stopped);

      // Clean up temp file
      if (_currentTempFile != null && await _currentTempFile!.exists()) {
        await _currentTempFile!.delete();
        _currentTempFile = null;
      }

      rethrow;
    }
  }

  /// Start streaming PCM audio chunks (true low-latency streaming)
  Future<void> startStreaming({int sampleRate = 44100, int channels = 1}) async {
    if (!_isInitialized || _player == null) {
      throw Exception('AudioPlaybackService not initialized');
    }

    await stop(); // Stop any current playback

    try {
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Starting PCM stream - $sampleRate Hz, $channels ch');
      }

      _isPlaying = true;
      _isPaused = false;
      _isStreaming = true;
      _stateController.add(PlaybackState.playing);

      // Start player in streaming mode with PCM16
      await _player!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: channels,
        sampleRate: sampleRate,
        bufferSize: 8192, // Buffer size for streaming (8KB chunks)
        interleaved: true, // PCM data is interleaved (standard format)
      );
    } catch (e) {
      _isPlaying = false;
      _isStreaming = false;
      _stateController.add(PlaybackState.stopped);
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Stream start error: $e');
      }
      rethrow;
    }
  }

  /// Feed a PCM audio chunk to the stream
  Future<void> feedChunk(Uint8List pcmData) async {
    if (!_isStreaming || _player == null) {
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Cannot feed chunk - not streaming');
      }
      return;
    }

    try {
      await _player!.feedFromStream(pcmData);

      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Fed ${pcmData.length} bytes to stream');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Error feeding chunk: $e');
      }
    }
  }

  /// Stop streaming and close the stream
  /// Waits for buffer to drain before stopping to prevent clipping
  Future<void> stopStreaming({bool immediate = false}) async {
    if (_isStreaming && _player != null) {
      try {
        if (!immediate) {
          // Wait for audio buffer to drain (prevents clipping last syllable)
          // Buffer size is 8KB, at 44100Hz 16-bit mono = 88200 bytes/sec
          // 8KB = ~90ms of audio. Wait 200ms to be safe.
          await Future.delayed(const Duration(milliseconds: 200));

          if (kDebugMode) {
            debugPrint('AudioPlaybackService: Buffer drained, stopping stream');
          }
        }

        // Stop the streaming player
        await _player!.stopPlayer();
        _isStreaming = false;

        if (kDebugMode) {
          debugPrint('AudioPlaybackService: Stopped streaming');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('AudioPlaybackService: Error stopping stream: $e');
        }
      }
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (_isPlaying && !_isPaused && _player != null) {
      await _player!.pausePlayer();
      _isPaused = true;
      _stateController.add(PlaybackState.paused);
    }
  }

  /// Resume playback
  Future<void> resume() async {
    if (_isPlaying && _isPaused && _player != null) {
      await _player!.resumePlayer();
      _isPaused = false;
      _stateController.add(PlaybackState.playing);
    }
  }

  /// Stop playback
  Future<void> stop() async {
    if (_player != null) {
      try {
        // If streaming, stop immediately (user initiated)
        if (_isStreaming) {
          await stopStreaming(immediate: true);
        } else {
          await _player!.stopPlayer();
        }

        _isPlaying = false;
        _isPaused = false;
        _isStreaming = false;
        _stateController.add(PlaybackState.stopped);

        // Clean up temp file
        if (_currentTempFile != null && await _currentTempFile!.exists()) {
          await _currentTempFile!.delete();
          _currentTempFile = null;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('AudioPlaybackService: Error stopping: $e');
        }
      }
    }
  }

  void _onPlaybackComplete() {
    _isPlaying = false;
    _isPaused = false;
    _isStreaming = false; // Reset streaming state too
    _stateController.add(PlaybackState.completed);

    if (kDebugMode) {
      debugPrint('AudioPlaybackService: Playback completed');
    }

    // Clean up temp file
    if (_currentTempFile != null) {
      _currentTempFile!.delete().catchError((e) {
        if (kDebugMode) {
          debugPrint('AudioPlaybackService: Error deleting temp file: $e');
        }
        return _currentTempFile!; // Fix warning: return value for catchError
      });
      _currentTempFile = null;
    }
  }

  /// Convert raw PCM to WAV format
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

  /// Detect MIME type from audio file header
  String _detectMimeType(Uint8List bytes) {
    if (bytes.length < 12) return 'audio/pcm';

    // Check for MP3
    if ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
        (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)) {
      return 'audio/mpeg';
    }

    // Check for WAV
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45) {
      return 'audio/wav';
    }

    // Check for OGG
    if (bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) {
      return 'audio/ogg';
    }

    // Check for FLAC
    if (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) {
      return 'audio/flac';
    }

    return 'audio/pcm';
  }

  /// Get flutter_sound codec for MIME type
  Codec _getCodecForMimeType(String mimeType) {
    switch (mimeType) {
      case 'audio/mpeg':
      case 'audio/mp3':
        return Codec.mp3;
      case 'audio/wav':
      case 'audio/wave':
        return Codec.pcm16WAV;
      case 'audio/pcm':
        return Codec.pcm16;
      case 'audio/ogg':
        return Codec.opusOGG;
      case 'audio/flac':
        return Codec.flac;
      case 'audio/aac':
        return Codec.aacADTS;
      default:
        return Codec.pcm16WAV;
    }
  }

  /// Get file extension for MIME type (critical for Android MediaPlayer)
  String _getFileExtension(String mimeType) {
    switch (mimeType) {
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'mp3';
      case 'audio/wav':
      case 'audio/wave':
        return 'wav';
      case 'audio/pcm':
        return 'pcm'; // Will be converted to wav
      case 'audio/ogg':
        return 'ogg';
      case 'audio/flac':
        return 'flac';
      case 'audio/aac':
        return 'aac';
      default:
        return 'wav';
    }
  }

  /// Get current player state
  bool get isPlaying => _isPlaying && !_isPaused;
  bool get isPaused => _isPaused;
  bool get isStreaming => _isStreaming;

  /// Clean up resources
  Future<void> dispose() async {
    await stop();
    await _player?.closePlayer();
    await _stateController.close();
    await _positionController.close();
    _player = null;
  }
}

/// Playback state enum
enum PlaybackState {
  stopped,
  playing,
  paused,
  completed,
}
