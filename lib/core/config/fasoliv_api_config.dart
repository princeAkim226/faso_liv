/// API d'interconnexion FasoLiv (courses créées par Sôôma).
class FasoLivApiConfig {
  FasoLivApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'FASOLIV_API_URL',
    defaultValue: 'https://fasoliv.raaga-bf.com',
  );
}
