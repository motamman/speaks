import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service for playing TTS audio with queue management
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  final List<Uint8List> _queue = [];
  bool _isPlaying = false;
  bool _isPaused = false;

  StreamController<PlayerState>? _stateController;
  StreamController<Duration>? _positionController;
  StreamController<Duration>? _durationController;

  AudioPlaybackService() {
    _initializePlayer();
  }

  void _initializePlayer() {
    // Listen to player state changes
    _player.onPlayerStateChanged.listen((state) {
      _stateController?.add(state);
      if (state == PlayerState.completed) {
        _playNextInQueue();
      }
    });

    // Listen to position changes
    _player.onPositionChanged.listen((position) {
      _positionController?.add(position);
    });

    // Listen to duration changes
    _player.onDurationChanged.listen((duration) {
      _durationController?.add(duration);
    });
  }

  /// Stream of player state changes
  Stream<PlayerState> get onPlayerStateChanged {
    _stateController ??= StreamController<PlayerState>.broadcast();
    return _stateController!.stream;
  }

  /// Stream of position changes
  Stream<Duration> get onPositionChanged {
    _positionController ??= StreamController<Duration>.broadcast();
    return _positionController!.stream;
  }

  /// Stream of duration changes
  Stream<Duration> get onDurationChanged {
    _durationController ??= StreamController<Duration>.broadcast();
    return _durationController!.stream;
  }

  /// Play audio from bytes
  Future<void> play(Uint8List audioBytes, {String? mimeType, int? sampleRate}) async {
    await stop(); // Stop any current playback
    _queue.clear();

    _isPlaying = true;
    _isPaused = false;

    try {
      // Detect MIME type from audio header if not provided
      final detectedMimeType = mimeType ?? _detectMimeType(audioBytes);

      // Log for debugging
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Playing audio - ${audioBytes.length} bytes, MIME: $detectedMimeType');
        debugPrint('AudioPlaybackService: First 16 bytes: ${audioBytes.take(16).toList()}');
      }

      // On Android, use file-based approach directly (more reliable)
      if (Platform.isAndroid) {
        if (kDebugMode) {
          debugPrint('AudioPlaybackService: Using file-based playback on Android');
        }
        await _playFromFile(audioBytes, detectedMimeType, sampleRate);
      } else {
        await _player.play(BytesSource(audioBytes, mimeType: detectedMimeType));
      }
    } catch (e) {
      _isPlaying = false;
      if (kDebugMode) {
        debugPrint('AudioPlaybackService: Playback error: $e');
      }
      rethrow;
    }
  }

  /// File-based playback (more reliable on Android)
  Future<void> _playFromFile(Uint8List audioBytes, String? mimeType, int? sampleRate) async {
    final tempDir = await getTemporaryDirectory();
    final extension = _getFileExtension(mimeType);
    final tempFile = File('${tempDir.path}/tts_audio_${DateTime.now().millisecondsSinceEpoch}$extension');

    // Fix WAV header if needed (some providers return invalid size fields)
    Uint8List finalAudioBytes = audioBytes;
    if (mimeType == 'audio/wav' && audioBytes.length > 44) {
      finalAudioBytes = _fixWavHeader(audioBytes);
    } else if (mimeType == 'audio/pcm') {
      // Convert raw PCM to WAV (Android can't play raw PCM files)
      // Use the provided sample rate or default to 44100 Hz
      final pcmSampleRate = sampleRate ?? 44100;
      finalAudioBytes = _convertPcmToWav(
        audioBytes,
        sampleRate: pcmSampleRate,
        bitsPerSample: 16,
      );
    }

    await tempFile.writeAsBytes(finalAudioBytes);
    if (kDebugMode) {
      debugPrint('AudioPlaybackService: Playing from temp file: ${tempFile.path}');
    }

    await _player.play(DeviceFileSource(tempFile.path));

    // Clean up temp file after a delay (ensure playback has started)
    Future.delayed(const Duration(seconds: 3), () {
      try {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
          if (kDebugMode) {
            debugPrint('AudioPlaybackService: Cleaned up temp file');
          }
        }
      } catch (e) {
        // Ignore cleanup errors
        if (kDebugMode) {
          debugPrint('AudioPlaybackService: Error cleaning up temp file: $e');
        }
      }
    });
  }

  String _getFileExtension(String? mimeType) {
    switch (mimeType) {
      case 'audio/mpeg':
      case 'audio/mp3':
        return '.mp3';
      case 'audio/wav':
      case 'audio/wave':
      case 'audio/pcm':
        return '.wav'; // PCM will be converted to WAV
      case 'audio/ogg':
        return '.ogg';
      case 'audio/flac':
        return '.flac';
      case 'audio/mp4':
      case 'audio/aac':
        return '.m4a';
      default:
        return '.wav'; // Default to wav for unknown formats
    }
  }

  /// Convert raw PCM to WAV format (Android requires proper headers)
  /// Note: Cartesia default is pcm_s16le (16-bit signed little-endian) at 44100 Hz, mono
  Uint8List _convertPcmToWav(Uint8List pcmData, {int sampleRate = 44100, int channels = 1, int bitsPerSample = 16}) {
    if (kDebugMode) {
      debugPrint('AudioPlaybackService: Converting PCM to WAV - ${pcmData.length} bytes, $sampleRate Hz, $channels ch, $bitsPerSample bit');
    }
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
    header.setUint32(16, 16, Endian.little); // fmt chunk size
    header.setUint16(20, 1, Endian.little); // audio format (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * (bitsPerSample ~/ 8), Endian.little); // byte rate
    header.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little); // block align
    header.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    // Combine header and PCM data
    final wavData = Uint8List(44 + dataSize);
    wavData.setRange(0, 44, header.buffer.asUint8List());
    wavData.setRange(44, 44 + dataSize, pcmData);

    if (kDebugMode) {
      debugPrint('AudioPlaybackService: Converted raw PCM to WAV (${pcmData.length} bytes)');
    }

    return wavData;
  }

  /// Fix WAV header with proper file size (some streaming APIs return 0xFFFFFFFF)
  Uint8List _fixWavHeader(Uint8List wavData) {
    // Check if it's a valid RIFF/WAVE file
    if (wavData.length < 44 ||
        wavData[0] != 0x52 || wavData[1] != 0x49 || wavData[2] != 0x46 || wavData[3] != 0x46 || // RIFF
        wavData[8] != 0x57 || wavData[9] != 0x41 || wavData[10] != 0x56 || wavData[11] != 0x45) { // WAVE
      return wavData; // Not a WAV file, return as-is
    }

    // Create a mutable copy
    final fixedData = Uint8List.fromList(wavData);

    // Calculate actual file size
    final fileSize = wavData.length - 8; // Total size minus 8 bytes for RIFF header

    // Fix RIFF chunk size (bytes 4-7)
    fixedData[4] = fileSize & 0xFF;
    fixedData[5] = (fileSize >> 8) & 0xFF;
    fixedData[6] = (fileSize >> 16) & 0xFF;
    fixedData[7] = (fileSize >> 24) & 0xFF;

    // Find and fix data chunk size if it's also 0xFFFFFFFF
    for (int i = 12; i < wavData.length - 8; i++) {
      // Look for 'data' chunk (0x64 0x61 0x74 0x61)
      if (wavData[i] == 0x64 && wavData[i + 1] == 0x61 &&
          wavData[i + 2] == 0x74 && wavData[i + 3] == 0x61) {
        // Data chunk size is at i+4 to i+7
        final dataSize = wavData.length - i - 8;
        fixedData[i + 4] = dataSize & 0xFF;
        fixedData[i + 5] = (dataSize >> 8) & 0xFF;
        fixedData[i + 6] = (dataSize >> 16) & 0xFF;
        fixedData[i + 7] = (dataSize >> 24) & 0xFF;
        break;
      }
    }

    if (kDebugMode) {
      debugPrint('AudioPlaybackService: Fixed WAV header (size: ${wavData.length} bytes)');
    }

    return fixedData;
  }

  /// Detect MIME type from audio file header
  String? _detectMimeType(Uint8List bytes) {
    if (bytes.length < 12) return 'audio/pcm'; // Default to raw PCM for small chunks

    // Check for MP3 (ID3 or FF FB/FF F3/FF F2)
    if ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) || // ID3
        (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)) { // MPEG sync
      return 'audio/mpeg';
    }

    // Check for WAV (RIFF....WAVE)
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45) {
      return 'audio/wav';
    }

    // Check for OGG (OggS)
    if (bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) {
      return 'audio/ogg';
    }

    // Check for FLAC (fLaC)
    if (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) {
      return 'audio/flac';
    }

    // Check for M4A/AAC (ftyp)
    if (bytes.length > 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      return 'audio/mp4';
    }

    // If none of the above, likely raw PCM from streaming
    return 'audio/pcm';
  }

  /// Play multiple audio chunks in sequence
  Future<void> playQueue(List<Uint8List> audioChunks, {String? mimeType, int? sampleRate}) async {
    if (audioChunks.isEmpty) return;

    await stop();
    _queue.clear();
    _queue.addAll(audioChunks);

    _isPlaying = true;
    _isPaused = false;

    // Detect MIME type from first chunk
    final detectedMimeType = mimeType ?? _detectMimeType(_queue.first);

    // Play first chunk using appropriate method for platform
    try {
      final firstChunk = _queue.removeAt(0);
      if (Platform.isAndroid) {
        await _playFromFile(firstChunk, detectedMimeType, sampleRate);
      } else {
        await _player.play(BytesSource(firstChunk, mimeType: detectedMimeType));
      }
    } catch (e) {
      _isPlaying = false;
      _queue.clear();
      rethrow;
    }
  }

  /// Play next chunk in queue
  Future<void> _playNextInQueue() async {
    if (_queue.isEmpty) {
      _isPlaying = false;
      return;
    }

    try {
      final audioBytes = _queue.removeAt(0);
      final mimeType = _detectMimeType(audioBytes);

      // Use appropriate method for platform
      if (Platform.isAndroid) {
        await _playFromFile(audioBytes, mimeType, null);
      } else {
        await _player.play(BytesSource(audioBytes, mimeType: mimeType));
      }
    } catch (e) {
      _isPlaying = false;
      _queue.clear();
      rethrow;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (_isPlaying && !_isPaused) {
      await _player.pause();
      _isPaused = true;
    }
  }

  /// Resume playback
  Future<void> resume() async {
    if (_isPlaying && _isPaused) {
      await _player.resume();
      _isPaused = false;
    }
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
    _queue.clear();
    _isPlaying = false;
    _isPaused = false;
  }

  /// Replay the current audio (if any)
  Future<void> replay() async {
    if (_isPlaying) {
      await _player.seek(Duration.zero);
    }
  }

  /// Get current player state
  bool get isPlaying => _isPlaying && !_isPaused;
  bool get isPaused => _isPaused;

  /// Clean up resources
  void dispose() {
    _player.dispose();
    _stateController?.close();
    _positionController?.close();
    _durationController?.close();
  }
}
