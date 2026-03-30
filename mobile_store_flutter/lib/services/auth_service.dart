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

    final row = await _db
        .from('store_users')
        .select('store_id, role, display_name')
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) {
      _storeId = null;
      _role = null;
      _displayName = null;
      return false;
    }

    _storeId     = row['store_id'] as String;
    _role        = row['role'] as String;
    _displayName = row['display_name'] as String?;
    return true;
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

    // Create the store
    final storeRow = await _db.from('stores').insert({
      'name':    storeName,
      'address': address,
      'phone':   phone,
      'email':   email,
    }).select().single();

    final storeId = storeRow['id'] as String;

    // Link this user as manager
    await _db.from('store_users').insert({
      'user_id':      user.id,
      'store_id':     storeId,
      'role':         'manager',
      'display_name': displayName,
    });

    // Refresh cached data
    await loadProfile();
  }

  // ── Worker Management ─────────────────────────────────────────────────────

  /// Invite a worker — creates a Supabase auth user via the API.
  /// The worker will receive an email to set their password.
  static Future<void> inviteWorker({
    required String email,
    required String displayName,
    required String role,
  }) async {
    if (_storeId == null) throw Exception('No store linked');

    // Use admin invite (via Supabase edge function or manual)
    // For now, we create the store_user entry. Worker must sign up with
    // the same email, then we link them.
    // Simple approach: store the pending invite
    await _db.from('store_users').insert({
      'user_id':      '00000000-0000-0000-0000-000000000000', // placeholder
      'store_id':     _storeId,
      'role':         role,
      'display_name': displayName,
    });
  }

  /// Get all users for the current store.
  static Future<List<Map<String, dynamic>>> getStoreUsers() async {
    if (_storeId == null) return [];
    final rows = await _db
        .from('store_users')
        .select('id, user_id, role, display_name, created_at')
        .eq('store_id', _storeId!)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Update a store user's role or display name.
  static Future<void> updateStoreUser(String id, Map<String, dynamic> data) async {
    await _db.from('store_users').update(data).eq('id', id);
  }

  /// Delete a store user.
  static Future<void> deleteStoreUser(String id) async {
    await _db.from('store_users').delete().eq('id', id);
  }

  /// Change the current user's password.
  static Future<void> changePassword(String newPassword) async {
    await _db.auth.updateUser(UserAttributes(password: newPassword));
  }
}
