import '../models/archive.dart';
import '../models/channel.dart';
import '../models/transcript.dart';
import '../services/archive_service.dart';
import '../services/billing_service.dart';
import '../services/selection_change_cache.dart';
import '../services/selection_service.dart';
import '../services/transcript_cache.dart';
import '../services/transcript_service.dart';
import '../services/user_service.dart';
import '../services/user_state_service.dart';
import '../services/video_history_cache.dart';
import '../services/youtube_api.dart';

abstract class ArchiveServiceApi {
  Future<List<ArchiveEntry>?> fetchArchives(String userId);
  Future<ArchiveToggleResult?> toggleArchive(String userId, String videoId);
  Future<bool> clearArchives(String userId);
}

class DefaultArchiveService implements ArchiveServiceApi {
  @override
  Future<List<ArchiveEntry>?> fetchArchives(String userId) {
    return ArchiveService.fetchArchives(userId);
  }

  @override
  Future<ArchiveToggleResult?> toggleArchive(String userId, String videoId) {
    return ArchiveService.toggleArchive(userId, videoId);
  }

  @override
  Future<bool> clearArchives(String userId) {
    return ArchiveService.clearArchives(userId);
  }
}

abstract class SelectionServiceApi {
  Future<Set<String>?> fetchSelection(String userId);
  Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  });
}

class DefaultSelectionService implements SelectionServiceApi {
  @override
  Future<Set<String>?> fetchSelection(String userId) {
    return SelectionService.fetchSelection(userId);
  }

  @override
  Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  }) {
    return SelectionService.saveSelection(
      userId: userId,
      channels: channels,
      selectedIds: selectedIds,
    );
  }
}

abstract class UserServiceApi {
  Future<UserProfile?> upsertUser({
    required String userId,
    required String? email,
    required String planTier,
  });
  Future<UserProfile?> fetchUser(String userId);
  Future<bool> updatePlan(String userId, String planTier);
}

class DefaultUserService implements UserServiceApi {
  @override
  Future<UserProfile?> upsertUser({
    required String userId,
    required String? email,
    required String planTier,
  }) {
    return UserService.upsertUser(
      userId: userId,
      email: email,
      planTier: planTier,
    );
  }

  @override
  Future<UserProfile?> fetchUser(String userId) {
    return UserService.fetchUser(userId);
  }

  @override
  Future<bool> updatePlan(String userId, String planTier) {
    return UserService.updatePlan(userId, planTier);
  }
}

abstract class UserStateServiceApi {
  Future<UserStatePayload?> fetchState(String userId);
  Future<bool> saveState({
    required String userId,
    required int selectionChangeDay,
    required int selectionChangesToday,
    required List<String> openedVideoIds,
  });
}

class DefaultUserStateService implements UserStateServiceApi {
  @override
  Future<UserStatePayload?> fetchState(String userId) {
    return UserStateService.fetchState(userId);
  }

  @override
  Future<bool> saveState({
    required String userId,
    required int selectionChangeDay,
    required int selectionChangesToday,
    required List<String> openedVideoIds,
  }) {
    return UserStateService.saveState(
      userId: userId,
      selectionChangeDay: selectionChangeDay,
      selectionChangesToday: selectionChangesToday,
      openedVideoIds: openedVideoIds,
    );
  }
}

abstract class TranscriptServiceApi {
  Future<TranscriptResult?> fetchTranscript(String videoId);
}

class DefaultTranscriptService implements TranscriptServiceApi {
  @override
  Future<TranscriptResult?> fetchTranscript(String videoId) {
    return TranscriptService.fetchTranscript(videoId);
  }
}

typedef BillingServiceFactory = Future<BillingService?> Function();
typedef YouTubeApiFactory = YouTubeApi Function(
    Map<String, String> authHeaders);
typedef NowFn = DateTime Function();

class AppServices {
  const AppServices({
    required this.archiveService,
    required this.selectionService,
    required this.userService,
    required this.userStateService,
    required this.transcriptService,
    required this.youtubeApiFactory,
    required this.billingServiceFactory,
    required this.transcriptCache,
    required this.videoHistoryCache,
    required this.selectionChangeCache,
    required this.now,
  });

  factory AppServices.defaults() => AppServices(
        archiveService: DefaultArchiveService(),
        selectionService: DefaultSelectionService(),
        userService: DefaultUserService(),
        userStateService: DefaultUserStateService(),
        transcriptService: DefaultTranscriptService(),
        youtubeApiFactory: (headers) => YouTubeApi(authHeaders: headers),
        billingServiceFactory: () => BillingService.create(),
        transcriptCache: TranscriptCache.create(),
        videoHistoryCache: VideoHistoryCache.create(),
        selectionChangeCache: SelectionChangeCache.create(),
        now: DateTime.now,
      );

  final ArchiveServiceApi archiveService;
  final SelectionServiceApi selectionService;
  final UserServiceApi userService;
  final UserStateServiceApi userStateService;
  final TranscriptServiceApi transcriptService;
  final YouTubeApiFactory youtubeApiFactory;
  final BillingServiceFactory billingServiceFactory;
  final Future<TranscriptCache> transcriptCache;
  final Future<VideoHistoryCache> videoHistoryCache;
  final Future<SelectionChangeCache> selectionChangeCache;
  final NowFn now;
}
