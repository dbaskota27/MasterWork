import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

enum SubStatus { active, trial, expired, suspended, unknown }

class SubscriptionService {
  static SupabaseClient get _db => Supabase.instance.client;

  static SubStatus _status = SubStatus.unknown;
  static DateTime? _expiry;

  static SubStatus get status => _status;
  static DateTime? get expiry => _expiry;

  static bool get isActive =>
      _status == SubStatus.active || _status == SubStatus.trial;

  /// Check the store's subscription status.
  static Future<SubStatus> check() async {
    final storeId = AuthService.storeId;
    if (storeId == null) {
      _status = SubStatus.unknown;
      return _status;
    }

    final row = await _db
        .from('stores')
        .select('subscription_status, subscription_expiry')
        .eq('id', storeId)
        .maybeSingle();

    if (row == null) {
      _status = SubStatus.unknown;
      return _status;
    }

    final statusStr = row['subscription_status'] as String? ?? 'expired';
    final expiryStr = row['subscription_expiry'] as String?;

    _expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;

    // If status is trial or active, but expiry has passed → treat as expired
    if ((statusStr == 'trial' || statusStr == 'active') &&
        _expiry != null &&
        _expiry!.isBefore(DateTime.now())) {
      _status = SubStatus.expired;
      // Optionally update in DB
      await _db
          .from('stores')
          .update({'subscription_status': 'expired'}).eq('id', storeId);
      return _status;
    }

    switch (statusStr) {
      case 'active':
        _status = SubStatus.active;
      case 'trial':
        _status = SubStatus.trial;
      case 'suspended':
        _status = SubStatus.suspended;
      case 'expired':
        _status = SubStatus.expired;
      default:
        _status = SubStatus.unknown;
    }

    return _status;
  }

  /// Days remaining in the subscription / trial.
  static int get daysRemaining {
    if (_expiry == null) return 0;
    final diff = _expiry!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Friendly label for the status.
  static String get statusLabel {
    switch (_status) {
      case SubStatus.active:
        return 'Active';
      case SubStatus.trial:
        return 'Free Trial ($daysRemaining days left)';
      case SubStatus.expired:
        return 'Expired';
      case SubStatus.suspended:
        return 'Suspended';
      case SubStatus.unknown:
        return 'Unknown';
    }
  }
}
