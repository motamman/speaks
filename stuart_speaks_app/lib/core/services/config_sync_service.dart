import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'tts_provider_manager.dart';

/// Service for synchronizing TTS provider configurations with the server
class ConfigSyncService {
  final ApiClient _apiClient;
  final AuthService _authService;
  final TTSProviderManager _providerManager;
  final FlutterSecureStorage _secureStorage;

  static const String _activeProviderKey = 'active_tts_provider';

  // Known built-in provider IDs
  static const List<String> _builtInProviderIds = [
    'fish_audio',
    'cartesia',
    'elevenlabs',
    'playht',
    'resemble',
  ];

  ConfigSyncService({
    required ApiClient apiClient,
    required AuthService authService,
    required TTSProviderManager providerManager,
    FlutterSecureStorage? secureStorage,
  })  : _apiClient = apiClient,
        _authService = authService,
        _providerManager = providerManager,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Check if sync is available (authenticated and server configured)
  bool get canSync =>
      _authService.isAuthenticated && _apiClient.isServerConfigured;

  /// Upload current TTS provider configuration to server
  Future<bool> uploadConfig() async {
    if (!canSync) return false;

    try {
      final config = await _gatherLocalConfig();

      final response = await _apiClient.post(
        '/api/config',
        body: config,
      );

      return response.isSuccess;
    } catch (e) {
      return false;
    }
  }

  /// Download TTS provider configuration from server
  Future<bool> downloadConfig() async {
    if (!canSync) return false;

    try {
      final response = await _apiClient.get('/api/config');

      if (!response.isSuccess) return false;

      final config = response.jsonMap;
      if (config == null) return false;

      await _applyRemoteConfig(config);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sync configuration (download from server, prefer remote)
  /// Call this after login to get configs from server
  Future<bool> syncConfig() async {
    // For sync, we download remote config (it takes precedence)
    // This is called after login on a new device
    return await downloadConfig();
  }

  /// Gather all local TTS provider configuration
  Future<Map<String, dynamic>> _gatherLocalConfig() async {
    final providers = <String, Map<String, String>>{};

    // Get active provider ID
    final activeProviderId = await _secureStorage.read(key: _activeProviderKey);

    // Gather config for all known providers
    for (final providerId in _builtInProviderIds) {
      final provider = _providerManager.getProvider(providerId);
      if (provider != null) {
        final config = await _loadProviderConfig(providerId, provider);
        if (config.isNotEmpty) {
          providers[providerId] = config;
        }
      }
    }

    // Also gather config for any custom providers that are currently registered
    for (final provider in _providerManager.availableProviders) {
      if (!_builtInProviderIds.contains(provider.id)) {
        final config = await _loadProviderConfig(provider.id, provider);
        if (config.isNotEmpty) {
          providers[provider.id] = config;
        }
      }
    }

    return {
      'activeProviderId': activeProviderId,
      'providers': providers,
    };
  }

  /// Load configuration for a specific provider from secure storage
  Future<Map<String, String>> _loadProviderConfig(
    String providerId,
    dynamic provider,
  ) async {
    final config = <String, String>{};

    // Get required config fields from provider
    List<dynamic> requiredFields = [];
    try {
      requiredFields = provider.getRequiredConfig();
    } catch (e) {
      // Provider doesn't have getRequiredConfig, skip
      return config;
    }

    for (final field in requiredFields) {
      final key = field.key as String;
      final value = await _secureStorage.read(key: '${providerId}_$key');
      if (value != null) {
        config[key] = value;
      }
    }

    return config;
  }

  /// Apply remote configuration to local secure storage
  Future<void> _applyRemoteConfig(Map<String, dynamic> config) async {
    final activeProviderId = config['activeProviderId'] as String?;
    final providers = config['providers'] as Map<String, dynamic>?;

    // Apply provider configurations
    if (providers != null) {
      for (final entry in providers.entries) {
        final providerId = entry.key;
        final providerConfig = entry.value as Map<String, dynamic>?;

        if (providerConfig != null) {
          for (final configEntry in providerConfig.entries) {
            await _secureStorage.write(
              key: '${providerId}_${configEntry.key}',
              value: configEntry.value.toString(),
            );
          }
        }
      }
    }

    // Set active provider
    if (activeProviderId != null) {
      await _secureStorage.write(
        key: _activeProviderKey,
        value: activeProviderId,
      );
    }

    // Reload provider manager configuration
    await _providerManager.loadSavedConfiguration();
  }

  /// Clear synced configuration (on logout)
  /// Note: This doesn't clear local config, just any sync state
  Future<void> clearSyncState() async {
    // Currently no sync state to clear
    // In future, could track last sync time, etc.
  }
}
