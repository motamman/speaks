import '../config/server_config.dart';
import 'api_client.dart';

/// Authentication status response
class AuthStatus {
  final bool isAuthenticated;
  final String? email;
  final String? authMethod; // 'email' or 'google'
  final String? name;

  AuthStatus({
    required this.isAuthenticated,
    this.email,
    this.authMethod,
    this.name,
  });

  factory AuthStatus.notAuthenticated() {
    return AuthStatus(isAuthenticated: false);
  }

  factory AuthStatus.fromJson(Map<String, dynamic> json) {
    return AuthStatus(
      isAuthenticated: json['authenticated'] == true,
      email: json['email'] as String?,
      authMethod: json['authMethod'] as String?,
      name: json['name'] as String?,
    );
  }
}

/// Result of authentication operations
class AuthResult {
  final bool success;
  final String? errorMessage;
  final AuthStatus? status;

  AuthResult._({
    required this.success,
    this.errorMessage,
    this.status,
  });

  factory AuthResult.success({AuthStatus? status}) {
    return AuthResult._(success: true, status: status);
  }

  factory AuthResult.failure(String message) {
    return AuthResult._(success: false, errorMessage: message);
  }
}

/// Service for handling authentication with the sync server
class AuthService {
  final ApiClient _apiClient;
  final ServerConfig _serverConfig;

  AuthStatus? _cachedStatus;

  AuthService({
    required ApiClient apiClient,
    required ServerConfig serverConfig,
  })  : _apiClient = apiClient,
        _serverConfig = serverConfig;

  /// Check if we have a cached authenticated status
  bool get isAuthenticated => _cachedStatus?.isAuthenticated ?? false;

  /// Get the current user's email
  String? get userEmail => _cachedStatus?.email;

  /// Get the authentication method
  String? get authMethod => _cachedStatus?.authMethod;

  /// Get the current auth status
  AuthStatus? get currentStatus => _cachedStatus;

  /// Check if server is configured
  bool get isServerConfigured => _serverConfig.isConfigured;

  /// Request a verification code to be sent to the email
  Future<AuthResult> requestVerificationCode(String email) async {
    if (!_serverConfig.isConfigured) {
      return AuthResult.failure('Server not configured');
    }

    final response = await _apiClient.post(
      '/api/auth/request-code',
      body: {'email': email.trim().toLowerCase()},
    );

    if (response.isSuccess) {
      return AuthResult.success();
    }

    // Parse error message from response
    final json = response.jsonMap;
    final errorMessage = json?['error'] as String? ??
        json?['message'] as String? ??
        'Failed to send verification code';

    return AuthResult.failure(errorMessage);
  }

  /// Verify the code and establish a session
  Future<AuthResult> verifyCode(String email, String code) async {
    if (!_serverConfig.isConfigured) {
      return AuthResult.failure('Server not configured');
    }

    final response = await _apiClient.post(
      '/api/auth/verify-code',
      body: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
      },
    );

    if (response.isSuccess) {
      // Refresh auth status after successful verification
      await checkAuthStatus();
      return AuthResult.success(status: _cachedStatus);
    }

    // Parse error message from response
    final json = response.jsonMap;
    final errorMessage = json?['error'] as String? ??
        json?['message'] as String? ??
        'Invalid or expired code';

    return AuthResult.failure(errorMessage);
  }

  /// Check current authentication status with the server
  Future<AuthStatus> checkAuthStatus() async {
    if (!_serverConfig.isConfigured) {
      _cachedStatus = AuthStatus.notAuthenticated();
      return _cachedStatus!;
    }

    final response = await _apiClient.get('/api/auth/status');

    if (response.isSuccess) {
      final json = response.jsonMap;
      if (json != null) {
        _cachedStatus = AuthStatus.fromJson(json);
        return _cachedStatus!;
      }
    }

    _cachedStatus = AuthStatus.notAuthenticated();
    return _cachedStatus!;
  }

  /// Logout and clear session
  Future<AuthResult> logout() async {
    if (!_serverConfig.isConfigured) {
      return AuthResult.failure('Server not configured');
    }

    final response = await _apiClient.post('/api/auth/logout');

    // Clear local session regardless of server response
    await _apiClient.clearSession();
    _cachedStatus = AuthStatus.notAuthenticated();

    if (response.isSuccess) {
      return AuthResult.success();
    }

    // Still return success since we cleared local session
    return AuthResult.success();
  }

  /// Get the Google OAuth URL to open in browser
  /// Returns null if server is not configured
  String? getGoogleAuthUrl() {
    return _serverConfig.buildUrl('/auth/google');
  }

  /// Clear cached status (e.g., when server URL changes)
  void clearCache() {
    _cachedStatus = null;
  }
}
