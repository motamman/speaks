import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/server_config.dart';

/// HTTP client with automatic session cookie management
class ApiClient {
  static const String _sessionCookieKey = 'session_cookie';

  final ServerConfig _serverConfig;
  final FlutterSecureStorage _secureStorage;

  String? _sessionCookie;

  ApiClient({
    required ServerConfig serverConfig,
    FlutterSecureStorage? secureStorage,
  })  : _serverConfig = serverConfig,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Initialize by loading saved session cookie
  Future<void> initialize() async {
    _sessionCookie = await _secureStorage.read(key: _sessionCookieKey);
  }

  /// Check if server is configured
  bool get isServerConfigured => _serverConfig.isConfigured;

  /// Check if we have a session cookie
  bool get hasSession => _sessionCookie != null;

  /// Get current session cookie (for debugging)
  String? get sessionCookie => _sessionCookie;

  /// Update session cookie (called after auth)
  Future<void> setSessionCookie(String? cookie) async {
    _sessionCookie = cookie;
    if (cookie != null) {
      await _secureStorage.write(key: _sessionCookieKey, value: cookie);
    } else {
      await _secureStorage.delete(key: _sessionCookieKey);
    }
  }

  /// Clear session (logout)
  Future<void> clearSession() async {
    _sessionCookie = null;
    await _secureStorage.delete(key: _sessionCookieKey);
  }

  /// Build headers including session cookie
  Map<String, String> _buildHeaders({Map<String, String>? additionalHeaders}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    return headers;
  }

  /// Extract and save session cookie from response
  Future<void> _handleResponseCookies(http.Response response) async {
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      // Parse the session cookie from Set-Cookie header
      // Format: "connect.sid=xxx; Path=/; HttpOnly" or similar
      final cookieParts = setCookie.split(';');
      if (cookieParts.isNotEmpty) {
        final sessionPart = cookieParts.first.trim();
        await setSessionCookie(sessionPart);
      }
    }
  }

  /// Make a GET request
  Future<ApiResponse> get(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) async {
    final url = _serverConfig.buildUrl(endpoint);
    if (url == null) {
      return ApiResponse.error('Server not configured');
    }

    try {
      Uri uri = Uri.parse(url);
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final response = await http.get(
        uri,
        headers: _buildHeaders(additionalHeaders: headers),
      );

      await _handleResponseCookies(response);

      return ApiResponse.fromHttpResponse(response);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Make a POST request
  Future<ApiResponse> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = _serverConfig.buildUrl(endpoint);
    if (url == null) {
      return ApiResponse.error('Server not configured');
    }

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _buildHeaders(additionalHeaders: headers),
        body: body != null ? jsonEncode(body) : null,
      );

      await _handleResponseCookies(response);

      return ApiResponse.fromHttpResponse(response);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Make a DELETE request
  Future<ApiResponse> delete(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    final url = _serverConfig.buildUrl(endpoint);
    if (url == null) {
      return ApiResponse.error('Server not configured');
    }

    try {
      final response = await http.delete(
        Uri.parse(url),
        headers: _buildHeaders(additionalHeaders: headers),
      );

      await _handleResponseCookies(response);

      return ApiResponse.fromHttpResponse(response);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }
}

/// Wrapper for API responses
class ApiResponse {
  final int? statusCode;
  final String? body;
  final bool isSuccess;
  final String? errorMessage;

  ApiResponse._({
    this.statusCode,
    this.body,
    required this.isSuccess,
    this.errorMessage,
  });

  factory ApiResponse.fromHttpResponse(http.Response response) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    return ApiResponse._(
      statusCode: response.statusCode,
      body: response.body,
      isSuccess: isSuccess,
      errorMessage: isSuccess ? null : 'HTTP ${response.statusCode}',
    );
  }

  factory ApiResponse.error(String message) {
    return ApiResponse._(
      isSuccess: false,
      errorMessage: message,
    );
  }

  /// Parse body as JSON
  dynamic get json {
    if (body == null) return null;
    try {
      return jsonDecode(body!);
    } catch (e) {
      return null;
    }
  }

  /// Parse body as JSON map
  Map<String, dynamic>? get jsonMap {
    final decoded = json;
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }

  /// Parse body as JSON list
  List<dynamic>? get jsonList {
    final decoded = json;
    if (decoded is List) {
      return decoded;
    }
    return null;
  }

  /// Check if response is unauthorized (401)
  bool get isUnauthorized => statusCode == 401;

  /// Check if response is forbidden (403)
  bool get isForbidden => statusCode == 403;

  /// Check if response is not found (404)
  bool get isNotFound => statusCode == 404;
}
