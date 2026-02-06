import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/plan.dart';
import 'package:youtube_summary/models/transcript.dart';
import 'package:youtube_summary/models/user.dart';
import 'package:youtube_summary/models/video.dart';
import 'package:youtube_summary/screens/home_screen.dart';
import 'package:youtube_summary/state/app_controller.dart';

void main() {
  testWidgets('Home screen renders summary cards', (WidgetTester tester) async {
    final video = Video(
      id: 'v1',
      youtubeId: 'v1',
      channelId: 'c1',
      title: '테스트 영상',
      publishedAt: DateTime(2024, 1, 1),
      thumbnailUrl: 'https://example.com/thumb.jpg',
    );
    final channel = Channel(
      id: 'c1',
      youtubeChannelId: 'c1',
      title: '테스트 채널',
      thumbnailUrl: 'https://example.com/channel.jpg',
    );
    const transcript = TranscriptResult(
      text: '원문 텍스트',
      summary: '요약 1\n요약 2\n요약 3',
      source: 'whisper',
      partial: false,
    );

    final state = AppStateData(
      user: User(
        id: 'u1',
        email: 'test@example.com',
        plan: const Plan(tier: PlanTier.free),
        createdAt: DateTime(2024, 1, 1),
      ),
      selectionCompleted: true,
      channels: [channel],
      selectedChannelIds: const {'c1'},
      videos: [video],
      transcripts: const {'v1': transcript},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            (ref) =>
                AppController(ref, initialState: state, restoreSession: false),
          ),
        ],
        child: const CupertinoApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('테스트 영상'), findsOneWidget);
    expect(find.textContaining('요약 1'), findsOneWidget);
  });
}
