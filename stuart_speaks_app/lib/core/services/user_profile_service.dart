import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing user profile data (first name, last name)
class UserProfileService {
  static const String _keyFirstName = 'user_first_name';
  static const String _keyLastName = 'user_last_name';

  final SharedPreferences _prefs;

  UserProfileService(this._prefs);

  /// Get user's first name
  String getFirstName() {
    return _prefs.getString(_keyFirstName) ?? 'Stuart';
  }

  /// Get user's last name
  String getLastName() {
    return _prefs.getString(_keyLastName) ?? '';
  }

  /// Set user's first name
  Future<bool> setFirstName(String firstName) {
    return _prefs.setString(_keyFirstName, firstName.trim());
  }

  /// Set user's last name
  Future<bool> setLastName(String lastName) {
    return _prefs.setString(_keyLastName, lastName.trim());
  }

  /// Get the app title (FirstName + " Speaks")
  String getAppTitle() {
    final firstName = getFirstName();
    return '$firstName Speaks';
  }
}
