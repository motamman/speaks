import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/tts_request.dart';
import '../providers/cartesia_provider.dart';
import '../providers/elevenlabs_provider.dart';
import '../providers/fish_audio_provider.dart';
import '../providers/playht_provider.dart';
import '../providers/resemble_provider.dart';
import '../providers/tts_provider.dart';

/// Manages TTS providers and handles provider switching
class TTSProviderManager {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final Map<String, TTSProvider> _providers = {};
  TTSProvider? _activeProvider;

  static const String _activeProviderKey = 'active_tts_provider';

  TTSProviderManager() {
    _registerProviders();
  }

  /// Register all available TTS providers
  void _registerProviders() {
    // Register Fish.Audio provider
    _providers['fish_audio'] = FishAudioProvider();

    // Register Cartesia provider
    _providers['cartesia'] = CartesiaProvider();

    // Register ElevenLabs provider
    _providers['elevenlabs'] = ElevenLabsProvider();

    // Register Play.ht provider
    _providers['playht'] = PlayHtProvider();

    // Register Resemble.AI provider
    _providers['resemble'] = ResembleProvider();

    // TODO: Register other providers (Google, AWS Polly, Azure, etc.)
  }

  /// Get all available providers
  List<TTSProvider> get availableProviders => _providers.values.toList();

  /// Get provider by ID
  TTSProvider? getProvider(String providerId) => _providers[providerId];

  /// Get the currently active provider
  TTSProvider? get activeProvider => _activeProvider;

  /// Load saved provider configuration
  Future<void> loadSavedConfiguration() async {
    // Load active provider ID
    final activeProviderId = await _secureStorage.read(key: _activeProviderKey);

    if (activeProviderId != null && _providers.containsKey(activeProviderId)) {
      final provider = _providers[activeProviderId]!;

      // Load provider-specific configuration
      final config = await _loadProviderConfig(activeProviderId);

      if (config.isNotEmpty) {
        final initialized = await provider.initialize(config);
        if (initialized) {
          _activeProvider = provider;
        }
      }
    }
  }

  /// Load configuration for a specific provider
  Future<Map<String, String>> _loadProviderConfig(String providerId) async {
    final provider = _providers[providerId];
    if (provider == null) return {};

    final config = <String, String>{};

    for (final field in provider.getRequiredConfig()) {
      final value = await _secureStorage.read(
        key: '${providerId}_${field.key}',
      );
      if (value != null) {
        config[field.key] = value;
      }
    }

    return config;
  }

  /// Set and initialize a provider
  Future<bool> setActiveProvider(
    String providerId,
    Map<String, String> config,
  ) async {
    final provider = _providers[providerId];
    if (provider == null) {
      throw TTSProviderException(
        'Provider not found: $providerId',
        providerId: providerId,
      );
    }

    // Try to initialize the provider (will throw exception if invalid)
    await provider.initialize(config);

    // Save configuration
    await _saveProviderConfig(providerId, config);
    await _secureStorage.write(key: _activeProviderKey, value: providerId);

    _activeProvider = provider;
    return true;
  }

  /// Save provider configuration
  Future<void> _saveProviderConfig(
    String providerId,
    Map<String, String> config,
  ) async {
    for (final entry in config.entries) {
      await _secureStorage.write(
        key: '${providerId}_${entry.key}',
        value: entry.value,
      );
    }
  }

  /// Generate speech using the active provider
  Future<Uint8List> generateSpeech(String text) async {
    if (_activeProvider == null) {
      throw TTSProviderException('No active TTS provider configured');
    }

    final request = TTSRequest(text: text);
    return await _activeProvider!.generateSpeech(request);
  }

  /// Check if a provider is configured and ready
  Future<bool> isProviderReady(String providerId) async {
    final provider = _providers[providerId];
    if (provider == null) return false;

    if (!provider.isInitialized) {
      final config = await _loadProviderConfig(providerId);
      if (config.isEmpty) return false;

      final initialized = await provider.initialize(config);
      if (!initialized) return false;
    }

    return true;
  }

  /// Clear all saved configurations
  Future<void> clearAllConfigurations() async {
    await _secureStorage.deleteAll();
    _activeProvider = null;
  }
}
