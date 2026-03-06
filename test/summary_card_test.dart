import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:youtube_summary/localization/app_strings.dart';
import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/video.dart';
import 'package:youtube_summary/state/ui_providers.dart';
import 'package:youtube_summary/widgets/summary_card.dart';

void main() {
  group('SummaryCard thumbnail fallback', () {
    testWidgets(
      'does not create a network thumbnail for non-YouTube fixture ids',
      (WidgetTester tester) async {
        await tester.pumpWidget(_buildTestApp(videoId: 'e2evideo_channel_1'));

        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(CupertinoIcons.photo), findsOneWidget);
      },
    );

    testWidgets(
      'creates a YouTube thumbnail fallback for valid YouTube ids',
      (WidgetTester tester) async {
        await tester.pumpWidget(_buildTestApp(videoId: 'dQw4w9WgXcQ'));

        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image;

        expect(provider, isA<NetworkImage>());
        expect(
          (provider as NetworkImage).url,
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        );
      },
    );
  });
}

Widget _buildTestApp({required String videoId}) {
  final video = Video(
    id: videoId,
    youtubeId: videoId,
    channelId: 'channel-1',
    title: '테스트 영상',
    publishedAt: DateTime(2024, 1, 1, 9, 30),
    thumbnailUrl: '',
  );
  final channel = Channel(
    id: 'channel-1',
    youtubeChannelId: 'channel-1',
    title: '테스트 채널',
    thumbnailUrl: '',
  );

  return CupertinoApp(
    home: CupertinoPageScaffold(
      child: SummaryCard(
        video: video,
        channel: channel,
        transcript: null,
        isTranscriptLoading: false,
        isQueued: false,
        strings: const AppStrings(AppLanguage.ko),
        onWatchVideo: () {},
        isArchived: false,
        onToggleArchive: () {},
        onRequestSummary: () {},
      ),
    ),
  );
}
