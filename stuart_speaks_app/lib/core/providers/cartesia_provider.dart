import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/tts_request.dart';
import 'tts_provider.dart';

/// Cartesia AI TTS Provider implementation
class CartesiaProvider extends TTSProvider {
  static const String _baseUrl = 'https://api.cartesia.ai';
  static const String _ttsEndpoint = '$_baseUrl/tts/bytes';
  static const String _ttsStreamEndpoint = '$_baseUrl/tts/sse';
  static const String _apiVersion = '2024-06-10';

  Map<String, String> _config = {};
  bool _isInitialized = false;

  @override
  String get id => 'cartesia';

  @override
  String get name => 'Cartesia AI';

  @override
  String get description =>
      'High-performance, low-latency TTS with the Sonic 3 model. Ideal for real-time applications.';

  @override
  bool get supportsStreaming => true;

  @override
  List<ConfigField> getRequiredConfig() => [
        const ConfigField(
          key: 'apiKey',
          label: 'API Key',
          hint: 'Your Cartesia API key',
          isSecret: true,
          isRequired: true,
        ),
        const ConfigField(
          key: 'voiceId',
          label: 'Voice ID',
          hint: 'Voice identifier (UUID format)',
          isSecret: false,
          isRequired: true,
        ),
        const ConfigField(
          key: 'modelId',
          label: 'Model ID',
          hint: 'Model to use',
          isSecret: false,
          isRequired: false,
          defaultValue: 'sonic-3',
          options: ['sonic', 'sonic-turbo', 'sonic-2', 'sonic-3'],
        ),
        const ConfigField(
          key: 'container',
          label: 'Audio Container',
          hint: 'Audio format container',
          isSecret: false,
          isRequired: false,
          defaultValue: 'mp3',
          options: ['mp3', 'wav', 'raw'],
        ),
        const ConfigField(
          key: 'encoding',
          label: 'Audio Encoding',
          hint: 'For WAV format',
          isSecret: false,
          isRequired: false,
          defaultValue: 'pcm_s16le',
          options: ['pcm_s16le', 'pcm_f32le', 'mulaw'],
        ),
        const ConfigField(
          key: 'sampleRate',
          label: 'Sample Rate',
          hint: 'Audio sample rate in Hz',
          isSecret: false,
          isRequired: false,
          defaultValue: '44100',
          options: ['8000', '16000', '22050', '24000', '44100'],
        ),
        const ConfigField(
          key: 'language',
          label: 'Language',
          hint: 'Language code',
          isSecret: false,
          isRequired: false,
          defaultValue: 'en',
          options: ['en', 'es', 'fr', 'de', 'it', 'pt', 'pl', 'tr', 'ru', 'nl', 'cs', 'ar', 'zh', 'ja', 'ko', 'hi'],
        ),
        const ConfigField(
          key: 'speed',
          label: 'Speed',
          hint: 'Speech speed preset',
          isSecret: false,
          isRequired: false,
          defaultValue: 'normal',
          options: ['slowest', 'slow', 'normal', 'fast', 'fastest'],
        ),
        const ConfigField(
          key: 'speedValue',
          label: 'Speed Value',
          hint: '0.5-2.0 for generation_config',
          isSecret: false,
          isRequired: false,
          defaultValue: '1.0',
        ),
        const ConfigField(
          key: 'volume',
          label: 'Volume',
          hint: '0.0-2.0 (1.0 is normal)',
          isSecret: false,
          isRequired: false,
          defaultValue: '1.0',
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
    _config['modelId'] ??= 'sonic-3';
    _config['container'] ??= 'mp3'; // MP3 has better Android compatibility
    _config['encoding'] ??= 'pcm_s16le';
    _config['sampleRate'] ??= '44100';
    _config['language'] ??= 'en';
    _config['speed'] ??= 'normal';
    _config['speedValue'] ??= '1.0';
    _config['volume'] ??= '1.0';

    _isInitialized = true;
    return true;
  }

  @override
  Future<String?> validateCredentials() async {
    try {
      // Make a minimal TTS request to validate credentials
      final response = await http.post(
        Uri.parse(_ttsEndpoint),
        headers: {
          'Cartesia-Version': _apiVersion,
          'X-API-Key': _config['apiKey']!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'transcript': 'test',
          'model_id': _config['modelId'],
          'voice': {
            'mode': 'id',
            'id': _config['voiceId'],
          },
          'output_format': {
            'container': _config['container'],
            'encoding': _config['encoding'],
            'sample_rate': int.tryParse(_config['sampleRate'] ?? '44100') ?? 44100,
          },
          'language': _config['language'],
          'speed': _config['speed'] ?? 'normal',
          'generation_config': {
            'speed': double.tryParse(_config['speedValue'] ?? '1.0') ?? 1.0,
            'volume': double.tryParse(_config['volume'] ?? '1.0') ?? 1.0,
          },
        }),
      );

      if (response.statusCode == 200) {
        return null; // Valid
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return 'Invalid API key or access denied';
      } else if (response.statusCode == 404) {
        return 'Invalid voice ID or endpoint not found';
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
      final sampleRate = int.tryParse(_config['sampleRate'] ?? '44100') ?? 44100;
      final speedValue = double.tryParse(_config['speedValue'] ?? '1.0') ?? 1.0;
      final volume = double.tryParse(_config['volume'] ?? '1.0') ?? 1.0;

      // Build output_format based on container type
      final outputFormat = <String, dynamic>{
        'container': _config['container'],
        'sample_rate': sampleRate,
      };

      // Only include encoding for raw/wav containers, not for mp3
      final container = _config['container'];
      if (container == 'raw' || container == 'wav') {
        outputFormat['encoding'] = _config['encoding'];
      }

      final requestBody = <String, dynamic>{
        'transcript': request.text,
        'model_id': _config['modelId'],
        'voice': {
          'mode': 'id',
          'id': request.voiceId ?? _config['voiceId'],
        },
        'output_format': outputFormat,
        'language': _config['language'],
      };

      // Add speed parameter (can be a string like "normal" or numeric)
      final speed = _config['speed'] ?? 'normal';
      if (speed != 'normal') {
        requestBody['speed'] = speed;
      }

      // Add generation_config for fine-tuned control
      requestBody['generation_config'] = {
        'speed': speedValue,
        'volume': volume,
      };

      final response = await http.post(
        Uri.parse(_ttsEndpoint),
        headers: {
          'Cartesia-Version': _apiVersion,
          'X-API-Key': _config['apiKey']!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
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
  Stream<Uint8List>? generateSpeechStream(TTSRequest request) async* {
    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    try {
      final sampleRate = int.tryParse(_config['sampleRate'] ?? '44100') ?? 44100;
      final speedValue = double.tryParse(_config['speedValue'] ?? '1.0') ?? 1.0;
      final volume = double.tryParse(_config['volume'] ?? '1.0') ?? 1.0;

      final requestBody = <String, dynamic>{
        'transcript': request.text,
        'model_id': _config['modelId'],
        'voice': {
          'mode': 'id',
          'id': request.voiceId ?? _config['voiceId'],
        },
        'output_format': {
          'container': 'raw', // SSE only supports raw
          'encoding': _config['encoding'],
          'sample_rate': sampleRate,
        },
        'language': _config['language'],
        'generation_config': {
          'speed': speedValue,
          'volume': volume,
        },
      };

      // Use HTTP streaming (Server-Sent Events)
      final client = http.Client();
      try {
        final streamRequest = http.Request('POST', Uri.parse(_ttsStreamEndpoint));
        streamRequest.headers['Cartesia-Version'] = _apiVersion;
        streamRequest.headers['Authorization'] = 'Bearer ${_config['apiKey']!}';
        streamRequest.headers['Content-Type'] = 'application/json';
        streamRequest.body = jsonEncode(requestBody);

        final streamedResponse = await client.send(streamRequest);

        if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 204) {
          // Process Server-Sent Events stream - parse SSE format
          String buffer = '';

          await for (final chunk in streamedResponse.stream) {
            // Convert chunk to string and add to buffer
            buffer += utf8.decode(chunk, allowMalformed: true);

            // Process complete SSE events (separated by double newline)
            while (buffer.contains('\n\n')) {
              final eventEnd = buffer.indexOf('\n\n');
              final event = buffer.substring(0, eventEnd);
              buffer = buffer.substring(eventEnd + 2);

              // Parse SSE event to extract audio data
              final audioData = _parseSSEEvent(event);
              if (audioData != null && audioData.isNotEmpty) {
                yield audioData;
              }
            }
          }
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

  /// Parse SSE event to extract base64-encoded audio data
  Uint8List? _parseSSEEvent(String event) {
    // SSE format:
    // event: chunk
    // data: {"type":"chunk","status_code":206,"done":false,"data":"<base64>"}
    final lines = event.split('\n');
    String? eventType;
    String? jsonData;

    for (final line in lines) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        jsonData = line.substring(5).trim();
      }
    }

    // Only process 'chunk' events with data
    if (eventType == 'chunk' && jsonData != null && jsonData.isNotEmpty) {
      try {
        // Parse JSON to extract the base64-encoded audio
        final json = jsonDecode(jsonData) as Map<String, dynamic>;
        final audioBase64 = json['data'] as String?;

        if (audioBase64 != null && audioBase64.isNotEmpty) {
          // Decode base64 to get raw PCM audio bytes
          return base64Decode(audioBase64);
        }
      } catch (e) {
        // Silently ignore parse errors - likely malformed SSE events
        return null;
      }
    }

    return null;
  }

  @override
  Future<List<Voice>> getAvailableVoices() async {
    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    // Cartesia doesn't provide a voices listing endpoint in the basic API
    // Users can find voice IDs at play.cartesia.ai/voices
    return [
      Voice(
        id: _config['voiceId']!,
        name: 'Configured Voice',
        description: 'Your configured Cartesia voice model',
        isCustom: false,
      ),
    ];
  }

  @override
  Map<String, String> get config => Map.unmodifiable(_config);

  @override
  bool get isInitialized => _isInitialized;
}
