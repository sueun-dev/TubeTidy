import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:youtube_summary/app.dart';
import 'package:youtube_summary/state/app_controller.dart';

void main() {
  testWidgets('App shows onboarding when signed out',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            (ref) => AppController(ref, restoreSession: false),
          ),
        ],
        child: const YouTubeSummaryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google로 로그인'), findsOneWidget);
  });
}
