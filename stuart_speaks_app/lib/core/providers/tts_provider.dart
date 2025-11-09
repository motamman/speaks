import 'dart:typed_data';

import '../models/tts_request.dart';

/// Configuration field for a TTS provider
class ConfigField {
  final String key;
  final String label;
  final String hint;
  final bool isSecret;
  final bool isRequired;
  final String? defaultValue;
  final List<String>? options; // If provided, renders as dropdown instead of text field

  const ConfigField({
    required this.key,
    required this.label,
    required this.hint,
    this.isSecret = false,
    this.isRequired = true,
    this.defaultValue,
    this.options,
  });
}

/// Abstract base class for all TTS providers
abstract class TTSProvider {
  /// Unique identifier for this provider (e.g., 'fish_audio', 'elevenlabs')
  String get id;

  /// Display name for this provider
  String get name;

  /// Description of this provider
  String get description;

  /// Whether this provider supports streaming audio
  bool get supportsStreaming;

  /// Whether this provider supports custom voice cloning
  bool get supportsVoiceCloning;

  /// Configuration fields required by this provider
  List<ConfigField> getRequiredConfig();

  /// Initialize the provider with configuration
  /// Returns true if configuration is valid and provider is ready
  Future<bool> initialize(Map<String, String> config);

  /// Validate the current configuration
  /// Returns error message if invalid, null if valid
  Future<String?> validateCredentials();

  /// Generate speech from text
  /// Returns audio data as bytes
  Future<Uint8List> generateSpeech(TTSRequest request);

  /// Generate speech with streaming support (if supported)
  /// Returns a stream of audio chunks
  Stream<Uint8List>? generateSpeechStream(TTSRequest request) {
    throw UnimplementedError('Streaming not supported by this provider');
  }

  /// Get available voices for this provider
  Future<List<Voice>> getAvailableVoices();

  /// Get the current configuration
  Map<String, String> get config;

  /// Whether the provider is currently initialized
  bool get isInitialized;
}

/// Exception thrown by TTS providers
class TTSProviderException implements Exception {
  final String message;
  final String? providerId;
  final int? statusCode;
  final dynamic originalError;

  TTSProviderException(
    this.message, {
    this.providerId,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() {
    final buffer = StringBuffer('TTSProviderException: $message');
    if (providerId != null) buffer.write(' (Provider: $providerId)');
    if (statusCode != null) buffer.write(' (Status: $statusCode)');
    return buffer.toString();
  }
}
