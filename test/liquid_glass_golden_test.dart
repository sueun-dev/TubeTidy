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
import 'package:youtube_summary/screens/channel_selection_screen.dart';
import 'package:youtube_summary/screens/connect_youtube_screen.dart';
import 'package:youtube_summary/screens/home_screen.dart';
import 'package:youtube_summary/screens/main_tab_scaffold.dart';
import 'package:youtube_summary/screens/onboarding_screen.dart';
import 'package:youtube_summary/screens/settings_screen.dart';
import 'package:youtube_summary/state/app_controller.dart';

AppStateData _goldenState() {
  final now = DateTime(2026, 2, 7, 10, 30);
  final channels = [
    Channel(
      id: 'e2echannel01',
      youtubeChannelId: 'e2echannel01',
      title: 'E2E 채널 1',
      thumbnailUrl: '',
    ),
    Channel(
      id: 'e2echannel02',
      youtubeChannelId: 'e2echannel02',
      title: 'E2E 채널 2',
      thumbnailUrl: '',
    ),
    Channel(
      id: 'e2echannel03',
      youtubeChannelId: 'e2echannel03',
      title: 'E2E 채널 3',
      thumbnailUrl: '',
    ),
  ];
  final videos = [
    Video(
      id: 'golden_video_1',
      youtubeId: 'golden_video_1',
      channelId: 'e2echannel01',
      title: 'AI 시장 핵심 요약',
      publishedAt: now,
      thumbnailUrl: '',
    ),
    Video(
      id: 'golden_video_2',
      youtubeId: 'golden_video_2',
      channelId: 'e2echannel02',
      title: '모바일 UX 트렌드',
      publishedAt: now.subtract(const Duration(hours: 4)),
      thumbnailUrl: '',
    ),
  ];
  return AppStateData(
    user: User(
      id: 'golden_user',
      email: 'golden@example.com',
      plan: const Plan(tier: PlanTier.free),
      createdAt: now,
    ),
    youtubeConnected: true,
    selectionCompleted: true,
    channels: channels,
    selectedChannelIds: const {'e2echannel01', 'e2echannel02', 'e2echannel03'},
    videos: videos,
    transcripts: const {
      'golden_video_1': TranscriptResult(
        text: '원문 요약',
        summary: '요약 1\n요약 2\n요약 3',
        source: 'captions',
        partial: false,
      ),
      'golden_video_2': TranscriptResult(
        text: '원문 요약 2',
        summary: '핵심 A\n핵심 B\n핵심 C',
        source: 'whisper',
        partial: false,
      ),
    },
    archives: [
      ArchiveEntry(
        videoId: 'golden_video_1',
        archivedAt: now.subtract(const Duration(days: 1)),
      ),
    ],
  );
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required Widget child,
  required AppStateData state,
}) async {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(1170, 2532);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

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
  await tester.pumpAndSettle(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('Onboarding liquid glass golden', (tester) async {
    await _pumpGolden(
      tester,
      child: const OnboardingScreen(),
      state: const AppStateData(),
    );
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/onboarding_liquid_glass.png'),
    );
  });

  testWidgets('Channel selection liquid glass golden', (tester) async {
    await _pumpGolden(
      tester,
      child: const ChannelSelectionScreen(),
      state: _goldenState().copyWith(selectionCompleted: false),
    );
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/channel_selection_liquid_glass.png'),
    );
  });

  testWidgets('Home liquid glass golden', (tester) async {
    await _pumpGolden(
      tester,
      child: const HomeScreen(),
      state: _goldenState(),
    );
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/home_liquid_glass.png'),
    );
  });

  testWidgets('Settings liquid glass golden', (tester) async {
    await _pumpGolden(
      tester,
      child: const SettingsScreen(),
      state: _goldenState(),
    );
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/settings_liquid_glass.png'),
    );
  });

  testWidgets('Connect liquid glass golden', (tester) async {
    await _pumpGolden(
      tester,
      child: const ConnectYouTubeScreen(),
      state: _goldenState(),
    );
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/connect_liquid_glass.png'),
    );
  });

  testWidgets('Main tab liquid glass golden', (tester) async {
    await _pumpGolden(
      tester,
      child: const MainTabScaffold(),
      state: _goldenState(),
    );
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/main_tab_liquid_glass.png'),
    );
  });
}
