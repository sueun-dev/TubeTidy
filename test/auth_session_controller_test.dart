import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_summary/services/backend_api.dart';
import 'package:youtube_summary/state/auth_session_controller.dart';

void main() {
  test('setAuthHeaders stores immutable headers', () {
    final controller = AuthSessionController();
    controller.setAuthHeaders({'Authorization': 'Bearer token'});

    final headers = controller.authHeaders;
    expect(headers, isNotNull);
    expect(headers!['Authorization'], 'Bearer token');
    expect(
      () => headers['X-Test'] = 'value',
      throwsUnsupportedError,
    );
  });

  test('clearSession clears backend token and local headers', () {
    final controller = AuthSessionController();
    controller.setAuthHeaders({'Authorization': 'Bearer token'});
    BackendApi.setIdToken('session-token');
    addTearDown(() => BackendApi.setIdToken(null));

    expect(controller.authHeaders, isNotNull);
    expect(BackendApi.headers().containsKey('Authorization'), isTrue);

    controller.clearSession();

    expect(controller.authHeaders, isNull);
    expect(controller.account, isNull);
    expect(BackendApi.headers().containsKey('Authorization'), isFalse);
  });
}
