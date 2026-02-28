import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_summary/state/auth_flow_guard.dart';

void main() {
  test('begin and invalidate advance revision', () {
    final guard = AuthFlowGuard();

    final first = guard.begin();
    final second = guard.begin();
    final invalidated = guard.invalidate();

    expect(first, 1);
    expect(second, 2);
    expect(invalidated, 3);
    expect(guard.revision, 3);
  });

  test('isCurrent only true for latest revision', () {
    final guard = AuthFlowGuard();

    final first = guard.begin();
    final second = guard.begin();

    expect(guard.isCurrent(first), isFalse);
    expect(guard.isCurrent(second), isTrue);
  });
}
