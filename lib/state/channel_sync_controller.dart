import '../models/channel.dart';
import '../models/video.dart';
import '../services/app_services.dart';
import '../services/youtube_api.dart';

typedef EnsureYouTubeAccessFn = Future<void> Function({
  required bool allowInteractive,
  bool forceRefresh,
});

typedef CurrentAuthHeadersFn = Map<String, String> Function();

class ChannelSyncController {
  const ChannelSyncController({
    required SelectionServiceApi selectionService,
    required YouTubeApiFactory youtubeApiFactory,
  })  : _selectionService = selectionService,
        _youtubeApiFactory = youtubeApiFactory;

  final SelectionServiceApi _selectionService;
  final YouTubeApiFactory _youtubeApiFactory;

  Future<List<Channel>> fetchChannels({
    required bool allowInteractive,
    required EnsureYouTubeAccessFn ensureYouTubeAccess,
    required CurrentAuthHeadersFn currentAuthHeaders,
  }) async {
    await ensureYouTubeAccess(allowInteractive: allowInteractive);
    try {
      return await _youtubeApiFactory(currentAuthHeaders())
          .fetchSubscriptions();
    } on YouTubeApiException catch (error) {
      if (_shouldRetryAuth(error.statusCode) && allowInteractive) {
        await ensureYouTubeAccess(
          allowInteractive: allowInteractive,
          forceRefresh: true,
        );
        return _youtubeApiFactory(currentAuthHeaders()).fetchSubscriptions();
      }
      rethrow;
    }
  }

  Future<List<Video>> fetchLatestVideos({
    required List<String> selectedChannelIds,
    required bool allowInteractive,
    required EnsureYouTubeAccessFn ensureYouTubeAccess,
    required CurrentAuthHeadersFn currentAuthHeaders,
  }) async {
    await ensureYouTubeAccess(allowInteractive: allowInteractive);
    try {
      return await _youtubeApiFactory(currentAuthHeaders())
          .fetchLatestVideos(selectedChannelIds);
    } on YouTubeApiException catch (error) {
      if (_shouldRetryAuth(error.statusCode) && allowInteractive) {
        await ensureYouTubeAccess(
          allowInteractive: allowInteractive,
          forceRefresh: true,
        );
        return _youtubeApiFactory(currentAuthHeaders())
            .fetchLatestVideos(selectedChannelIds);
      }
      rethrow;
    }
  }

  Future<Set<String>?> fetchSelection(String userId) {
    return _selectionService.fetchSelection(userId);
  }

  Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  }) {
    return _selectionService.saveSelection(
      userId: userId,
      channels: channels,
      selectedIds: selectedIds,
    );
  }

  Set<String> normalizeSelection({
    required List<Channel> channels,
    required Set<String> selectedChannelIds,
    required int channelLimit,
  }) {
    if (channels.isEmpty || channelLimit <= 0) {
      return <String>{};
    }
    if (selectedChannelIds.isEmpty) {
      return <String>{};
    }
    final available = channels.map((channel) => channel.id).toSet();
    final filtered = <String>{};
    for (final selectedId in selectedChannelIds) {
      if (!available.contains(selectedId)) continue;
      filtered.add(selectedId);
      if (filtered.length >= channelLimit) {
        break;
      }
    }
    return filtered;
  }

  Set<String> filterServerSelection({
    required Set<String> selected,
    required List<Channel> channels,
    required int channelLimit,
  }) {
    final available = channels.map((channel) => channel.id).toSet();
    if (channelLimit <= 0) {
      return selected.where(available.contains).toSet();
    }
    final filtered = <String>{};
    for (final selectedId in selected) {
      if (!available.contains(selectedId)) continue;
      filtered.add(selectedId);
      if (filtered.length >= channelLimit) {
        break;
      }
    }
    return filtered;
  }

  bool _shouldRetryAuth(int statusCode) =>
      statusCode == 401 || statusCode == 403;
}
