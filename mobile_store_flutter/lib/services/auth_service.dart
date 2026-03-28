import 'package:shared_preferences/shared_preferences.dart';
import 'settings_service.dart';

class AuthService {
  static const _keyUsername = 'logged_in_username';
  static const _keyRole     = 'logged_in_role';

  static String? _username;
  static String? _role;

  static String? get username => _username;
  static String? get role     => _role;
  static bool get isLoggedIn  => _username != null;
  static bool get isManager   => _role == 'manager';

  /// Try to restore a saved session (call on app start).
  static Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final u = prefs.getString(_keyUsername);
    final r = prefs.getString(_keyRole);
    if (u != null && r != null) {
      _username = u;
      _role = r;
      return true;
    }
    return false;
  }

  /// Returns true on success, false on wrong credentials.
  static Future<bool> login(String username, String password) async {
    final users = await SettingsService.getUsers();
    final key = username.trim().toLowerCase();
    final entry = users[key];
    if (entry == null) return false;
    if (entry['password'] != password) return false;

    _username = key;
    _role = entry['role'];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, _username!);
    await prefs.setString(_keyRole, _role!);
    return true;
  }

  static Future<void> logout() async {
    _username = null;
    _role = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyRole);
  }

  /// Update the in-memory role after settings change (so UI reflects immediately).
  static void refreshRole(String newRole) => _role = newRole;
}
