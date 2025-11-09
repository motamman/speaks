import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/tts_request.dart';
import 'tts_provider.dart';

/// Fish.Audio TTS Provider implementation
class FishAudioProvider extends TTSProvider {
  static const String _baseUrl = 'https://api.fish.audio/v1';
  static const String _ttsEndpoint = '$_baseUrl/tts';

  Map<String, String> _config = {};
  bool _isInitialized = false;

  @override
  String get id => 'fish_audio';

  @override
  String get name => 'Fish.Audio';

  @override
  String get description =>
      'Custom voice cloning with high-quality TTS. Best for personalized voices like Stuart\'s voice.';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsVoiceCloning => true;

  @override
  List<ConfigField> getRequiredConfig() => [
        const ConfigField(
          key: 'apiKey',
          label: 'API Key',
          hint: 'Your Fish.Audio API key',
          isSecret: true,
          isRequired: true,
        ),
        const ConfigField(
          key: 'modelId',
          label: 'Model ID',
          hint: 'The voice model ID (e.g., stuart_voice_01)',
          isSecret: false,
          isRequired: true,
        ),
        const ConfigField(
          key: 'format',
          label: 'Audio Format',
          hint: 'Audio output format',
          isSecret: false,
          isRequired: false,
          defaultValue: 'mp3',
          options: ['mp3', 'opus', 'wav', 'pcm'],
        ),
        const ConfigField(
          key: 'bitrate',
          label: 'MP3 Bitrate',
          hint: 'Audio quality in kbps',
          isSecret: false,
          isRequired: false,
          defaultValue: '128',
          options: ['64', '128', '192'],
        ),
        const ConfigField(
          key: 'temperature',
          label: 'Temperature',
          hint: '0.0-1.0 (controls creativity)',
          isSecret: false,
          isRequired: false,
          defaultValue: '0.7',
        ),
        const ConfigField(
          key: 'topP',
          label: 'Top P',
          hint: '0.0-1.0 (nucleus sampling)',
          isSecret: false,
          isRequired: false,
          defaultValue: '0.7',
        ),
        const ConfigField(
          key: 'latency',
          label: 'Latency Mode',
          hint: 'Quality vs speed tradeoff',
          isSecret: false,
          isRequired: false,
          defaultValue: 'normal',
          options: ['normal', 'balanced'],
        ),
        const ConfigField(
          key: 'useStreaming',
          label: 'Use Streaming',
          hint: 'Enable WebSocket streaming',
          isSecret: false,
          isRequired: false,
          defaultValue: 'false',
        ),
      ];

  @override
  Future<bool> initialize(Map<String, String> config) async {
    _config = Map.from(config);

    // Validate required fields
    if (!_config.containsKey('apiKey') || _config['apiKey']!.isEmpty) {
      throw TTSProviderException(
        'API Key is required',
        providerId: id,
      );
    }
    if (!_config.containsKey('modelId') || _config['modelId']!.isEmpty) {
      throw TTSProviderException(
        'Model ID is required',
        providerId: id,
      );
    }

    // Mark as initialized - credentials will be validated on first use
    _isInitialized = true;
    return true;
  }

  @override
  Future<String?> validateCredentials() async {
    try {
      // Make a minimal TTS request to validate credentials
      // This mimics the backend's approach of validating on first use
      final response = await http.post(
        Uri.parse(_ttsEndpoint),
        headers: {
          'Authorization': 'Bearer ${_config['apiKey']}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': 'test',
          'reference_id': _config['modelId'],
          'format': 'mp3',
          'mp3_bitrate': 128,
        }),
      );

      if (response.statusCode == 200) {
        return null; // Valid
      } else if (response.statusCode == 401) {
        return 'Invalid API key';
      } else if (response.statusCode == 402) {
        return 'Insufficient balance or invalid API key';
      } else if (response.statusCode == 403) {
        return 'Access forbidden - check your API key permissions';
      } else if (response.statusCode == 404) {
        return 'Invalid model ID or endpoint not found';
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
      // Get format and bitrate from config or request
      final format = request.format.isNotEmpty ? request.format : (_config['format'] ?? 'mp3');
      final bitrate = request.bitrate ?? int.tryParse(_config['bitrate'] ?? '128');
      final temperature = request.temperature ?? double.tryParse(_config['temperature'] ?? '0.7');
      final topP = request.topP ?? double.tryParse(_config['topP'] ?? '0.7');
      final latency = request.latency ?? _config['latency'] ?? 'normal';

      final requestBody = {
        'text': request.text,
        'reference_id': _config['modelId'],
        'format': format,
        if (format == 'mp3' && bitrate != null) 'mp3_bitrate': bitrate,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (latency.isNotEmpty) 'latency': latency,
      };

      final response = await http.post(
        Uri.parse(_ttsEndpoint),
        headers: {
          'Authorization': 'Bearer ${_config['apiKey']}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else if (response.statusCode == 401) {
        throw TTSProviderException(
          'Authentication failed - invalid API key',
          providerId: id,
          statusCode: response.statusCode,
        );
      } else if (response.statusCode == 429) {
        throw TTSProviderException(
          'Rate limit exceeded - please try again later',
          providerId: id,
          statusCode: response.statusCode,
        );
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
  Stream<Uint8List>? generateSpeechStream(TTSRequest request) async* {
    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    try {
      // Get format and other parameters
      final format = request.format.isNotEmpty ? request.format : (_config['format'] ?? 'mp3');
      final bitrate = request.bitrate ?? int.tryParse(_config['bitrate'] ?? '128');
      final temperature = request.temperature ?? double.tryParse(_config['temperature'] ?? '0.7');
      final topP = request.topP ?? double.tryParse(_config['topP'] ?? '0.7');
      final latency = request.latency ?? _config['latency'] ?? 'normal';

      final requestBody = {
        'text': request.text,
        'reference_id': _config['modelId'],
        'format': format,
        'chunk_length': 200, // Enable streaming with chunk length
        if (format == 'mp3' && bitrate != null) 'mp3_bitrate': bitrate,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (latency.isNotEmpty) 'latency': latency,
      };

      final client = http.Client();
      try {
        final streamRequest = http.Request('POST', Uri.parse(_ttsEndpoint));
        streamRequest.headers['Authorization'] = 'Bearer ${_config['apiKey']}';
        streamRequest.headers['Content-Type'] = 'application/json';
        streamRequest.body = jsonEncode(requestBody);

        final streamedResponse = await client.send(streamRequest);

        if (streamedResponse.statusCode == 200) {
          // Stream audio chunks
          await for (final chunk in streamedResponse.stream) {
            if (chunk.isNotEmpty) {
              yield Uint8List.fromList(chunk);
            }
          }
        } else if (streamedResponse.statusCode == 401) {
          throw TTSProviderException(
            'Authentication failed - invalid API key',
            providerId: id,
            statusCode: streamedResponse.statusCode,
          );
        } else if (streamedResponse.statusCode == 429) {
          throw TTSProviderException(
            'Rate limit exceeded',
            providerId: id,
            statusCode: streamedResponse.statusCode,
          );
        } else {
          throw TTSProviderException(
            'Streaming failed: ${streamedResponse.statusCode}',
            providerId: id,
            statusCode: streamedResponse.statusCode,
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (e is TTSProviderException) rethrow;
      throw TTSProviderException(
        'Streaming error: ${e.toString()}',
        providerId: id,
        originalError: e,
      );
    }
  }

  @override
  Future<List<Voice>> getAvailableVoices() async {
    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    // Fish.Audio doesn't provide a models listing endpoint
    // Return the configured voice as a single option
    return [
      Voice(
        id: _config['modelId']!,
        name: 'Configured Voice',
        description: 'Your configured Fish.Audio voice model',
        isCustom: true,
      ),
    ];
  }

  @override
  Map<String, String> get config => Map.unmodifiable(_config);

  @override
  bool get isInitialized => _isInitialized;
}
