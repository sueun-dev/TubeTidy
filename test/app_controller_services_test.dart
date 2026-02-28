import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:youtube_summary/models/archive.dart';
import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/plan.dart';
import 'package:youtube_summary/models/transcript.dart';
import 'package:youtube_summary/models/user.dart';
import 'package:youtube_summary/models/video.dart';
import 'package:youtube_summary/services/app_services.dart';
import 'package:youtube_summary/services/archive_service.dart';
import 'package:youtube_summary/services/backend_api.dart';
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

class _FailingSelectionService implements SelectionServiceApi {
  @override
  Future<Set<String>?> fetchSelection(String userId) async => <String>{};

  @override
  Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  }) async {
    return false;
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

AppStateData _signedInState() {
  return AppStateData(
    user: User(
      id: 'user-1',
      email: 'tester@example.com',
      plan: const Plan(tier: PlanTier.free),
      createdAt: DateTime(2024, 1, 1),
    ),
    selectionCompleted: false,
  );
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

  test('refreshSubscriptions clears loading after subscription failure',
      () async {
    SharedPreferences.setMockInitialValues({});
    final services = AppServices(
      archiveService: _NoopArchiveService(),
      selectionService: _NoopSelectionService(),
      userService: _NoopUserService(),
      userStateService: _NoopUserStateService(),
      transcriptService: _FakeTranscriptService(
        const TranscriptResult(
          text: 'noop',
          summary: null,
          source: 'captions',
          partial: false,
        ),
      ),
      youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
      billingServiceFactory: () async => null,
      transcriptCache: TranscriptCache.create(),
      videoHistoryCache: VideoHistoryCache.create(),
      selectionChangeCache: SelectionChangeCache.create(),
      now: DateTime.now,
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(
            ref,
            services: services,
            initialState: _signedInState(),
            restoreSession: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    await controller.refreshSubscriptions();

    final state = container.read(appControllerProvider);
    expect(state.isLoading, isFalse);
    expect(state.toastMessage, isNotNull);
    expect(state.toastMessage!, contains('구독 채널 로드 실패'));
  });

  test('finalizeChannelSelection does not consume swap when save fails',
      () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 2, 7, 9, 30);
    final services = AppServices(
      archiveService: _NoopArchiveService(),
      selectionService: _FailingSelectionService(),
      userService: _NoopUserService(),
      userStateService: _NoopUserStateService(),
      transcriptService: _FakeTranscriptService(
        const TranscriptResult(
          text: 'noop',
          summary: null,
          source: 'captions',
          partial: false,
        ),
      ),
      youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
      billingServiceFactory: () async => null,
      transcriptCache: TranscriptCache.create(),
      videoHistoryCache: VideoHistoryCache.create(),
      selectionChangeCache: SelectionChangeCache.create(),
      now: () => now,
    );

    final initialState = AppStateData(
      user: User(
        id: 'user-1',
        email: 'tester@example.com',
        plan: const Plan(tier: PlanTier.free),
        createdAt: now,
      ),
      channels: const <Channel>[],
      selectedChannelIds: const <String>{},
      selectionCompleted: true,
      selectionChangeDay: 20260207,
      selectionChangesToday: 0,
      selectionChangePending: true,
      dailySwapAddedId: 'c-added',
      dailySwapRemovedId: 'c-removed',
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(
            ref,
            services: services,
            initialState: initialState,
            restoreSession: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    final completed = await controller.finalizeChannelSelection();

    final state = container.read(appControllerProvider);
    expect(completed, isFalse);
    expect(state.selectionChangeDay, 20260207);
    expect(state.selectionChangesToday, 0);
    expect(state.selectionChangePending, isTrue);
    expect(state.toastMessage, contains('채널 선택을 저장하지 못했습니다'));
  });

  test('finalizeChannelSelection consumes swap only after successful save',
      () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 2, 7, 9, 30);
    final services = AppServices(
      archiveService: _NoopArchiveService(),
      selectionService: _NoopSelectionService(),
      userService: _NoopUserService(),
      userStateService: _NoopUserStateService(),
      transcriptService: _FakeTranscriptService(
        const TranscriptResult(
          text: 'noop',
          summary: null,
          source: 'captions',
          partial: false,
        ),
      ),
      youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
      billingServiceFactory: () async => null,
      transcriptCache: TranscriptCache.create(),
      videoHistoryCache: VideoHistoryCache.create(),
      selectionChangeCache: SelectionChangeCache.create(),
      now: () => now,
    );

    final initialState = AppStateData(
      user: User(
        id: 'user-1',
        email: 'tester@example.com',
        plan: const Plan(tier: PlanTier.free),
        createdAt: now,
      ),
      channels: const <Channel>[],
      selectedChannelIds: const <String>{},
      selectionCompleted: true,
      selectionChangeDay: 20260207,
      selectionChangesToday: 0,
      selectionChangePending: true,
      dailySwapAddedId: 'c-added',
      dailySwapRemovedId: 'c-removed',
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(
            ref,
            services: services,
            initialState: initialState,
            restoreSession: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    final completed = await controller.finalizeChannelSelection();

    final state = container.read(appControllerProvider);
    expect(completed, isTrue);
    expect(state.selectionChangesToday, 1);
    expect(state.selectionChangePending, isFalse);
    expect(state.dailySwapAddedId, isNull);
    expect(state.dailySwapRemovedId, isNull);
  });

  test('finalizeChannelSelection is ignored while loading', () async {
    SharedPreferences.setMockInitialValues({});
    final services = AppServices(
      archiveService: _NoopArchiveService(),
      selectionService: _NoopSelectionService(),
      userService: _NoopUserService(),
      userStateService: _NoopUserStateService(),
      transcriptService: _FakeTranscriptService(
        const TranscriptResult(
          text: 'noop',
          summary: null,
          source: 'captions',
          partial: false,
        ),
      ),
      youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
      billingServiceFactory: () async => null,
      transcriptCache: TranscriptCache.create(),
      videoHistoryCache: VideoHistoryCache.create(),
      selectionChangeCache: SelectionChangeCache.create(),
      now: DateTime.now,
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(
            ref,
            services: services,
            initialState: _signedInState().copyWith(isLoading: true),
            restoreSession: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    final completed = await controller.finalizeChannelSelection();
    expect(completed, isFalse);
  });

  test('signOut clears backend authorization header', () async {
    SharedPreferences.setMockInitialValues({});
    BackendApi.setIdToken('test-token');
    addTearDown(() => BackendApi.setIdToken(null));

    final services = AppServices(
      archiveService: _NoopArchiveService(),
      selectionService: _NoopSelectionService(),
      userService: _NoopUserService(),
      userStateService: _NoopUserStateService(),
      transcriptService: _FakeTranscriptService(
        const TranscriptResult(
          text: 'noop',
          summary: null,
          source: 'captions',
          partial: false,
        ),
      ),
      youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
      billingServiceFactory: () async => null,
      transcriptCache: TranscriptCache.create(),
      videoHistoryCache: VideoHistoryCache.create(),
      selectionChangeCache: SelectionChangeCache.create(),
      now: DateTime.now,
    );

    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          (ref) => AppController(
            ref,
            services: services,
            initialState: _signedInState(),
            restoreSession: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(BackendApi.headers().containsKey('Authorization'), isTrue);

    final controller = container.read(appControllerProvider.notifier);
    controller.signOut();

    expect(BackendApi.headers().containsKey('Authorization'), isFalse);
    expect(container.read(appControllerProvider).isSignedIn, isFalse);
  });
}
