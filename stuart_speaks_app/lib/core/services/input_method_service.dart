import 'package:shared_preferences/shared_preferences.dart';

/// Key for storing input method preference
const String _inputMethodKey = 'input_method';
const String _handednessKey = 'handedness';
const String _disableSystemKeyboardKey = 'disable_system_keyboard';
const String _inputModeKey = 'input_mode';

/// Input method options
enum InputMethod {
  wordWheel,
  spinnerKeyboard,
}

/// Handedness options
enum Handedness {
  right,
  left,
}

/// Input mode: hardware-keyboard driven vs touch-augmented
enum InputMode {
  typeOnly,
  typeAndTouch,
}

/// Service for managing the user's preferred input method
class InputMethodService {
  final SharedPreferences _prefs;

  InputMethodService(this._prefs);

  /// Get the current input method preference
  InputMethod getInputMethod() {
    // Spinner keyboard disabled for now - always return wordWheel
    // TODO: Re-enable when spinner keyboard is ready
    // final saved = _prefs.getString(_inputMethodKey);
    // if (saved == 'spinnerKeyboard') {
    //   return InputMethod.spinnerKeyboard;
    // }
    return InputMethod.wordWheel;
  }

  /// Set the input method preference
  Future<void> setInputMethod(InputMethod method) async {
    await _prefs.setString(
      _inputMethodKey,
      method == InputMethod.spinnerKeyboard ? 'spinnerKeyboard' : 'wordWheel',
    );
  }

  /// Check if spinner keyboard is enabled
  bool isSpinnerKeyboardEnabled() {
    return getInputMethod() == InputMethod.spinnerKeyboard;
  }

  /// Get the current handedness preference
  Handedness getHandedness() {
    final saved = _prefs.getString(_handednessKey);
    if (saved == 'left') {
      return Handedness.left;
    }
    return Handedness.right; // Default to right-handed
  }

  /// Set the handedness preference
  Future<void> setHandedness(Handedness handedness) async {
    await _prefs.setString(
      _handednessKey,
      handedness == Handedness.left ? 'left' : 'right',
    );
  }

  /// Check if left-handed
  bool isLeftHanded() {
    return getHandedness() == Handedness.left;
  }

  /// Get the current input mode preference
  InputMode getInputMode() {
    final saved = _prefs.getString(_inputModeKey);
    if (saved == 'typeAndTouch') {
      return InputMode.typeAndTouch;
    }
    return InputMode.typeOnly; // Default for hardware-keyboard users
  }

  /// Set the input mode preference
  Future<void> setInputMode(InputMode mode) async {
    await _prefs.setString(
      _inputModeKey,
      mode == InputMode.typeAndTouch ? 'typeAndTouch' : 'typeOnly',
    );
  }

  /// Get whether system keyboard is disabled
  bool isSystemKeyboardDisabled() {
    return _prefs.getBool(_disableSystemKeyboardKey) ?? false;
  }

  /// Set whether system keyboard is disabled
  Future<void> setSystemKeyboardDisabled(bool disabled) async {
    await _prefs.setBool(_disableSystemKeyboardKey, disabled);
  }
}
