import 'package:supabase_flutter/supabase_flutter.dart';

class WorkerService {
  static SupabaseClient get _db => Supabase.instance.client;

  // Active worker state
  static int? _workerId;
  static String? _workerName;
  static String? _workerRole;

  static int? get workerId => _workerId;
  static String? get workerName => _workerName;
  static String? get workerRole => _workerRole;
  static bool get isManager => _workerRole == 'manager';
  static bool get isLoggedIn => _workerId != null;

  /// Authenticate a worker by username + password.
  static Future<bool> login(String username, String password) async {
    final rows = await _db.rpc('authenticate_worker', params: {
      'p_username': username.trim(),
      'p_password': password,
    });
    final list = rows as List;
    if (list.isEmpty) return false;

    final row = list.first as Map<String, dynamic>;
    _workerId = (row['id'] as num).toInt();
    _workerName = row['display_name'] as String;
    _workerRole = row['role'] as String;
    return true;
  }

  /// Sign out the current worker (back to worker login).
  static void logout() {
    _workerId = null;
    _workerName = null;
    _workerRole = null;
  }

  // ── Worker CRUD (manager only) ────────────────────────────────────────────

  static Future<void> createWorker({
    required String username,
    required String password,
    required String displayName,
    required String role,
  }) async {
    await _db.rpc('create_worker_account', params: {
      'p_username': username.trim(),
      'p_password': password,
      'p_display_name': displayName.trim(),
      'p_role': role,
    });
  }

  static Future<List<Map<String, dynamic>>> listWorkers() async {
    final rows = await _db.rpc('list_workers');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> updateWorker(int id, {required String displayName, required String role}) async {
    await _db.rpc('update_worker_account', params: {
      'p_id': id,
      'p_display_name': displayName.trim(),
      'p_role': role,
    });
  }

  static Future<void> changePassword(int id, String newPassword) async {
    await _db.rpc('change_worker_password', params: {
      'p_id': id,
      'p_new_password': newPassword,
    });
  }

  static Future<void> deleteWorker(int id) async {
    await _db.rpc('delete_worker_account', params: {'p_id': id});
  }
}
