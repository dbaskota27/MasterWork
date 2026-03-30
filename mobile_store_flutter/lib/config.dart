/// App-wide configuration.
/// Fill in your Supabase project credentials before building.
class AppConfig {
  // ── Supabase ──────────────────────────────────────────────────────────────
  static const String supabaseUrl     = 'https://your-project-id.supabase.co';
  static const String supabaseAnonKey = 'your-anon-key-here';

  // ── Defaults (used during store setup, editable later) ────────────────────
  static const String currency = '\$';

  // ── Subscription ──────────────────────────────────────────────────────────
  static const int trialDays = 7;
  static const String supportPhone = '+1 (555) 000-0000';
  static const String supportEmail = 'support@example.com';
}
