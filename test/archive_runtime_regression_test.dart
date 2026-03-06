import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:youtube_summary/models/archive.dart';
import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/plan.dart';
import 'package:youtube_summary/models/transcript.dart';
import 'package:youtube_summary/models/user.dart';
import 'package:youtube_summary/services/app_services.dart';
import 'package:youtube_summary/services/archive_service.dart';
import 'package:youtube_summary/services/selection_change_cache.dart';
import 'package:youtube_summary/services/transcript_cache.dart';
import 'package:youtube_summary/services/video_history_cache.dart';
import 'package:youtube_summary/services/user_service.dart';
import 'package:youtube_summary/services/user_state_service.dart';
import 'package:youtube_summary/services/youtube_api.dart';
import 'package:youtube_summary/screens/calendar_screen.dart';
import 'package:youtube_summary/state/app_controller.dart';
import 'package:youtube_summary/state/ui_providers.dart';

class _NoopSelectionService implements SelectionServiceApi {
  @override
  Future<Set<String>?> fetchSelection(String userId) async => <String>{};

  @override
  Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  }) async {
    return true;
  }
}

class _NoopUserService implements UserServiceApi {
  @override
  Future<UserProfile?> upsertUser({
    required String userId,
    required String? email,
  }) async {
    return null;
  }

  @override
  Future<UserProfile?> fetchUser(String userId) async => null;

  @override
  Future<bool> updatePlan(String userId, String planTier) async => true;
}

class _NoopUserStateService implements UserStateServiceApi {
  @override
  Future<UserStatePayload?> fetchState(String userId) async => null;

  @override
  Future<bool> saveState({
    required String userId,
    required int selectionChangeDay,
    required int selectionChangesToday,
    required List<String> openedVideoIds,
  }) async {
    return true;
  }
}

class _NoopTranscriptService implements TranscriptServiceApi {
  @override
  Future<TranscriptResult?> fetchTranscript(String videoId) async => null;
}

class _FailingArchiveService implements ArchiveServiceApi {
  @override
  Future<List<ArchiveEntry>?> fetchArchives(String userId) async =>
      <ArchiveEntry>[];

  @override
  Future<ArchiveToggleResult?> toggleArchive({
    required String userId,
    required ArchiveMutationRequest request,
  }) async {
    return null;
  }

  @override
  Future<bool> clearArchives(String userId) async => false;
}

AppServices _services(ArchiveServiceApi archiveService) {
  return AppServices(
    archiveService: archiveService,
    selectionService: _NoopSelectionService(),
    userService: _NoopUserService(),
    userStateService: _NoopUserStateService(),
    transcriptService: _NoopTranscriptService(),
    youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
    billingServiceFactory: () async => null,
    transcriptCache: TranscriptCache.create(),
    videoHistoryCache: VideoHistoryCache.create(),
    selectionChangeCache: SelectionChangeCache.create(),
    now: DateTime.now,
  );
}

AppStateData _baseState({required List<ArchiveEntry> archives}) {
  return AppStateData(
    user: User(
      id: 'user-1',
      email: 'tester@example.com',
      plan: const Plan(tier: PlanTier.free),
      createdAt: DateTime(2026, 2, 1),
    ),
    youtubeConnected: true,
    selectionCompleted: true,
    channels: const <Channel>[],
    selectedChannelIds: const <String>{},
    archives: archives,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  testWidgets('Calendar renders archived items from archive metadata only',
      (tester) async {
    final archivedAt = DateTime(2026, 3, 6, 9, 0);
    final state = _baseState(
      archives: [
        ArchiveEntry(
          videoId: 'video-1',
          archivedAt: archivedAt,
          title: '보관된 영상',
          thumbnailUrl: 'https://example.com/video.jpg',
          channelId: 'channel-9',
          channelTitle: '기록 채널',
          channelThumbnailUrl: 'https://example.com/channel.jpg',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            (ref) => AppController(
              ref,
              services: _services(_FailingArchiveService()),
              initialState: state,
              restoreSession: false,
            ),
          ),
          calendarFocusedMonthProvider.overrideWith((ref) => archivedAt),
          calendarSelectedDayProvider.overrideWith((ref) => archivedAt),
        ],
        child: const CupertinoApp(home: CalendarScreen()),
      ),
    );

    await tester.pumpAndSettle();

    final archivedTitleFinder = find.text('보관된 영상', skipOffstage: false);
    await tester.scrollUntilVisible(
      archivedTitleFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(archivedTitleFinder, findsOneWidget);
    expect(find.text('기록 채널', skipOffstage: false), findsOneWidget);
  });
}
