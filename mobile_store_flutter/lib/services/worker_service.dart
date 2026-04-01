import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkerService {
  static SupabaseClient get _db => Supabase.instance.client;

  // All available permission keys
  static const List<String> allPermissionKeys = [
    'inventory_view',
    'inventory_edit',
    'customers_view',
    'customers_edit',
    'sales',
    'invoices_view',
    'invoices_refund',
    'expenses_view',
    'expenses_edit',
    'reports',
    'cash_register',
    'dashboard',
  ];

  // Human-readable labels for each permission
  static const Map<String, String> permissionLabels = {
    'inventory_view': 'View Inventory',
    'inventory_edit': 'Add/Edit/Delete Products',
    'customers_view': 'View Customers',
    'customers_edit': 'Add/Edit/Delete Customers',
    'sales': 'Make Sales (New Sale + Scanner)',
    'invoices_view': 'View Invoices',
    'invoices_refund': 'Process Refunds',
    'expenses_view': 'View Expenses',
    'expenses_edit': 'Add/Edit Expenses',
    'reports': 'View Reports',
    'cash_register': 'Access Cash Register',
    'dashboard': 'View Dashboard',
  };

  // Active worker state
  static int? _workerId;
  static String? _workerName;
  static String? _workerRole;
  static Map<String, bool> _permissions = {};

  static int? get workerId => _workerId;
  static String? get workerName => _workerName;
  static String? get workerRole => _workerRole;
  static bool get isManager => _workerRole == 'manager';
  static bool get isLoggedIn => _workerId != null;
  static Map<String, bool> get permissions => Map.unmodifiable(_permissions);

  /// Returns true if the current worker has the given permission.
  /// Managers always have ALL permissions regardless of the stored map.
  static bool hasPermission(String key) {
    if (isManager) return true;
    return _permissions[key] == true;
  }

  /// Parse a permissions value from the DB (could be Map or JSON string).
  static Map<String, bool> _parsePermissions(dynamic raw) {
    if (raw == null) return {};
    Map<String, dynamic> map;
    if (raw is String) {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } else if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    } else {
      return {};
    }
    final result = <String, bool>{};
    for (final key in allPermissionKeys) {
      result[key] = map[key] == true;
    }
    return result;
  }

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
    _permissions = _parsePermissions(row['permissions']);
    return true;
  }

  /// Sign out the current worker (back to worker login).
  static void logout() {
    _workerId = null;
    _workerName = null;
    _workerRole = null;
    _permissions = {};
  }

  // ── Worker CRUD (manager only) ────────────────────────────────────────────

  static Future<void> createWorker({
    required String username,
    required String password,
    required String displayName,
    required String role,
    Map<String, bool> permissions = const {},
  }) async {
    // Managers always get all permissions
    final perms = role == 'manager'
        ? {for (final k in allPermissionKeys) k: true}
        : permissions;
    await _db.rpc('create_worker_account', params: {
      'p_username': username.trim(),
      'p_password': password,
      'p_display_name': displayName.trim(),
      'p_role': role,
      'p_permissions': perms,
    });
  }

  static Future<List<Map<String, dynamic>>> listWorkers() async {
    final rows = await _db.rpc('list_workers');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> updateWorker(
    int id, {
    required String displayName,
    required String role,
    Map<String, bool> permissions = const {},
  }) async {
    // Managers always get all permissions
    final perms = role == 'manager'
        ? {for (final k in allPermissionKeys) k: true}
        : permissions;
    await _db.rpc('update_worker_account', params: {
      'p_id': id,
      'p_display_name': displayName.trim(),
      'p_role': role,
      'p_permissions': perms,
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
