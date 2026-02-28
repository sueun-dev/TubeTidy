import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/models/video.dart';
import 'package:youtube_summary/services/app_services.dart';
import 'package:youtube_summary/services/youtube_api.dart';
import 'package:youtube_summary/state/channel_sync_controller.dart';

class _FakeSelectionService implements SelectionServiceApi {
  Set<String>? selection;
  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<Set<String>?> fetchSelection(String userId) async {
    fetchCalls += 1;
    return selection;
  }

  @override
  Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  }) async {
    saveCalls += 1;
    selection = selectedIds;
    return true;
  }
}

class _FakeYouTubeApi extends YouTubeApi {
  _FakeYouTubeApi({
    required this.fetchSubscriptionsImpl,
    required this.fetchLatestVideosImpl,
  }) : super(authHeaders: const {});

  final Future<List<Channel>> Function() fetchSubscriptionsImpl;
  final Future<List<Video>> Function(List<String>) fetchLatestVideosImpl;

  @override
  Future<List<Channel>> fetchSubscriptions() => fetchSubscriptionsImpl();

  @override
  Future<List<Video>> fetchLatestVideos(List<String> channelIds) =>
      fetchLatestVideosImpl(channelIds);
}

void main() {
  test('normalizeSelection filters unavailable ids and applies limit', () {
    final selectionService = _FakeSelectionService();
    final controller = ChannelSyncController(
      selectionService: selectionService,
      youtubeApiFactory: (_) => _FakeYouTubeApi(
        fetchSubscriptionsImpl: () async => <Channel>[],
        fetchLatestVideosImpl: (_) async => <Video>[],
      ),
    );

    final result = controller.normalizeSelection(
      channels: [
        Channel(
          id: 'c1',
          youtubeChannelId: 'c1',
          title: 'Channel 1',
          thumbnailUrl: '',
        ),
        Channel(
          id: 'c2',
          youtubeChannelId: 'c2',
          title: 'Channel 2',
          thumbnailUrl: '',
        ),
      ],
      selectedChannelIds: const {'c1', 'missing', 'c2'},
      channelLimit: 1,
    );

    expect(result, {'c1'});
  });

  test('fetchChannels retries once for auth error when interactive', () async {
    final selectionService = _FakeSelectionService();
    var attempts = 0;
    final controller = ChannelSyncController(
      selectionService: selectionService,
      youtubeApiFactory: (_) => _FakeYouTubeApi(
        fetchSubscriptionsImpl: () async {
          attempts += 1;
          if (attempts == 1) {
            throw YouTubeApiException('unauthorized', 401);
          }
          return [
            Channel(
              id: 'c1',
              youtubeChannelId: 'c1',
              title: 'Channel 1',
              thumbnailUrl: '',
            ),
          ];
        },
        fetchLatestVideosImpl: (_) async => <Video>[],
      ),
    );

    final forceRefreshCalls = <bool>[];
    final channels = await controller.fetchChannels(
      allowInteractive: true,
      ensureYouTubeAccess: ({
        required bool allowInteractive,
        bool forceRefresh = false,
      }) async {
        forceRefreshCalls.add(forceRefresh);
      },
      currentAuthHeaders: () => const {'Authorization': 'Bearer test'},
    );

    expect(channels.length, 1);
    expect(attempts, 2);
    expect(forceRefreshCalls, [false, true]);
  });

  test('filterServerSelection keeps only available ids and applies limit', () {
    final selectionService = _FakeSelectionService();
    final controller = ChannelSyncController(
      selectionService: selectionService,
      youtubeApiFactory: (_) => _FakeYouTubeApi(
        fetchSubscriptionsImpl: () async => <Channel>[],
        fetchLatestVideosImpl: (_) async => <Video>[],
      ),
    );

    final filtered = controller.filterServerSelection(
      selected: const {'c2', 'c3', 'missing'},
      channels: [
        Channel(
          id: 'c1',
          youtubeChannelId: 'c1',
          title: 'Channel 1',
          thumbnailUrl: '',
        ),
        Channel(
          id: 'c2',
          youtubeChannelId: 'c2',
          title: 'Channel 2',
          thumbnailUrl: '',
        ),
        Channel(
          id: 'c3',
          youtubeChannelId: 'c3',
          title: 'Channel 3',
          thumbnailUrl: '',
        ),
      ],
      channelLimit: 1,
    );

    expect(filtered.length, 1);
    expect(filtered.first, anyOf('c2', 'c3'));
  });

  test(
      'filterServerSelection keeps all available ids when limit is non-positive',
      () {
    final selectionService = _FakeSelectionService();
    final controller = ChannelSyncController(
      selectionService: selectionService,
      youtubeApiFactory: (_) => _FakeYouTubeApi(
        fetchSubscriptionsImpl: () async => <Channel>[],
        fetchLatestVideosImpl: (_) async => <Video>[],
      ),
    );

    final filtered = controller.filterServerSelection(
      selected: const {'c2', 'missing', 'c3'},
      channels: [
        Channel(
          id: 'c1',
          youtubeChannelId: 'c1',
          title: 'Channel 1',
          thumbnailUrl: '',
        ),
        Channel(
          id: 'c2',
          youtubeChannelId: 'c2',
          title: 'Channel 2',
          thumbnailUrl: '',
        ),
        Channel(
          id: 'c3',
          youtubeChannelId: 'c3',
          title: 'Channel 3',
          thumbnailUrl: '',
        ),
      ],
      channelLimit: 0,
    );

    expect(filtered, {'c2', 'c3'});
  });

  test('fetchLatestVideos retries once for auth error when interactive',
      () async {
    final selectionService = _FakeSelectionService();
    var attempts = 0;
    final controller = ChannelSyncController(
      selectionService: selectionService,
      youtubeApiFactory: (_) => _FakeYouTubeApi(
        fetchSubscriptionsImpl: () async => <Channel>[],
        fetchLatestVideosImpl: (_) async {
          attempts += 1;
          if (attempts == 1) {
            throw YouTubeApiException('forbidden', 403);
          }
          return [
            Video(
              id: 'v1',
              youtubeId: 'v1',
              channelId: 'c1',
              title: 'Video 1',
              publishedAt: DateTime(2026, 1, 1),
              thumbnailUrl: '',
            ),
          ];
        },
      ),
    );

    final forceRefreshCalls = <bool>[];
    final videos = await controller.fetchLatestVideos(
      selectedChannelIds: const ['c1'],
      allowInteractive: true,
      ensureYouTubeAccess: ({
        required bool allowInteractive,
        bool forceRefresh = false,
      }) async {
        forceRefreshCalls.add(forceRefresh);
      },
      currentAuthHeaders: () => const {'Authorization': 'Bearer test'},
    );

    expect(videos.length, 1);
    expect(attempts, 2);
    expect(forceRefreshCalls, [false, true]);
  });

  test('selection service calls are delegated', () async {
    final selectionService = _FakeSelectionService()..selection = {'c1'};
    final controller = ChannelSyncController(
      selectionService: selectionService,
      youtubeApiFactory: (_) => _FakeYouTubeApi(
        fetchSubscriptionsImpl: () async => <Channel>[],
        fetchLatestVideosImpl: (_) async => <Video>[],
      ),
    );

    final fetched = await controller.fetchSelection('user-1');
    final saved = await controller.saveSelection(
      userId: 'user-1',
      channels: [
        Channel(
          id: 'c1',
          youtubeChannelId: 'c1',
          title: 'Channel 1',
          thumbnailUrl: '',
        ),
      ],
      selectedIds: const {'c1'},
    );

    expect(fetched, {'c1'});
    expect(saved, isTrue);
    expect(selectionService.fetchCalls, 1);
    expect(selectionService.saveCalls, 1);
  });
}
