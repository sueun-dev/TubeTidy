import '../app_config.dart';

class BackendApi {
  static String? _idToken;

  static String get baseUrl {
    final configured = AppConfig.transcriptApiUrl.trim();
    return configured.isNotEmpty ? configured : 'http://127.0.0.1:5055';
  }

  static Uri uri(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final raw = Uri.parse('$normalizedBase$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return raw;
    }
    return raw.replace(queryParameters: queryParameters);
  }

  static void setIdToken(String? token) {
    final normalized = token?.trim();
    _idToken = (normalized == null || normalized.isEmpty) ? null : normalized;
  }

  static Map<String, String> headers({bool json = true}) {
    final result = <String, String>{};
    if (json) {
      result['Content-Type'] = 'application/json';
    }
    if (_idToken != null) {
      result['Authorization'] = 'Bearer $_idToken';
    }
    return result;
  }
}
