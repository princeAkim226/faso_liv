/// Configuration Supabase pour FasoLiv.
///
/// Clé publishable (anon) : destinée au client Flutter — ne jamais y mettre
/// la clé `service_role`.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jlwjzlrdgkcmpnhzhmju.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_e9X5FayIYlzbUHAUP61oKA_zV9oO-nq',
  );

  static bool get estConfigure =>
      !url.contains('VOTRE_PROJET') &&
      !publishableKey.contains('VOTRE_CLE');
}
