import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

class AuthService {
  static SupabaseClient get _db => Supabase.instance.client;
  // Separate client for creating worker accounts without signing out the manager
  static final SupabaseClient _adminClient = SupabaseClient(
    AppConfig.supabaseUrl,
    AppConfig.supabaseAnonKey,
  );

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
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Use RPC to create store + link user atomically (bypasses RLS)
    await _db.rpc('create_store_with_owner', params: {
      'p_name':         storeName,
      'p_address':      address,
      'p_phone':        phone,
      'p_email':        email,
      'p_display_name': displayName,
    });

    // Refresh cached data
    await loadProfile();
  }

  // ── Worker Management ─────────────────────────────────────────────────────

  /// Create a worker account and link to the manager's store.
  /// Uses a separate client so the manager stays logged in.
  static Future<void> createWorker({
    required String email,
    required String password,
    required String displayName,
    required String role,
  }) async {
    if (_storeId == null) throw Exception('No store linked');

    // Create auth user using a separate client (manager stays signed in)
    final response = await _adminClient.auth.signUp(
      email: email.trim(),
      password: password,
    );

    final workerId = response.user?.id;
    if (workerId == null) {
      throw Exception('Failed to create worker account.');
    }

    // Sign out the separate client so it doesn't hold a session
    await _adminClient.auth.signOut();

    // Link worker to manager's store via RPC
    await _db.rpc('add_worker_to_store', params: {
      'p_worker_user_id': workerId,
      'p_display_name': displayName,
      'p_role': role,
    });
  }

  /// Get all users for the current store via RPC.
  static Future<List<Map<String, dynamic>>> getStoreUsers() async {
    if (_storeId == null) return [];
    final rows = await _db.rpc('get_store_workers');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Update a store user's role or display name via RPC.
  static Future<void> updateStoreUser(String id, {required String displayName, required String role}) async {
    await _db.rpc('update_worker', params: {
      'p_id': id,
      'p_display_name': displayName,
      'p_role': role,
    });
  }

  /// Delete a store user via RPC.
  static Future<void> deleteStoreUser(String id) async {
    await _db.rpc('delete_worker', params: {'p_id': id});
  }

  /// Change the current user's password.
  static Future<void> changePassword(String newPassword) async {
    await _db.auth.updateUser(UserAttributes(password: newPassword));
  }
}
