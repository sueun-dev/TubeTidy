import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:youtube_summary/main.dart' as app;

const _e2eUserId = 'e2e_user_0001';
const _selectedChannelIds = <String>[
  'e2echannel01',
  'e2echannel02',
  'e2echannel03',
];
const _backendBaseUrl = String.fromEnvironment(
  'E2E_BACKEND_URL',
  defaultValue: 'http://127.0.0.1:5055',
);

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  required String step,
}) async {
  final endAt = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out while waiting for target widget. step=$step finder=$finder');
}

Future<int> _waitForAny(
  WidgetTester tester, {
  required List<Finder> finders,
  required String step,
}) async {
  final endAt = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < finders.length; i += 1) {
      if (finders[i].evaluate().isNotEmpty) {
        return i;
      }
    }
  }
  fail('Timed out while waiting for any target widget. step=$step');
}

Future<void> _expectBackendReady() async {
  final uri = Uri.parse('$_backendBaseUrl/health');
  final response = await http.get(uri).timeout(const Duration(seconds: 5));
  if (response.statusCode != 200) {
    fail(
        'Backend is not ready on $_backendBaseUrl. status=${response.statusCode}');
  }
}

Future<Set<String>> _fetchSelectionFromBackend() async {
  final response = await http
      .get(
        Uri.parse('$_backendBaseUrl/selection?user_id=$_e2eUserId'),
      )
      .timeout(const Duration(seconds: 8));
  expect(response.statusCode, 200);
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return (body['selected_ids'] as List<dynamic>? ?? [])
      .map((item) => item.toString())
      .toSet();
}

Future<void> _scrollToLogoutButton(WidgetTester tester) async {
  final scrollView = find.byType(CustomScrollView).first;
  final logoutButton = find.byKey(const ValueKey('settings-logout-button'));
  for (var i = 0; i < 5; i += 1) {
    if (logoutButton.evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(scrollView, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
  expect(logoutButton, findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'E2E login -> select 3 channels -> relogin keeps selection',
    (tester) async {
      await _expectBackendReady();

      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final e2eLoginButton = find.byKey(const ValueKey('e2e-login-button'));
      await _waitFor(tester, e2eLoginButton, step: 'initial-e2e-login-button');
      await tester.ensureVisible(e2eLoginButton);
      await tester.tap(e2eLoginButton);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final completeButton =
          find.byKey(const ValueKey('selection-complete-button'));
      await _waitFor(tester, completeButton, step: 'selection-complete-button');
      await tester.ensureVisible(completeButton);

      for (final channelId in _selectedChannelIds) {
        final switchFinder = find.byKey(ValueKey('channel-switch-$channelId'));
        await _waitFor(
          tester,
          switchFinder,
          step: 'channel-switch-$channelId-before-complete',
        );
        await tester.ensureVisible(switchFinder);
        final channelSwitch = tester.widget<CupertinoSwitch>(switchFinder);
        if (!channelSwitch.value) {
          await tester.tap(switchFinder);
          await tester.pumpAndSettle();
        }
      }

      await tester.tap(completeButton);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await _waitFor(
        tester,
        find.byKey(const ValueKey('tab-settings')),
        step: 'tab-settings',
      );
      await tester.tap(find.byKey(const ValueKey('tab-settings')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await _scrollToLogoutButton(tester);
      final logoutButton = find.byKey(const ValueKey('settings-logout-button'));
      await tester.tap(logoutButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await _waitFor(
        tester,
        e2eLoginButton,
        step: 'e2e-login-button-after-logout',
      );
      await tester.ensureVisible(e2eLoginButton);
      await tester.tap(e2eLoginButton);
      await tester.pumpAndSettle(const Duration(seconds: 4));

      final tabChannels = find.byKey(const ValueKey('tab-channels'));
      final selectionCompleteButton =
          find.byKey(const ValueKey('selection-complete-button'));
      final reloginLanding = await _waitForAny(
        tester,
        finders: [tabChannels, selectionCompleteButton],
        step: 'relogin-landing-screen',
      );
      if (reloginLanding == 0) {
        await tester.tap(tabChannels);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      for (final channelId in _selectedChannelIds) {
        final switchFinder = find.byKey(ValueKey('channel-switch-$channelId'));
        await _waitFor(
          tester,
          switchFinder,
          step: 'channel-switch-$channelId-after-relogin',
        );
        final channelSwitch = tester.widget<CupertinoSwitch>(switchFinder);
        expect(channelSwitch.value, isTrue);
      }

      final stored = await _fetchSelectionFromBackend();
      expect(stored, _selectedChannelIds.toSet());
    },
  );
}
