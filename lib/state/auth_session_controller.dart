import 'package:google_sign_in/google_sign_in.dart';

import '../services/backend_api.dart';
import 'auth_flow_guard.dart';

class AuthSessionController {
  final AuthFlowGuard _flowGuard = AuthFlowGuard();
  GoogleSignInAccount? _account;
  Map<String, String>? _authHeaders;

  int get revision => _flowGuard.revision;
  GoogleSignInAccount? get account => _account;
  Map<String, String>? get authHeaders => _authHeaders;
  bool get hasAuthHeaders => _authHeaders != null;

  int beginFlow() => _flowGuard.begin();

  int invalidateFlow() => _flowGuard.invalidate();

  bool isFlowCurrent(int revision) => _flowGuard.isCurrent(revision);

  bool matchesAccountId(String accountId) => _account?.id == accountId;

  void setAccount(GoogleSignInAccount account) {
    _account = account;
  }

  void setAuthHeaders(Map<String, String> headers) {
    _authHeaders = Map.unmodifiable(headers);
  }

  void clearSession() {
    _account = null;
    _authHeaders = null;
    BackendApi.setIdToken(null);
  }

  Future<void> refreshBackendToken({
    GoogleSignInAccount? account,
    String? expectedAccountId,
    int? expectedAuthRevision,
  }) async {
    final targetAccount = account ?? _account;
    if (targetAccount == null) {
      return;
    }
    if (!_passesGuards(
      expectedAccountId: expectedAccountId,
      expectedAuthRevision: expectedAuthRevision,
    )) {
      return;
    }
    try {
      final authentication = await targetAccount.authentication;
      if (!_passesGuards(
        expectedAccountId: expectedAccountId,
        expectedAuthRevision: expectedAuthRevision,
      )) {
        return;
      }
      BackendApi.setIdToken(authentication.idToken);
    } catch (_) {
      if (!_passesGuards(
        expectedAccountId: expectedAccountId,
        expectedAuthRevision: expectedAuthRevision,
      )) {
        return;
      }
      BackendApi.setIdToken(null);
    }
  }

  bool _passesGuards({
    String? expectedAccountId,
    int? expectedAuthRevision,
  }) {
    if (expectedAuthRevision != null &&
        !_flowGuard.isCurrent(expectedAuthRevision)) {
      return false;
    }
    if (expectedAccountId != null && !matchesAccountId(expectedAccountId)) {
      return false;
    }
    return true;
  }
}
