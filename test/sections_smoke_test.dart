import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:youtube_summary/models/archive.dart';
import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/plan.dart';
import 'package:youtube_summary/models/transcript.dart';
import 'package:youtube_summary/models/user.dart';
import 'package:youtube_summary/models/video.dart';
import 'package:youtube_summary/screens/calendar_screen.dart';
import 'package:youtube_summary/screens/channel_selection_screen.dart';
import 'package:youtube_summary/screens/connect_youtube_screen.dart';
import 'package:youtube_summary/screens/home_screen.dart';
import 'package:youtube_summary/screens/main_tab_scaffold.dart';
import 'package:youtube_summary/screens/onboarding_screen.dart';
import 'package:youtube_summary/screens/plan_screen.dart';
import 'package:youtube_summary/screens/settings_screen.dart';
import 'package:youtube_summary/state/app_controller.dart';
import 'package:youtube_summary/widgets/glass_surface.dart';

AppStateData _mockState({bool loading = false}) {
  final video = Video(
    id: 'video-1',
    youtubeId: 'yt-video-1',
    channelId: 'channel-1',
    title: '테스트 영상',
    publishedAt: DateTime(2026, 2, 1),
    thumbnailUrl: 'https://example.com/video.jpg',
  );
  final channel = Channel(
    id: 'channel-1',
    youtubeChannelId: 'channel-1',
    title: '테스트 채널',
    thumbnailUrl: 'https://example.com/channel.jpg',
  );
  return AppStateData(
    user: User(
      id: 'user-1',
      email: 'tester@example.com',
      plan: const Plan(tier: PlanTier.free),
      createdAt: DateTime(2026, 2, 1),
    ),
    youtubeConnected: true,
    selectionCompleted: true,
    isLoading: loading,
    channels: [channel],
    selectedChannelIds: const {'channel-1'},
    videos: [video],
    transcripts: const {
      'video-1': TranscriptResult(
        text: '원문',
        summary: '요약 1\n요약 2\n요약 3',
        source: 'captions',
        partial: false,
      ),
    },
    archives: [
      ArchiveEntry(
        videoId: 'video-1',
        archivedAt: DateTime(2026, 2, 2),
      ),
    ],
  );
}

AppStateData _emptyLoadingState() {
  return AppStateData(
    user: User(
      id: 'user-1',
      email: 'tester@example.com',
      plan: const Plan(tier: PlanTier.free),
      createdAt: DateTime(2026, 2, 1),
    ),
    youtubeConnected: true,
    selectionCompleted: true,
    isLoading: true,
    channels: const <Channel>[],
    selectedChannelIds: const <String>{},
    videos: const <Video>[],
    transcripts: const <String, TranscriptResult>{},
    archives: const <ArchiveEntry>[],
  );
}

Future<void> _pumpWithState(
  WidgetTester tester, {
  required Widget child,
  required AppStateData state,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(
            ref,
            initialState: state,
            restoreSession: false,
          ),
        ),
      ],
      child: CupertinoApp(home: child),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  testWidgets('Home screen smoke + liquid surface', (tester) async {
    await _pumpWithState(
      tester,
      child: const HomeScreen(),
      state: _mockState(),
    );
    expect(find.byType(GlassSurface), findsWidgets);
    expect(find.text('테스트 영상'), findsOneWidget);
  });

  testWidgets('Home empty/loading state does not throw', (tester) async {
    await _pumpWithState(
      tester,
      child: const HomeScreen(),
      state: _emptyLoadingState(),
      settle: false,
    );
    expect(find.byType(CupertinoActivityIndicator), findsWidgets);
    expect(find.byType(GlassSurface), findsWidgets);
  });

  testWidgets('Calendar screen smoke + liquid surface', (tester) async {
    await _pumpWithState(
      tester,
      child: const CalendarScreen(),
      state: _mockState(),
    );
    expect(find.byType(GlassSurface), findsWidgets);
    expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
  });

  testWidgets('Channel selection screen smoke + liquid surface',
      (tester) async {
    await _pumpWithState(
      tester,
      child: const ChannelSelectionScreen(),
      state: _mockState(),
    );
    expect(find.byType(GlassSurface), findsWidgets);
    expect(find.byType(CupertinoSearchTextField), findsOneWidget);
  });

  testWidgets('Plan screen smoke + liquid surface', (tester) async {
    await _pumpWithState(
      tester,
      child: const PlanScreen(),
      state: _mockState(),
    );
    expect(find.byType(GlassSurface), findsWidgets);
  });

  testWidgets('Settings screen smoke + liquid surface', (tester) async {
    await _pumpWithState(
      tester,
      child: const SettingsScreen(),
      state: _mockState(),
    );
    expect(find.byType(GlassSurface), findsWidgets);
  });

  testWidgets('Connect YouTube screen smoke + liquid surface', (tester) async {
    await _pumpWithState(
      tester,
      child: const ConnectYouTubeScreen(),
      state: _mockState(),
    );
    expect(find.byType(GlassSurface), findsWidgets);
  });

  testWidgets('Onboarding screen smoke + liquid surface', (tester) async {
    await _pumpWithState(
      tester,
      child: const OnboardingScreen(),
      state: _mockState(),
    );
    expect(find.byType(GlassSurface), findsWidgets);
  });

  testWidgets('Main tab scaffold smoke', (tester) async {
    await _pumpWithState(
      tester,
      child: const MainTabScaffold(),
      state: _mockState(),
    );
    expect(find.byType(CupertinoTabScaffold), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.house_fill), findsOneWidget);
  });
}
