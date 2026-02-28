import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_summary/state/app_controller.dart';

const _e2eUserId = 'e2e_user_0001';
const _selectedChannelIds = <String>{
  'e2echannel01',
  'e2echannel02',
  'e2echannel03',
};
const _backendBaseUrl = String.fromEnvironment(
  'E2E_BACKEND_URL',
  defaultValue: 'http://127.0.0.1:5055',
);
const _e2eEnabled = bool.fromEnvironment('E2E_TEST_MODE');

Future<void> _expectBackendReady() async {
  final uri = Uri.parse('$_backendBaseUrl/health');
  final response = await http.get(uri).timeout(const Duration(seconds: 5));
  if (response.statusCode != 200) {
    fail(
        'Backend is not ready on $_backendBaseUrl. status=${response.statusCode}');
  }
}

Future<void> _resetSelectionOnBackend() async {
  final response = await http
      .post(
        Uri.parse('$_backendBaseUrl/selection'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _e2eUserId,
          'channels': const <Map<String, Object?>>[],
          'selected_ids': const <String>[],
        }),
      )
      .timeout(const Duration(seconds: 8));
  expect(response.statusCode, 200);
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

void main() {
  test('E2E flow: login -> select 3 channels -> relogin -> restore', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _expectBackendReady();
    await _resetSelectionOnBackend();

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(ref, restoreSession: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);

    await controller.signInForE2E();
    var state = container.read(appControllerProvider);
    expect(state.isSignedIn, isTrue);
    expect(state.channels.length, greaterThanOrEqualTo(3));
    expect(state.selectionCompleted, isFalse);

    for (final channelId in _selectedChannelIds) {
      controller.toggleChannel(channelId);
    }

    final finalized = await controller.finalizeChannelSelection();
    expect(finalized, isTrue);
    state = container.read(appControllerProvider);
    expect(state.selectionCompleted, isTrue);
    expect(state.selectedChannelIds, _selectedChannelIds);

    final savedSelection = await _fetchSelectionFromBackend();
    expect(savedSelection, _selectedChannelIds);

    controller.signOut();
    state = container.read(appControllerProvider);
    expect(state.isSignedIn, isFalse);

    await controller.signInForE2E();
    final restored = container.read(appControllerProvider);
    expect(restored.isSignedIn, isTrue);
    expect(restored.selectionCompleted, isTrue);
    expect(restored.selectedChannelIds, _selectedChannelIds);
  }, skip: !_e2eEnabled);
}
