import 'dart:convert';

import '../providers/tts_provider.dart';

/// Template for creating custom TTS providers from shared configurations
class ProviderTemplate {
  final String id;
  final String name;
  final String description;
  final String baseUrl;
  final bool supportsStreaming;
  final bool supportsVoiceCloning;
  final List<ConfigField> configFields;
  final Map<String, String> endpoints;
  final RequestFormat requestFormat;
  final ResponseFormat responseFormat;

  const ProviderTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.baseUrl,
    required this.supportsStreaming,
    required this.supportsVoiceCloning,
    required this.configFields,
    required this.endpoints,
    required this.requestFormat,
    required this.responseFormat,
  });

  /// Convert to JSON for sharing (.speakjson file)
  Map<String, dynamic> toJson({Map<String, String>? configValues}) {
    return {
      'version': '1.0',
      'provider': {
        'id': id,
        'name': name,
        'description': description,
        'baseUrl': baseUrl,
        'supportsStreaming': supportsStreaming,
        'supportsVoiceCloning': supportsVoiceCloning,
        'endpoints': endpoints,
        'configFields': configFields.map((f) => f.toJson(
          value: (configValues != null && !f.isSecret)
            ? configValues[f.key]
            : null,
        )).toList(),
        'requestFormat': requestFormat.toJson(),
        'responseFormat': responseFormat.toJson(),
      },
    };
  }

  /// Create from JSON (.speakjson file)
  factory ProviderTemplate.fromJson(Map<String, dynamic> json) {
    final provider = json['provider'] as Map<String, dynamic>;
    final configFieldsList = provider['configFields'] as List<dynamic>;

    return ProviderTemplate(
      id: provider['id'] as String,
      name: provider['name'] as String,
      description: provider['description'] as String,
      baseUrl: provider['baseUrl'] as String,
      supportsStreaming: provider['supportsStreaming'] as bool? ?? false,
      supportsVoiceCloning: provider['supportsVoiceCloning'] as bool? ?? false,
      endpoints: Map<String, String>.from(provider['endpoints'] as Map),
      configFields: configFieldsList
          .map((f) => ConfigFieldJson.fromJson(f as Map<String, dynamic>))
          .toList(),
      requestFormat: RequestFormat.fromJson(
        provider['requestFormat'] as Map<String, dynamic>,
      ),
      responseFormat: ResponseFormat.fromJson(
        provider['responseFormat'] as Map<String, dynamic>,
      ),
    );
  }

  /// Export to .speakjson file content
  String toSpeakJson({Map<String, String>? configValues}) {
    return const JsonEncoder.withIndent('  ').convert(toJson(configValues: configValues));
  }

  /// Import from .speakjson file content
  static ProviderTemplate fromSpeakJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return ProviderTemplate.fromJson(json);
  }
}

/// Extension to add JSON serialization to ConfigField
extension ConfigFieldJson on ConfigField {
  Map<String, dynamic> toJson({String? value}) {
    return {
      'key': key,
      'label': label,
      'hint': hint,
      'isSecret': isSecret,
      'isRequired': isRequired,
      if (defaultValue != null) 'defaultValue': defaultValue,
      if (options != null) 'options': options,
      if (value != null) 'value': value,
    };
  }

  static ConfigField fromJson(Map<String, dynamic> json) {
    return ConfigField(
      key: json['key'] as String,
      label: json['label'] as String,
      hint: json['hint'] as String,
      isSecret: json['isSecret'] as bool? ?? false,
      isRequired: json['isRequired'] as bool? ?? true,
      defaultValue: json['defaultValue'] as String?,
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }
}

/// HTTP request format configuration
class RequestFormat {
  final String method; // GET, POST, etc.
  final Map<String, String> headers; // Header templates with {placeholders}
  final Map<String, dynamic>? body; // JSON body template with {placeholders}

  const RequestFormat({
    required this.method,
    required this.headers,
    this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'headers': headers,
      if (body != null) 'body': body,
    };
  }

  factory RequestFormat.fromJson(Map<String, dynamic> json) {
    return RequestFormat(
      method: json['method'] as String,
      headers: Map<String, String>.from(json['headers'] as Map),
      body: json['body'] as Map<String, dynamic>?,
    );
  }
}

/// HTTP response format configuration
class ResponseFormat {
  final String type; // 'json', 'binary', 'base64'
  final String? audioField; // JSON field containing audio (for type='json')
  final String? encoding; // 'base64', 'binary'

  const ResponseFormat({
    required this.type,
    this.audioField,
    this.encoding,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (audioField != null) 'audioField': audioField,
      if (encoding != null) 'encoding': encoding,
    };
  }

  factory ResponseFormat.fromJson(Map<String, dynamic> json) {
    return ResponseFormat(
      type: json['type'] as String,
      audioField: json['audioField'] as String?,
      encoding: json['encoding'] as String?,
    );
  }
}
