class AppConfig {
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const transcriptApiUrl = String.fromEnvironment('TRANSCRIPT_API_URL');
  static const webAutoSignIn =
      String.fromEnvironment('WEB_AUTO_SIGNIN', defaultValue: 'false') == 'true';
}
