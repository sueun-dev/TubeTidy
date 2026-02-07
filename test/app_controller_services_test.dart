import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:youtube_summary/models/archive.dart';
import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/transcript.dart';
import 'package:youtube_summary/models/video.dart';
import 'package:youtube_summary/services/app_services.dart';
import 'package:youtube_summary/services/archive_service.dart';
import 'package:youtube_summary/services/selection_change_cache.dart';
import 'package:youtube_summary/services/transcript_cache.dart';
import 'package:youtube_summary/services/video_history_cache.dart';
import 'package:youtube_summary/services/user_service.dart';
import 'package:youtube_summary/services/user_state_service.dart';
import 'package:youtube_summary/services/youtube_api.dart';
import 'package:youtube_summary/state/app_controller.dart';

class _FakeTranscriptService implements TranscriptServiceApi {
  _FakeTranscriptService(this.result);

  final TranscriptResult result;
  int callCount = 0;

  @override
  Future<TranscriptResult?> fetchTranscript(String videoId) async {
    callCount += 1;
    return result;
  }
}

class _NoopArchiveService implements ArchiveServiceApi {
  @override
  Future<List<ArchiveEntry>?> fetchArchives(String userId) async =>
      <ArchiveEntry>[];

  @override
  Future<ArchiveToggleResult?> toggleArchive(
    String userId,
    String videoId,
  ) async {
    return null;
  }

  @override
  Future<bool> clearArchives(String userId) async => true;
}

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
    required String planTier,
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

void main() {
  test('AppController uses injected transcript service', () async {
    SharedPreferences.setMockInitialValues({});
    final fakeService = _FakeTranscriptService(
      const TranscriptResult(
        text: 'test transcript',
        summary: 'summary',
        source: 'captions',
        partial: false,
      ),
    );

    final services = AppServices(
      archiveService: _NoopArchiveService(),
      selectionService: _NoopSelectionService(),
      userService: _NoopUserService(),
      userStateService: _NoopUserStateService(),
      transcriptService: fakeService,
      youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
      billingServiceFactory: () async => null,
      transcriptCache: TranscriptCache.create(),
      videoHistoryCache: VideoHistoryCache.create(),
      selectionChangeCache: SelectionChangeCache.create(),
      now: () => DateTime(2024, 1, 1),
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) =>
              AppController(ref, services: services, restoreSession: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    final video = Video(
      id: 'video-1',
      youtubeId: 'yt-1',
      channelId: 'channel-1',
      title: 'Sample Video',
      publishedAt: DateTime(2024, 1, 1),
      thumbnailUrl: 'https://example.com/thumb.jpg',
    );
    controller.state = controller.state.copyWith(videos: [video]);

    controller.requestSummaryFor(video);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final state = container.read(appControllerProvider);
    expect(state.transcripts[video.id]?.text, 'test transcript');
    expect(fakeService.callCount, 1);
  });
}
