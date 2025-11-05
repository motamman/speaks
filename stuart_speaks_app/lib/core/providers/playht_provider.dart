import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/tts_request.dart';
import 'tts_provider.dart';

/// Play.ht TTS Provider implementation with voice cloning and streaming
class PlayHtProvider extends TTSProvider {
  static const String _baseUrl = 'https://api.play.ht/api/v2';
  static const String _streamEndpoint = '$_baseUrl/tts/stream';

  Map<String, String> _config = {};
  bool _isInitialized = false;

  @override
  String get id => 'playht';

  @override
  String get name => 'Play.ht';

  @override
  String get description =>
      'Ultra-realistic voice cloning with instant cloning from 30 seconds of audio. Best for creating custom voices quickly.';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsVoiceCloning => true;

  @override
  List<ConfigField> getRequiredConfig() => [
        const ConfigField(
          key: 'userId',
          label: 'User ID',
          hint: 'Your Play.ht user ID (from dashboard)',
          isSecret: false,
          isRequired: true,
        ),
        const ConfigField(
          key: 'apiKey',
          label: 'API Key',
          hint: 'Your Play.ht API key',
          isSecret: true,
          isRequired: true,
        ),
        const ConfigField(
          key: 'voice',
          label: 'Voice ID',
          hint: 'Voice manifest URL (s3://... or voice ID)',
          isSecret: false,
          isRequired: true,
        ),
        const ConfigField(
          key: 'voiceEngine',
          label: 'Voice Engine',
          hint: 'PlayDialog, Play3.0-mini, or Play3.0',
          isSecret: false,
          isRequired: false,
          defaultValue: 'PlayDialog',
        ),
        const ConfigField(
          key: 'outputFormat',
          label: 'Output Format',
          hint: 'mp3, wav, ogg, flac, or mulaw',
          isSecret: false,
          isRequired: false,
          defaultValue: 'mp3',
        ),
        const ConfigField(
          key: 'quality',
          label: 'Quality',
          hint: 'draft, low, medium, high, or premium',
          isSecret: false,
          isRequired: false,
          defaultValue: 'medium',
        ),
        const ConfigField(
          key: 'speed',
          label: 'Speed',
          hint: '0.5-2.0 (1.0 is normal)',
          isSecret: false,
          isRequired: false,
          defaultValue: '1.0',
        ),
        const ConfigField(
          key: 'sampleRate',
          label: 'Sample Rate',
          hint: '8000, 16000, 22050, 24000, or 44100',
          isSecret: false,
          isRequired: false,
          defaultValue: '24000',
        ),
        const ConfigField(
          key: 'temperature',
          label: 'Temperature',
          hint: '0.0-2.0 (controls randomness)',
          isSecret: false,
          isRequired: false,
          defaultValue: '1.0',
        ),
      ];

  @override
  Future<bool> initialize(Map<String, String> config) async {
    _config = Map.from(config);

    // Validate required fields
    if (!_config.containsKey('userId') || _config['userId']!.isEmpty) {
      throw TTSProviderException(
        'User ID is required',
        providerId: id,
      );
    }
    if (!_config.containsKey('apiKey') || _config['apiKey']!.isEmpty) {
      throw TTSProviderException(
        'API Key is required',
        providerId: id,
      );
    }
    if (!_config.containsKey('voice') || _config['voice']!.isEmpty) {
      throw TTSProviderException(
        'Voice ID is required',
        providerId: id,
      );
    }

    // Set defaults
    _config['voiceEngine'] ??= 'PlayDialog';
    _config['outputFormat'] ??= 'mp3';
    _config['quality'] ??= 'medium';
    _config['speed'] ??= '1.0';
    _config['sampleRate'] ??= '24000';
    _config['temperature'] ??= '1.0';

    _isInitialized = true;
    return true;
  }

  @override
  Future<String?> validateCredentials() async {
    try {
      // Make a minimal TTS request to validate credentials
      final response = await http.post(
        Uri.parse(_streamEndpoint),
        headers: {
          'X-USER-ID': _config['userId']!,
          'AUTHORIZATION': _config['apiKey']!,
          'accept': 'audio/mpeg',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'text': 'test',
          'voice': _config['voice'],
          'voice_engine': _config['voiceEngine'],
          'output_format': _config['outputFormat'],
        }),
      );

      if (response.statusCode == 200) {
        return null; // Valid
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return 'Invalid user ID or API key';
      } else if (response.statusCode == 404) {
        return 'Invalid voice ID';
      } else if (response.statusCode == 400) {
        try {
          final error = jsonDecode(response.body);
          return 'Invalid request: ${error['error_message'] ?? response.body}';
        } catch (_) {
          return 'Invalid request parameters';
        }
      } else {
        return 'API error: ${response.statusCode}';
      }
    } catch (e) {
      return 'Connection error: ${e.toString()}';
    }
  }

  @override
  Future<Uint8List> generateSpeech(TTSRequest request) async {
    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    try {
      final voice = request.voiceId ?? _config['voice']!;
      final speed = request.speed ?? double.tryParse(_config['speed'] ?? '1.0') ?? 1.0;
      final sampleRate = int.tryParse(_config['sampleRate'] ?? '24000') ?? 24000;
      final temperature = double.tryParse(_config['temperature'] ?? '1.0') ?? 1.0;

      final requestBody = <String, dynamic>{
        'text': request.text,
        'voice': voice,
        'voice_engine': _config['voiceEngine'],
        'output_format': _config['outputFormat'],
        'quality': _config['quality'],
        'speed': speed,
        'sample_rate': sampleRate,
        'temperature': temperature,
      };

      final response = await http.post(
        Uri.parse(_streamEndpoint),
        headers: {
          'X-USER-ID': _config['userId']!,
          'AUTHORIZATION': _config['apiKey']!,
          'accept': 'audio/mpeg',
          'content-type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw TTSProviderException(
          'Authentication failed - invalid credentials',
          providerId: id,
          statusCode: response.statusCode,
        );
      } else if (response.statusCode == 429) {
        throw TTSProviderException(
          'Rate limit exceeded - please try again later',
          providerId: id,
          statusCode: response.statusCode,
        );
      } else if (response.statusCode == 400) {
        try {
          final error = jsonDecode(response.body);
          throw TTSProviderException(
            'Invalid request: ${error['error_message'] ?? response.body}',
            providerId: id,
            statusCode: response.statusCode,
          );
        } catch (e) {
          throw TTSProviderException(
            'Invalid request parameters',
            providerId: id,
            statusCode: response.statusCode,
          );
        }
      } else {
        final errorBody = response.body;
        throw TTSProviderException(
          'API error: $errorBody',
          providerId: id,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is TTSProviderException) rethrow;
      throw TTSProviderException(
        'Failed to generate speech: ${e.toString()}',
        providerId: id,
        originalError: e,
      );
    }
  }

  @override
  Stream<Uint8List>? generateSpeechStream(TTSRequest request) {
    // TODO: Implement WebSocket streaming
    // WebSocket endpoint: wss://api.play.ht/api/v2/tts/stream
    // Requires web_socket_channel package
    //
    // Play.ht supports both HTTP streaming and WebSocket streaming
    // HTTP streaming is already implemented above
    throw UnimplementedError('WebSocket streaming not yet implemented for Play.ht');
  }

  @override
  Future<List<Voice>> getAvailableVoices() async {
    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    // Play.ht voices are typically cloned voices
    // Return the configured voice
    return [
      Voice(
        id: _config['voice']!,
        name: 'Cloned Voice',
        description: 'Your custom cloned voice',
        isCustom: true,
      ),
    ];
  }

  @override
  Map<String, String> get config => Map.unmodifiable(_config);

  @override
  bool get isInitialized => _isInitialized;
}
