/// App-wide configuration.
/// Edit these values before building the APK.
class AppConfig {
  // ── Supabase ──────────────────────────────────────────────────────────────
  static const String supabaseUrl = 'https://your-project-id.supabase.co';
  static const String supabaseAnonKey = 'your-anon-key-here';

  // ── Store Info ────────────────────────────────────────────────────────────
  static const String storeName = 'My Mobile Store';
  static const String storeAddress = '123 Main Street, City, State';
  static const String storePhone = '+1 (555) 000-0000';
  static const String storeEmail = 'store@example.com';

  // ── Tax & Currency ────────────────────────────────────────────────────────
  static const double taxRate = 0.0; // 0.08 = 8%
  static const String currency = '\$';

  // ── Payment QR  (leave empty to hide on receipts) ─────────────────────────
  static const String paymentQrLink = ''; // e.g. 'https://venmo.com/yourhandle'

  // ── Login Credentials ─────────────────────────────────────────────────────
  static const Map<String, Map<String, String>> users = {
    'manager': {'password': 'admin123', 'role': 'manager'},
    'worker':  {'password': 'worker123', 'role': 'worker'},
  };
}
