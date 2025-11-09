import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/provider_template.dart';
import '../models/tts_request.dart';
import 'tts_provider.dart';

/// Dynamic TTS provider that loads configuration from templates
class DynamicTTSProvider extends TTSProvider {
  final ProviderTemplate template;
  Map<String, String> _config = {};
  bool _isInitialized = false;

  DynamicTTSProvider(this.template);

  @override
  String get id => template.id;

  @override
  String get name => template.name;

  @override
  String get description => template.description;

  @override
  bool get supportsStreaming => template.supportsStreaming;

  @override
  bool get supportsVoiceCloning => template.supportsVoiceCloning;

  @override
  List<ConfigField> getRequiredConfig() => template.configFields;

  @override
  Map<String, String> get config => Map.unmodifiable(_config);

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<bool> initialize(Map<String, String> config) async {
    _config = Map.from(config);
    _isInitialized = true;
    return true;
  }

  @override
  Future<String?> validateCredentials() async {
    if (!_isInitialized) {
      return 'Provider not initialized';
    }

    // Check all required fields are present
    for (final field in template.configFields) {
      if (field.isRequired && (_config[field.key]?.isEmpty ?? true)) {
        return 'Missing required field: ${field.label}';
      }
    }

    // Try making a test request if validation endpoint exists
    // For now, just validate fields are present
    return null;
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
      final endpoint = template.endpoints['tts'];
      if (endpoint == null) {
        throw TTSProviderException(
          'TTS endpoint not configured',
          providerId: id,
        );
      }

      // Build URL
      final url = Uri.parse('${template.baseUrl}${_replacePlaceholders(endpoint, request.text)}');

      // Build headers
      final headers = <String, String>{};
      template.requestFormat.headers.forEach((key, value) {
        headers[key] = _replacePlaceholders(value, request.text);
      });

      // Build request body
      dynamic body;
      if (template.requestFormat.body != null) {
        body = _replacePlaceholdersInMap(template.requestFormat.body!, request.text);

        // For Cartesia, fix numeric types
        if (id.startsWith('cartesia') && body is Map) {
          if (body['output_format'] is Map) {
            // Parse sample_rate to integer
            final sampleRateStr = body['output_format']['sample_rate'];
            if (sampleRateStr is String) {
              body['output_format']['sample_rate'] = int.tryParse(sampleRateStr) ?? 44100;
            }
          }

          // Add generation_config
          final speedValue = double.tryParse(_config['speedValue'] ?? '1.0') ?? 1.0;
          final volume = double.tryParse(_config['volume'] ?? '1.0') ?? 1.0;
          body['generation_config'] = {
            'speed': speedValue,
            'volume': volume,
          };

          // Add speed parameter if it's not 'normal'
          final speed = _config['speed'] ?? 'normal';
          if (speed != 'normal') {
            body['speed'] = speed;
          }
        }
      }

      // Make request
      final response = await http.post(
        url,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Handle response based on format
        return _processResponse(response);
      } else {
        throw TTSProviderException(
          'Request failed: ${response.statusCode} ${response.reasonPhrase}',
          providerId: id,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is TTSProviderException) rethrow;
      throw TTSProviderException(
        'Error generating speech: ${e.toString()}',
        providerId: id,
        originalError: e,
      );
    }
  }

  /// Process response based on template format
  Uint8List _processResponse(http.Response response) {
    switch (template.responseFormat.type) {
      case 'binary':
        return response.bodyBytes;

      case 'base64':
        return base64Decode(response.body);

      case 'json':
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final audioField = template.responseFormat.audioField;
        if (audioField == null) {
          throw TTSProviderException(
            'Audio field not specified for JSON response',
            providerId: id,
          );
        }

        final audioData = json[audioField];
        if (audioData == null) {
          throw TTSProviderException(
            'Audio field "$audioField" not found in response',
            providerId: id,
          );
        }

        // Check encoding
        if (template.responseFormat.encoding == 'base64') {
          return base64Decode(audioData as String);
        } else {
          // Assume binary
          return Uint8List.fromList((audioData as List).cast<int>());
        }

      default:
        throw TTSProviderException(
          'Unknown response format: ${template.responseFormat.type}',
          providerId: id,
        );
    }
  }

  /// Replace placeholders like {text}, {apiKey}, etc. with actual values
  String _replacePlaceholders(String template, String text) {
    var result = template;

    // Replace {text} with the actual text
    result = result.replaceAll('{text}', text);

    // Replace config values like {apiKey}, {voiceId}, etc.
    _config.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });

    return result;
  }

  /// Replace placeholders in a map (for JSON body)
  Map<String, dynamic> _replacePlaceholdersInMap(Map<String, dynamic> map, String text) {
    final result = <String, dynamic>{};

    map.forEach((key, value) {
      if (value is String) {
        result[key] = _replacePlaceholders(value, text);
      } else if (value is Map<String, dynamic>) {
        result[key] = _replacePlaceholdersInMap(value, text);
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is String) {
            return _replacePlaceholders(item, text);
          } else if (item is Map<String, dynamic>) {
            return _replacePlaceholdersInMap(item, text);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  @override
  Stream<Uint8List>? generateSpeechStream(TTSRequest request) async* {
    if (!template.supportsStreaming) {
      throw UnimplementedError('Streaming not supported by this provider');
    }

    if (!_isInitialized) {
      throw TTSProviderException(
        'Provider not initialized',
        providerId: id,
      );
    }

    try {
      final endpoint = template.endpoints['ttsStream'] ?? template.endpoints['tts'];
      if (endpoint == null) {
        throw TTSProviderException(
          'Streaming endpoint not configured',
          providerId: id,
        );
      }

      // Build URL
      final url = Uri.parse('${template.baseUrl}${_replacePlaceholders(endpoint, request.text)}');

      // Build headers
      final headers = <String, String>{};
      template.requestFormat.headers.forEach((key, value) {
        headers[key] = _replacePlaceholders(value, request.text);
      });

      // Build request body with streaming-specific overrides
      dynamic body;
      if (template.requestFormat.body != null) {
        body = _replacePlaceholdersInMap(template.requestFormat.body!, request.text);

        // For Cartesia streaming, apply specific fixes
        if (id.startsWith('cartesia') && body is Map) {
          // Override container to 'raw' for SSE endpoint
          if (body['output_format'] is Map) {
            body['output_format']['container'] = 'raw';

            // Parse sample_rate to integer
            final sampleRateStr = body['output_format']['sample_rate'];
            if (sampleRateStr is String) {
              body['output_format']['sample_rate'] = int.tryParse(sampleRateStr) ?? 44100;
            }
          }

          // Add generation_config
          final speedValue = double.tryParse(_config['speedValue'] ?? '1.0') ?? 1.0;
          final volume = double.tryParse(_config['volume'] ?? '1.0') ?? 1.0;
          body['generation_config'] = {
            'speed': speedValue,
            'volume': volume,
          };

          // Add speed parameter if it's not 'normal'
          final speed = _config['speed'] ?? 'normal';
          if (speed != 'normal') {
            body['speed'] = speed;
          }
        }
      }

      // Make streaming request
      final client = http.Client();
      final streamRequest = http.Request(template.requestFormat.method, url);
      streamRequest.headers.addAll(headers);
      if (body != null) {
        streamRequest.body = jsonEncode(body);
      }

      final streamedResponse = await client.send(streamRequest);

      if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201 || streamedResponse.statusCode == 204) {
        // For Cartesia SSE streaming, parse the SSE events
        if (id.startsWith('cartesia') && endpoint.contains('sse')) {
          String buffer = '';
          await for (final chunk in streamedResponse.stream) {
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
          // Stream the response bytes directly
          await for (final chunk in streamedResponse.stream) {
            yield Uint8List.fromList(chunk);
          }
        }
      } else {
        throw TTSProviderException(
          'Streaming request failed: ${streamedResponse.statusCode}',
          providerId: id,
          statusCode: streamedResponse.statusCode,
        );
      }

      client.close();
    } catch (e) {
      if (e is TTSProviderException) rethrow;
      throw TTSProviderException(
        'Streaming error: ${e.toString()}',
        providerId: id,
        originalError: e,
      );
    }
  }

  /// Parse SSE event to extract audio data (for Cartesia)
  Uint8List? _parseSSEEvent(String event) {
    try {
      // SSE format: "data: {...}\n"
      final lines = event.split('\n');
      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6); // Remove "data: " prefix
          if (jsonStr.trim() == '[DONE]') {
            return null; // End of stream
          }

          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final audioBase64 = json['data'] as String?;

          if (audioBase64 != null && audioBase64.isNotEmpty) {
            return base64Decode(audioBase64);
          }
        }
      }
    } catch (e) {
      // Ignore parse errors for incomplete events
    }
    return null;
  }

  @override
  Future<List<Voice>> getAvailableVoices() async {
    // Dynamic providers don't support voice listing by default
    return [];
  }
}
