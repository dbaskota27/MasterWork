import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Stores and retrieves store info and user accounts from SharedPreferences.
/// Falls back to AppConfig defaults on first launch.
class SettingsService {
  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kStoreName    = 'store_name';
  static const _kStoreAddress = 'store_address';
  static const _kStorePhone   = 'store_phone';
  static const _kStoreEmail   = 'store_email';
  static const _kPaymentQr    = 'payment_qr';
  static const _kCurrency     = 'currency';
  static const _kTaxRate      = 'tax_rate';
  static const _kUsers        = 'users_json';

  // ── Store Info ────────────────────────────────────────────────────────────

  static Future<Map<String, String>> getStoreInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name':    prefs.getString(_kStoreName)    ?? AppConfig.storeName,
      'address': prefs.getString(_kStoreAddress) ?? AppConfig.storeAddress,
      'phone':   prefs.getString(_kStorePhone)   ?? AppConfig.storePhone,
      'email':   prefs.getString(_kStoreEmail)   ?? AppConfig.storeEmail,
      'payment_qr': prefs.getString(_kPaymentQr) ?? AppConfig.paymentQrLink,
      'currency':   prefs.getString(_kCurrency)  ?? AppConfig.currency,
      'tax_rate':   (prefs.getDouble(_kTaxRate) ?? AppConfig.taxRate).toString(),
    };
  }

  static Future<void> saveStoreInfo({
    required String name,
    required String address,
    required String phone,
    required String email,
    required String paymentQr,
    required String currency,
    required double taxRate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStoreName,    name);
    await prefs.setString(_kStoreAddress, address);
    await prefs.setString(_kStorePhone,   phone);
    await prefs.setString(_kStoreEmail,   email);
    await prefs.setString(_kPaymentQr,    paymentQr);
    await prefs.setString(_kCurrency,     currency);
    await prefs.setDouble(_kTaxRate,      taxRate);
  }

  // ── Users ─────────────────────────────────────────────────────────────────

  /// Returns map of { username -> { 'password': ..., 'role': 'manager'|'worker' } }
  static Future<Map<String, Map<String, String>>> getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUsers);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(
            k,
            (v as Map<String, dynamic>).map((k2, v2) => MapEntry(k2, v2 as String)),
          ));
    }
    // First launch — seed from AppConfig
    final defaults = Map<String, Map<String, String>>.from(
      AppConfig.users.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
    );
    await _saveUsers(defaults);
    return defaults;
  }

  static Future<void> _saveUsers(Map<String, Map<String, String>> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsers, jsonEncode(users));
  }

  /// Add or update a user. Username is stored lowercase.
  static Future<void> upsertUser({
    required String username,
    required String password,
    required String role,
  }) async {
    final users = await getUsers();
    users[username.trim().toLowerCase()] = {
      'password': password,
      'role': role,
    };
    await _saveUsers(users);
  }

  /// Delete a user by username.
  static Future<void> deleteUser(String username) async {
    final users = await getUsers();
    users.remove(username.toLowerCase());
    await _saveUsers(users);
  }

  /// Change password for an existing user.
  static Future<void> changePassword({
    required String username,
    required String newPassword,
  }) async {
    final users = await getUsers();
    final user = users[username.toLowerCase()];
    if (user == null) throw Exception('User not found');
    user['password'] = newPassword;
    await _saveUsers(users);
  }
}
