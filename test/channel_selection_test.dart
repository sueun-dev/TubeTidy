import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/plan.dart';
import 'package:youtube_summary/models/user.dart';
import 'package:youtube_summary/screens/channel_selection_screen.dart';
import 'package:youtube_summary/state/app_controller.dart';

void main() {
  testWidgets('Channel selection lists channels', (WidgetTester tester) async {
    final channel = Channel(
      id: 'c1',
      youtubeChannelId: 'c1',
      title: '샘플 채널',
      thumbnailUrl: 'https://example.com/channel.jpg',
    );

    final state = AppStateData(
      user: User(
        id: 'u1',
        email: 'test@example.com',
        plan: const Plan(tier: PlanTier.free),
        createdAt: DateTime(2024, 1, 1),
      ),
      channels: [channel],
      selectedChannelIds: const {'c1'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            (ref) =>
                AppController(ref, initialState: state, restoreSession: false),
          ),
        ],
        child: const CupertinoApp(home: ChannelSelectionScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('샘플 채널'), findsOneWidget);
    expect(find.text('채널 선택 완료'), findsOneWidget);
  });

  testWidgets('Channel selection stays when finalize fails',
      (WidgetTester tester) async {
    final channel = Channel(
      id: 'c1',
      youtubeChannelId: 'c1',
      title: '실패 검증 채널',
      thumbnailUrl: 'https://example.com/channel.jpg',
    );

    final state = AppStateData(
      user: User(
        id: 'u1',
        email: 'test@example.com',
        plan: const Plan(tier: PlanTier.free),
        createdAt: DateTime(2024, 1, 1),
      ),
      channels: [channel],
      selectedChannelIds: const {'c1'},
      selectionCompleted: false,
    );

    final router = GoRouter(
      initialLocation: '/channels',
      routes: [
        GoRoute(
          path: '/channels',
          builder: (context, state) => const ChannelSelectionScreen(),
        ),
        GoRoute(
          path: '/app',
          builder: (context, state) => const CupertinoPageScaffold(
            child: Center(child: Text('APP_SCREEN')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            (ref) =>
                AppController(ref, initialState: state, restoreSession: false),
          ),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    final completeButton =
        find.byKey(const ValueKey('selection-complete-button'));
    expect(completeButton, findsOneWidget);
    await tester.tap(completeButton);
    await tester.pumpAndSettle();

    expect(find.byType(ChannelSelectionScreen), findsOneWidget);
    expect(find.text('APP_SCREEN'), findsNothing);
  });
}
