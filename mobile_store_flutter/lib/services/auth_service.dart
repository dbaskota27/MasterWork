import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static SupabaseClient get _db => Supabase.instance.client;

  // Cached session data
  static String? _storeId;
  static String? _role;
  static String? _displayName;

  static String? get userId      => _db.auth.currentUser?.id;
  static String? get userEmail   => _db.auth.currentUser?.email;
  static String? get storeId     => _storeId;
  static String? get role        => _role;
  static String? get displayName => _displayName;
  static bool get isLoggedIn     => _db.auth.currentUser != null && _storeId != null;
  static bool get isManager      => _role == 'manager';

  /// Load store_user data for the current auth user.
  /// Returns true if the user has a store linked.
  static Future<bool> loadProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return false;

    try {
      // Use RPC to bypass RLS — guaranteed to find the user's profile
      final rows = await _db.rpc('get_my_profile');
      final list = rows as List;

      if (list.isEmpty) {
        _storeId = null;
        _role = null;
        _displayName = null;
        return false;
      }

      final row = list.first as Map<String, dynamic>;
      _storeId     = row['store_id'] as String;
      _role        = row['role'] as String;
      _displayName = row['display_name'] as String?;
      return true;
    } catch (e) {
      _storeId = null;
      _role = null;
      _displayName = null;
      return false;
    }
  }

  /// Check if there's a valid Supabase session.
  static Future<bool> restoreSession() async {
    final session = _db.auth.currentSession;
    if (session == null) return false;
    return loadProfile();
  }

  // ── Sign Up (new store) ───────────────────────────────────────────────────

  static Future<void> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _db.auth.signUp(
      email: email.trim(),
      password: password,
    );
    if (response.user == null) {
      throw Exception('Sign up failed. Please try again.');
    }
  }

  // ── Log In ────────────────────────────────────────────────────────────────

  static Future<void> login({
    required String email,
    required String password,
  }) async {
    await _db.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await loadProfile();
  }

  // ── Password Recovery ─────────────────────────────────────────────────────

  static Future<void> sendPasswordReset(String email) async {
    await _db.auth.resetPasswordForEmail(email.trim());
  }

  // ── Log Out ───────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    _storeId = null;
    _role = null;
    _displayName = null;
    await _db.auth.signOut();
  }

  // ── Store Setup (called after signup) ─────────────────────────────────────

  static Future<void> createStore({
    required String storeName,
    required String address,
    required String phone,
    required String email,
    required String displayName,
    required String username,
    required String password,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Use RPC to create store + link user + create manager worker atomically
    await _db.rpc('create_store_with_owner', params: {
      'p_name':         storeName,
      'p_address':      address,
      'p_phone':        phone,
      'p_email':        email,
      'p_display_name': displayName,
      'p_username':     username,
      'p_password':     password,
    });

    // Refresh cached data
    await loadProfile();
  }

  // Worker management is now in WorkerService

  /// Change the current user's password.
  static Future<void> changePassword(String newPassword) async {
    await _db.auth.updateUser(UserAttributes(password: newPassword));
  }
}
