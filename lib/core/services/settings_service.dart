import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent user settings for transfer behavior.
class SettingsService {
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyRunInBackground = 'run_in_background';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  /// Whether to keep the screen on during transfers (wakelock).
  bool get keepScreenOn => _prefs.getBool(_keyKeepScreenOn) ?? true;

  /// Whether to run the app in the background during transfers (mobile only).
  /// Always false on Web since browser background execution is browser-managed.
  bool get runInBackground => kIsWeb ? false : (_prefs.getBool(_keyRunInBackground) ?? true);

  Future<void> setKeepScreenOn(bool value) async {
    await _prefs.setBool(_keyKeepScreenOn, value);
  }

  Future<void> setRunInBackground(bool value) async {
    if (kIsWeb) return; // Not applicable on Web
    await _prefs.setBool(_keyRunInBackground, value);
  }
}
