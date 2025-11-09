import '../providers/cartesia_provider.dart';
import '../providers/elevenlabs_provider.dart';
import '../providers/fish_audio_provider.dart';
import 'provider_template.dart';

/// Default provider templates for the built-in providers
class DefaultProviderTemplates {
  /// Get template for Cartesia provider
  static ProviderTemplate get cartesia {
    final provider = CartesiaProvider();
    return ProviderTemplate(
      id: provider.id,
      name: provider.name,
      description: provider.description,
      baseUrl: 'https://api.cartesia.ai',
      supportsStreaming: provider.supportsStreaming,
      supportsVoiceCloning: provider.supportsVoiceCloning,
      configFields: provider.getRequiredConfig(),
      endpoints: {
        'tts': '/tts/bytes',
        'ttsStream': '/tts/sse',
      },
      requestFormat: const RequestFormat(
        method: 'POST',
        headers: {
          'X-API-Key': '{apiKey}',
          'Cartesia-Version': '2024-06-10',
          'Content-Type': 'application/json',
        },
        body: {
          'model_id': '{modelId}',
          'transcript': '{text}',
          'voice': {
            'mode': 'id',
            'id': '{voiceId}',
          },
          'output_format': {
            'container': '{container}',
            'encoding': '{encoding}',
            'sample_rate': '{sampleRate}',
          },
          'language': '{language}',
        },
      ),
      responseFormat: const ResponseFormat(
        type: 'binary',
      ),
    );
  }

  /// Get template for ElevenLabs provider
  static ProviderTemplate get elevenlabs {
    final provider = ElevenLabsProvider();
    return ProviderTemplate(
      id: provider.id,
      name: provider.name,
      description: provider.description,
      baseUrl: 'https://api.elevenlabs.io',
      supportsStreaming: provider.supportsStreaming,
      supportsVoiceCloning: provider.supportsVoiceCloning,
      configFields: provider.getRequiredConfig(),
      endpoints: {
        'tts': '/v1/text-to-speech/{voiceId}',
        'voices': '/v1/voices',
      },
      requestFormat: const RequestFormat(
        method: 'POST',
        headers: {
          'xi-api-key': '{apiKey}',
          'Content-Type': 'application/json',
        },
        body: {
          'text': '{text}',
          'model_id': '{modelId}',
          'voice_settings': {
            'stability': '{stability}',
            'similarity_boost': '{similarityBoost}',
            'style': '{style}',
            'use_speaker_boost': '{useSpeakerBoost}',
          },
        },
      ),
      responseFormat: const ResponseFormat(
        type: 'binary',
      ),
    );
  }

  /// Get template for Fish Audio provider
  static ProviderTemplate get fishAudio {
    final provider = FishAudioProvider();
    return ProviderTemplate(
      id: provider.id,
      name: provider.name,
      description: provider.description,
      baseUrl: 'https://api.fish.audio',
      supportsStreaming: provider.supportsStreaming,
      supportsVoiceCloning: provider.supportsVoiceCloning,
      configFields: provider.getRequiredConfig(),
      endpoints: {
        'tts': '/v1/tts',
      },
      requestFormat: const RequestFormat(
        method: 'POST',
        headers: {
          'Authorization': 'Bearer {apiKey}',
          'Content-Type': 'application/json',
        },
        body: {
          'text': '{text}',
          'reference_id': '{modelId}',
          'format': '{format}',
          'mp3_bitrate': '{bitrate}',
          'latency': '{latency}',
        },
      ),
      responseFormat: const ResponseFormat(
        type: 'binary',
      ),
    );
  }

  /// Get all default provider templates
  static List<ProviderTemplate> get all => [
        cartesia,
        elevenlabs,
        fishAudio,
      ];

  /// Get template by ID
  static ProviderTemplate? getById(String id) {
    switch (id) {
      case 'cartesia':
        return cartesia;
      case 'elevenlabs':
        return elevenlabs;
      case 'fish_audio':
        return fishAudio;
      default:
        return null;
    }
  }
}
