import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/plan.dart';
import 'package:youtube_summary/models/user.dart';
import 'package:youtube_summary/state/app_controller.dart';

int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

List<Channel> _mockChannels(int count) {
  return List.generate(
    count,
    (index) => Channel(
      id: 'c${index + 1}',
      youtubeChannelId: 'c${index + 1}',
      title: '채널 ${index + 1}',
      thumbnailUrl: 'https://example.com/c${index + 1}.png',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('Selection swap enforces 1 out + 1 in per day', () {
    final channels = _mockChannels(5);
    final initialState = AppStateData(
      channels: channels,
      selectedChannelIds: const {'c1', 'c2', 'c3'},
      selectionCompleted: true,
      selectionChangeDay: _dayKey(DateTime.now()),
      selectionChangesToday: 0,
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(ref,
              initialState: initialState, restoreSession: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);

    controller.toggleChannel('c4');
    expect(container.read(appControllerProvider).selectedChannelIds,
        const {'c1', 'c2', 'c3'});

    controller.toggleChannel('c1');
    expect(container.read(appControllerProvider).selectedChannelIds,
        const {'c2', 'c3'});

    controller.toggleChannel('c4');
    expect(container.read(appControllerProvider).selectedChannelIds,
        const {'c2', 'c3', 'c4'});

    controller.toggleChannel('c5');
    expect(container.read(appControllerProvider).selectedChannelIds,
        const {'c2', 'c3', 'c4'});
  });

  test('Selection changes are blocked after daily swap is used', () {
    final channels = _mockChannels(4);
    final todayKey = _dayKey(DateTime.now());
    final initialState = AppStateData(
      channels: channels,
      selectedChannelIds: const {'c1', 'c2', 'c3'},
      selectionCompleted: true,
      selectionChangeDay: todayKey,
      selectionChangesToday: 1,
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(ref,
              initialState: initialState, restoreSession: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);

    controller.toggleChannel('c1');
    expect(container.read(appControllerProvider).selectedChannelIds,
        const {'c1', 'c2', 'c3'});
    expect(container.read(appControllerProvider).toastMessage, isNotNull);

    controller.toggleChannel('c4');
    expect(container.read(appControllerProvider).selectedChannelIds,
        const {'c1', 'c2', 'c3'});
  });

  test('Upgrade plan trims selection to new limit', () {
    final channels = _mockChannels(5);
    final initialState = AppStateData(
      channels: channels,
      selectedChannelIds: const {'c1', 'c2', 'c3', 'c4'},
      selectionCompleted: true,
      user: User(
        id: 'u1',
        email: 'u1@example.com',
        plan: const Plan(tier: PlanTier.unlimited),
        createdAt: DateTime.now(),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(ref,
              initialState: initialState, restoreSession: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    controller.upgradePlan(PlanTier.free);

    final updated = container.read(appControllerProvider).selectedChannelIds;
    expect(updated.length,
        lessThanOrEqualTo(container.read(appControllerProvider).channelLimit));
  });
}
