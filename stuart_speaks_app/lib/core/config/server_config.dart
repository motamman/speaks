import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing server configuration (URL for sync backend)
class ServerConfig {
  static const String _keyServerUrl = 'sync_server_url';
  static const String _keyBasePath = 'sync_server_base_path';

  final SharedPreferences _prefs;

  ServerConfig(this._prefs);

  /// Get the configured server URL (e.g., "https://example.com:3003")
  /// Returns null if not configured
  String? getServerUrl() {
    return _prefs.getString(_keyServerUrl);
  }

  /// Set the server URL
  Future<bool> setServerUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return _prefs.remove(_keyServerUrl);
    }
    // Normalize URL - remove trailing slash
    String normalizedUrl = url.trim();
    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }
    return _prefs.setString(_keyServerUrl, normalizedUrl);
  }

  /// Get the base path (default: "/stuartvoice")
  String getBasePath() {
    return _prefs.getString(_keyBasePath) ?? '/stuartvoice';
  }

  /// Set the base path
  Future<bool> setBasePath(String path) {
    String normalizedPath = path.trim();
    // Ensure path starts with /
    if (!normalizedPath.startsWith('/')) {
      normalizedPath = '/$normalizedPath';
    }
    // Remove trailing slash
    if (normalizedPath.endsWith('/') && normalizedPath.length > 1) {
      normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
    }
    return _prefs.setString(_keyBasePath, normalizedPath);
  }

  /// Get the full base URL for API calls (serverUrl + basePath)
  /// Returns null if server URL is not configured
  String? getFullBaseUrl() {
    final serverUrl = getServerUrl();
    if (serverUrl == null) return null;
    return '$serverUrl${getBasePath()}';
  }

  /// Check if server is configured
  bool get isConfigured => getServerUrl() != null;

  /// Build a full URL for an API endpoint
  /// Returns null if server is not configured
  String? buildUrl(String endpoint) {
    final baseUrl = getFullBaseUrl();
    if (baseUrl == null) return null;

    // Ensure endpoint starts with /
    String normalizedEndpoint = endpoint;
    if (!normalizedEndpoint.startsWith('/')) {
      normalizedEndpoint = '/$normalizedEndpoint';
    }

    return '$baseUrl$normalizedEndpoint';
  }
}
