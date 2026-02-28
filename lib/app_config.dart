class AppConfig {
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const transcriptApiUrl = String.fromEnvironment('TRANSCRIPT_API_URL');
  static const webAutoSignIn =
      String.fromEnvironment('WEB_AUTO_SIGNIN', defaultValue: 'true') !=
          'false';
  static const e2eTestMode =
      String.fromEnvironment('E2E_TEST_MODE', defaultValue: 'false') == 'true';
  static const appVersion = String.fromEnvironment('APP_VERSION');
  static const buildNumber = String.fromEnvironment('BUILD_NUMBER');
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const termsUrl = String.fromEnvironment('TERMS_URL');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
  static const supportUrl = String.fromEnvironment('SUPPORT_URL');

  static const iosPlusProductId =
      String.fromEnvironment('IOS_IAP_PLUS_PRODUCT_ID');
  static const iosProProductId =
      String.fromEnvironment('IOS_IAP_PRO_PRODUCT_ID');
  static const iosUnlimitedProductId =
      String.fromEnvironment('IOS_IAP_UNLIMITED_PRODUCT_ID');
}
