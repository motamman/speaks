import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/tts_request.dart';
import 'tts_provider.dart';

/// ElevenLabs TTS Provider implementation with streaming support
class ElevenLabsProvider extends TTSProvider {
  static const String _baseUrl = 'https://api.elevenlabs.io';
  static const String _streamEndpoint = '$_baseUrl/v1/text-to-speech';
  // WebSocket endpoint for future implementation:
  // static const String _wsBaseUrl = 'wss://api.elevenlabs.io';

  Map<String, String> _config = {};
  bool _isInitialized = false;

  @override
  String get id => 'elevenlabs';

  @override
  String get name => 'ElevenLabs';

  @override
  String get description =>
      'High-quality, natural-sounding voices with WebSocket streaming. Best for professional voiceovers and audiobooks.';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsVoiceCloning => true;

  @override
  List<ConfigField> getRequiredConfig() => [
        const ConfigField(
          key: 'apiKey',
          label: 'API Key',
          hint: 'Your ElevenLabs API key (xi-api-key)',
          isSecret: true,
          isRequired: true,
        ),
        const ConfigField(
          key: 'voiceId',
          label: 'Voice ID',
          hint: 'Voice identifier (e.g., 21m00Tcm4TlvDq8ikWAM)',
          isSecret: false,
          isRequired: true,
        ),
        const ConfigField(
          key: 'modelId',
          label: 'Model ID',
          hint: 'Model to use',
          isSecret: false,
          isRequired: false,
          defaultValue: 'eleven_multilingual_v2',
          options: [
            'eleven_multilingual_v2',
            'eleven_turbo_v2_5',
            'eleven_turbo_v2',
            'eleven_flash_v2_5',
            'eleven_english_sts_v2',
          ],
        ),
        const ConfigField(
          key: 'outputFormat',
          label: 'Output Format',
          hint: 'Audio format',
          isSecret: false,
          isRequired: false,
          defaultValue: 'mp3_44100_128',
          options: [
            'mp3_44100_128',
            'mp3_44100_192',
            'pcm_16000',
            'pcm_22050',
            'pcm_24000',
            'pcm_44100',
          ],
        ),
        const ConfigField(
          key: 'stability',
          label: 'Stability',
          hint: '0.0-1.0 (controls consistency)',
          isSecret: false,
          isRequired: false,
          defaultValue: '0.5',
        ),
        const ConfigField(
          key: 'similarityBoost',
          label: 'Similarity Boost',
          hint: '0.0-1.0 (enhances voice clarity)',
          isSecret: false,
          isRequired: false,
          defaultValue: '0.75',
        ),
        const ConfigField(
          key: 'style',
          label: 'Style',
          hint: '0.0-1.0 (expressiveness)',
          isSecret: false,
          isRequired: false,
          defaultValue: '0.0',
        ),
        const ConfigField(
          key: 'useSpeakerBoost',
          label: 'Speaker Boost',
          hint: 'Enable speaker boost',
          isSecret: false,
          isRequired: false,
          defaultValue: 'true',
          options: ['true', 'false'],
        ),
        const ConfigField(
          key: 'optimizeStreamingLatency',
          label: 'Optimize Latency',
          hint: '0-4 (higher = lower latency)',
          isSecret: false,
          isRequired: false,
          defaultValue: '0',
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
    if (!_config.containsKey('voiceId') || _config['voiceId']!.isEmpty) {
      throw TTSProviderException(
        'Voice ID is required',
        providerId: id,
      );
    }

    // Set defaults
    _config['modelId'] ??= 'eleven_multilingual_v2';
    _config['outputFormat'] ??= 'mp3_44100_128';
    _config['stability'] ??= '0.5';
    _config['similarityBoost'] ??= '0.75';
    _config['style'] ??= '0.0';
    _config['useSpeakerBoost'] ??= 'true';
    _config['optimizeStreamingLatency'] ??= '0';

    _isInitialized = true;
    return true;
  }

  @override
  Future<String?> validateCredentials() async {
    try {
      // Make a minimal TTS request to validate credentials
      final voiceId = _config['voiceId']!;
      final outputFormat = _config['outputFormat']!;
      final optimizeLatency = int.tryParse(_config['optimizeStreamingLatency'] ?? '0') ?? 0;

      final uri = Uri.parse('$_streamEndpoint/$voiceId/stream').replace(
        queryParameters: {
          'output_format': outputFormat,
          'optimize_streaming_latency': optimizeLatency.toString(),
        },
      );

      final response = await http.post(
        uri,
        headers: {
          'xi-api-key': _config['apiKey']!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': 'test',
          'model_id': _config['modelId'],
        }),
      );

      if (response.statusCode == 200) {
        return null; // Valid
      } else if (response.statusCode == 401) {
        return 'Invalid API key';
      } else if (response.statusCode == 404) {
        return 'Invalid voice ID';
      } else if (response.statusCode == 400) {
        try {
          final error = jsonDecode(response.body);
          return 'Invalid request: ${error['detail']?['message'] ?? response.body}';
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
      final voiceId = request.voiceId ?? _config['voiceId']!;
      final outputFormat = _config['outputFormat']!;
      final optimizeLatency = int.tryParse(_config['optimizeStreamingLatency'] ?? '0') ?? 0;

      // Build voice settings
      final stability = double.tryParse(_config['stability'] ?? '0.5') ?? 0.5;
      final similarityBoost = double.tryParse(_config['similarityBoost'] ?? '0.75') ?? 0.75;
      final style = double.tryParse(_config['style'] ?? '0.0') ?? 0.0;
      final useSpeakerBoost = (_config['useSpeakerBoost'] ?? 'true').toLowerCase() == 'true';

      final voiceSettings = <String, dynamic>{
        'stability': stability,
        'similarity_boost': similarityBoost,
        'style': style,
        'use_speaker_boost': useSpeakerBoost,
      };

      // Add speed if provided in request
      if (request.speed != null) {
        voiceSettings['speed'] = request.speed!;
      }

      final requestBody = {
        'text': request.text,
        'model_id': _config['modelId'],
        'voice_settings': voiceSettings,
      };

      final uri = Uri.parse('$_streamEndpoint/$voiceId/stream').replace(
        queryParameters: {
          'output_format': outputFormat,
          'optimize_streaming_latency': optimizeLatency.toString(),
        },
      );

      final response = await http.post(
        uri,
        headers: {
          'xi-api-key': _config['apiKey']!,
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
      } else if (response.statusCode == 422) {
        try {
          final error = jsonDecode(response.body);
          throw TTSProviderException(
            'Validation error: ${error['detail']?['message'] ?? response.body}',
            providerId: id,
            statusCode: response.statusCode,
          );
        } catch (e) {
          throw TTSProviderException(
            'Validation error',
            providerId: id,
            statusCode: response.statusCode,
          );
        }
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
      final voiceId = request.voiceId ?? _config['voiceId']!;
      final modelId = _config['modelId'] ?? 'eleven_multilingual_v2';

      // Use HTTP streaming endpoint with /stream
      final uri = Uri.parse('$_streamEndpoint/$voiceId/stream');

      final stability = double.tryParse(_config['stability'] ?? '0.5') ?? 0.5;
      final similarityBoost = double.tryParse(_config['similarityBoost'] ?? '0.75') ?? 0.75;
      final style = double.tryParse(_config['style'] ?? '0.0') ?? 0.0;
      final useSpeakerBoost = _config['useSpeakerBoost'] == 'true';

      final outputFormat = _config['outputFormat'] ?? 'mp3_44100_128';

      final requestBody = {
        'text': request.text,
        'model_id': modelId,
        'voice_settings': {
          'stability': stability,
          'similarity_boost': similarityBoost,
          'style': style,
          'use_speaker_boost': useSpeakerBoost,
        },
      };

      // Add output_format as query parameter
      final uriWithParams = uri.replace(
        queryParameters: {
          'output_format': outputFormat,
          'optimize_streaming_latency': '0',
        },
      );

      final client = http.Client();
      try {
        final streamRequest = http.Request('POST', uriWithParams);
        streamRequest.headers['xi-api-key'] = _config['apiKey']!;
        streamRequest.headers['Content-Type'] = 'application/json';
        streamRequest.body = jsonEncode(requestBody);

        final streamedResponse = await client.send(streamRequest);

        if (streamedResponse.statusCode == 200) {
          // Stream MP3 chunks directly
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
        } else if (streamedResponse.statusCode == 422) {
          throw TTSProviderException(
            'Validation error - check voice ID and settings',
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

    try {
      // ElevenLabs provides a voices endpoint
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/voices'),
        headers: {
          'xi-api-key': _config['apiKey']!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final voicesList = data['voices'] as List;

        return voicesList.map((voice) {
          return Voice(
            id: voice['voice_id'] as String,
            name: voice['name'] as String,
            description: voice['description'] as String?,
            language: voice['labels']?['accent'] as String?,
            gender: voice['labels']?['gender'] as String?,
            isCustom: voice['category'] == 'cloned',
          );
        }).toList();
      } else {
        // If we can't fetch voices, return the configured one
        return [
          Voice(
            id: _config['voiceId']!,
            name: 'Configured Voice',
            description: 'Your configured ElevenLabs voice',
            isCustom: false,
          ),
        ];
      }
    } catch (e) {
      // Fallback to configured voice if API call fails
      return [
        Voice(
          id: _config['voiceId']!,
          name: 'Configured Voice',
          description: 'Your configured ElevenLabs voice',
          isCustom: false,
        ),
      ];
    }
  }

  @override
  Map<String, String> get config => Map.unmodifiable(_config);

  @override
  bool get isInitialized => _isInitialized;
}
