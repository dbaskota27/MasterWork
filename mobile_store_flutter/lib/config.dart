/// App-wide configuration.
/// Fill in your Supabase project credentials before building.
class AppConfig {
  // ── Supabase ──────────────────────────────────────────────────────────────
  static const String supabaseUrl     = 'https://rejdtwdnbsuvypmjfpjr.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJlamR0d2RuYnN1dnlwbWpmcGpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MTc2NDIsImV4cCI6MjA5MDI5MzY0Mn0.jhOakgwg1rm_W_YIq3BI-P4noDx923uXsp0WHQl-kkc';

  // ── Defaults (used during store setup, editable later) ────────────────────
  static const String currency = '\$';

  // ── Subscription ──────────────────────────────────────────────────────────
  static const int trialDays = 7;
  static const String supportPhone = '+1 (555) 000-0000';
  static const String supportEmail = 'support@example.com';
}
