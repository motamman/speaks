import 'dart:typed_data';

/// Request model for TTS generation
class TTSRequest {
  final String text;
  final String? voiceId;
  final double? speed;
  final double? pitch;
  final String format; // mp3, wav, opus, etc.
  final int? bitrate;

  // Fish.Audio specific parameters
  final double? temperature; // 0.0-1.0, controls randomness/creativity
  final double? topP; // 0.0-1.0, nucleus sampling for natural speech
  final String? latency; // 'normal' or 'balanced'
  final bool? useStreaming; // Use WebSocket streaming vs REST API

  const TTSRequest({
    required this.text,
    this.voiceId,
    this.speed,
    this.pitch,
    this.format = 'mp3',
    this.bitrate,
    this.temperature,
    this.topP,
    this.latency,
    this.useStreaming,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        if (voiceId != null) 'voiceId': voiceId,
        if (speed != null) 'speed': speed,
        if (pitch != null) 'pitch': pitch,
        'format': format,
        if (bitrate != null) 'bitrate': bitrate,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (latency != null) 'latency': latency,
      };
}

/// Response from TTS generation
class TTSResponse {
  final Uint8List audioData;
  final String format;
  final int? bitrate;
  final Duration? duration;

  const TTSResponse({
    required this.audioData,
    required this.format,
    this.bitrate,
    this.duration,
  });
}

/// Voice model information
class Voice {
  final String id;
  final String name;
  final String? language;
  final String? gender;
  final String? description;
  final bool isCustom;

  const Voice({
    required this.id,
    required this.name,
    this.language,
    this.gender,
    this.description,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'language': language,
        'gender': gender,
        'description': description,
        'isCustom': isCustom,
      };

  factory Voice.fromJson(Map<String, dynamic> json) => Voice(
        id: json['id'] as String,
        name: json['name'] as String,
        language: json['language'] as String?,
        gender: json['gender'] as String?,
        description: json['description'] as String?,
        isCustom: json['isCustom'] as bool? ?? false,
      );
}
