import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/tts_request.dart';
import 'tts_provider.dart';

/// Resemble.AI TTS Provider implementation with voice cloning and emotional control
class ResembleProvider extends TTSProvider {
  static const String _baseUrl = 'https://f.cluster.resemble.ai';
  static const String _synthesizeEndpoint = '$_baseUrl/synthesize';

  Map<String, String> _config = {};
  bool _isInitialized = false;

  @override
  String get id => 'resemble';

  @override
  String get name => 'Resemble.AI';

  @override
  String get description =>
      'Real-time voice cloning with emotional control (happy, sad, angry). Best for expressive character voices in 149+ languages.';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsVoiceCloning => true;

  @override
  List<ConfigField> getRequiredConfig() => [
        const ConfigField(
          key: 'apiKey',
          label: 'API Key',
          hint: 'Your Resemble.AI API token (Bearer token)',
          isSecret: true,
          isRequired: true,
        ),
        const ConfigField(
          key: 'voiceUuid',
          label: 'Voice UUID',
          hint: 'Your cloned voice UUID',
          isSecret: false,
          isRequired: true,
        ),
        const ConfigField(
          key: 'projectUuid',
          label: 'Project UUID (Optional)',
          hint: 'Project to save clips to',
          isSecret: false,
          isRequired: false,
        ),
        const ConfigField(
          key: 'outputFormat',
          label: 'Output Format',
          hint: 'mp3 or wav',
          isSecret: false,
          isRequired: false,
          defaultValue: 'mp3',
        ),
        const ConfigField(
          key: 'sampleRate',
          label: 'Sample Rate',
          hint: '8000, 16000, 22050, or 44100',
          isSecret: false,
          isRequired: false,
          defaultValue: '22050',
        ),
        const ConfigField(
          key: 'precision',
          label: 'Precision',
          hint: 'PCM_16, PCM_24, PCM_32, or FLOAT',
          isSecret: false,
          isRequired: false,
          defaultValue: 'PCM_16',
        ),
        const ConfigField(
          key: 'emotion',
          label: 'Emotion',
          hint: 'happy, sad, angry, neutral, etc.',
          isSecret: false,
          isRequired: false,
          defaultValue: 'neutral',
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
    if (!_config.containsKey('voiceUuid') || _config['voiceUuid']!.isEmpty) {
      throw TTSProviderException(
        'Voice UUID is required',
        providerId: id,
      );
    }

    // Set defaults
    _config['outputFormat'] ??= 'mp3';
    _config['sampleRate'] ??= '22050';
    _config['precision'] ??= 'PCM_16';
    _config['emotion'] ??= 'neutral';

    _isInitialized = true;
    return true;
  }

  @override
  Future<String?> validateCredentials() async {
    try {
      // Make a minimal TTS request to validate credentials
      final requestBody = <String, dynamic>{
        'voice_uuid': _config['voiceUuid'],
        'data': 'test',
        'sample_rate': int.tryParse(_config['sampleRate'] ?? '22050') ?? 22050,
        'output_format': _config['outputFormat'],
        'precision': _config['precision'],
      };

      if (_config.containsKey('projectUuid') && _config['projectUuid']!.isNotEmpty) {
        requestBody['project_uuid'] = _config['projectUuid'];
      }

      final response = await http.post(
        Uri.parse(_synthesizeEndpoint),
        headers: {
          'Authorization': 'Bearer ${_config['apiKey']}',
          'Content-Type': 'application/json',
          'Accept-Encoding': 'gzip',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return null; // Valid
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return 'Invalid API key or access denied';
      } else if (response.statusCode == 404) {
        return 'Invalid voice UUID or project UUID';
      } else if (response.statusCode == 400) {
        try {
          final error = jsonDecode(response.body);
          return 'Invalid request: ${error['message'] ?? response.body}';
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
      final voiceUuid = request.voiceId ?? _config['voiceUuid']!;
      final sampleRate = int.tryParse(_config['sampleRate'] ?? '22050') ?? 22050;

      final requestBody = <String, dynamic>{
        'voice_uuid': voiceUuid,
        'data': request.text,
        'sample_rate': sampleRate,
        'output_format': _config['outputFormat'],
        'precision': _config['precision'],
      };

      // Add optional parameters
      if (_config.containsKey('projectUuid') && _config['projectUuid']!.isNotEmpty) {
        requestBody['project_uuid'] = _config['projectUuid'];
      }

      if (_config.containsKey('emotion') && _config['emotion']!.isNotEmpty && _config['emotion'] != 'neutral') {
        requestBody['emotion'] = _config['emotion'];
      }

      final response = await http.post(
        Uri.parse(_synthesizeEndpoint),
        headers: {
          'Authorization': 'Bearer ${_config['apiKey']}',
          'Content-Type': 'application/json',
          'Accept-Encoding': 'gzip',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Resemble.AI returns JSON with audio data
        try {
          final responseData = jsonDecode(response.body);

          // Check if response contains URL or direct audio data
          if (responseData['item'] != null && responseData['item']['audio_src'] != null) {
            // Audio is available at a URL, fetch it
            final audioUrl = responseData['item']['audio_src'] as String;
            final audioResponse = await http.get(Uri.parse(audioUrl));

            if (audioResponse.statusCode == 200) {
              return audioResponse.bodyBytes;
            } else {
              throw TTSProviderException(
                'Failed to download audio from URL',
                providerId: id,
                statusCode: audioResponse.statusCode,
              );
            }
          } else if (responseData['audio'] != null) {
            // Direct audio data (base64 encoded)
            final audioBase64 = responseData['audio'] as String;
            return base64Decode(audioBase64);
          } else {
            throw TTSProviderException(
              'Unexpected response format',
              providerId: id,
            );
          }
        } catch (e) {
          if (e is TTSProviderException) rethrow;
          throw TTSProviderException(
            'Failed to parse response: ${e.toString()}',
            providerId: id,
          );
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
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
      } else if (response.statusCode == 400) {
        try {
          final error = jsonDecode(response.body);
          throw TTSProviderException(
            'Invalid request: ${error['message'] ?? response.body}',
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
    // TODO: Implement HTTP or WebSocket streaming
    // Resemble.AI supports streaming via their SDK
    // HTTP streaming can be implemented using chunked transfer encoding
    // WebSocket streaming available for real-time applications
    throw UnimplementedError('Streaming not yet implemented for Resemble.AI');
  }

  @override
  Future<List<Voice>> getAvailableVoices() async {
    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    // Resemble.AI voices are cloned voices specific to the user's account
    // Return the configured voice
    return [
      Voice(
        id: _config['voiceUuid']!,
        name: 'Cloned Voice',
        description: 'Your custom cloned voice with emotional control',
        isCustom: true,
      ),
    ];
  }

  @override
  Map<String, String> get config => Map.unmodifiable(_config);

  @override
  bool get isInitialized => _isInitialized;
}
