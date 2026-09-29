/// Configuration Supabase pour FasoLiv.
///
/// Backend dédié sur le VPS (Kong), distinct de Voltify et de l'ancien
/// projet cloud. Clé anon destinée au client Flutter — ne jamais y mettre
/// la clé `service_role`.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://supabasekong-n5wmktsokjyssxemtifxpzlo.109.199.124.31.sslip.io',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc5MDY4NDQwMCwiZXhwIjo0OTQ2MzU4MDAwLCJyb2xlIjoiYW5vbiJ9.Sakw3QitZljhuYZJRnn4D7pYH8leSbhEItiaC9Nj_dU',
  );

  static bool get estConfigure =>
      !url.contains('VOTRE_PROJET') &&
      !publishableKey.contains('VOTRE_CLE');
}
