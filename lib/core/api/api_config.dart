class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://paperstock.app',
  );

  /// Public privacy policy page, hosted on the backend. Required for Google Play.
  static const String privacyPolicyUrl = '$baseUrl/privacy';
}
