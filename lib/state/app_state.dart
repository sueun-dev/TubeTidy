import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../models/archive.dart';
import '../models/channel.dart';
import '../models/plan.dart';
import '../models/transcript.dart';
import '../models/user.dart';
import '../models/video.dart';
import '../services/transcript_cache.dart';
import '../services/transcript_service.dart';
import '../services/youtube_api.dart';
import '../services/selection_change_cache.dart';

@immutable
class AppStateData {
  const AppStateData({
    this.user,
    this.youtubeConnected = false,
    this.selectionCompleted = false,
    this.isLoading = false,
    this.toastMessage,
    this.channels = const <Channel>[],
    this.selectedChannelIds = const <String>{},
    this.videos = const <Video>[],
    this.transcripts = const <String, TranscriptResult>{},
    this.transcriptLoading = const <String>{},
    this.archives = const <ArchiveEntry>[],
    this.selectionChangeDay = 0,
    this.selectionChangesToday = 0,
    this.selectionChangePending = false,
  });

  final User? user;
  final bool youtubeConnected;
  final bool selectionCompleted;
  final bool isLoading;
  final String? toastMessage;
  final List<Channel> channels;
  final Set<String> selectedChannelIds;
  final List<Video> videos;
  final Map<String, TranscriptResult> transcripts;
  final Set<String> transcriptLoading;
  final List<ArchiveEntry> archives;
  final int selectionChangeDay;
  final int selectionChangesToday;
  final bool selectionChangePending;

  factory AppStateData.initial() => const AppStateData();

  bool get isSignedIn => user != null;
  Plan get plan => user?.plan ?? const Plan(tier: PlanTier.free);
  int get channelLimit {
    final total = channels.length;
    if (total <= 0) return 0;
    final subscriptionLimit = total <= 3
        ? total
        : total <= 10
            ? 3
            : total <= 50
                ? 10
                : 10;
    final planLimit = plan.channelLimit;
    if (planLimit == null) {
      return subscriptionLimit;
    }
    return planLimit < subscriptionLimit ? planLimit : subscriptionLimit;
  }
  int get selectedCount => selectedChannelIds.length;
  bool get hasSelection => selectedChannelIds.isNotEmpty;
  int get _todayKey => _dayKey(DateTime.now());
  bool get isSelectionCooldownActive =>
      selectionChangeDay == _todayKey && selectionChangesToday >= 1;
  DateTime get nextSelectionChangeAt {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  static int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

  static const _toastSentinel = Object();

  AppStateData copyWith({
    User? user,
    bool? youtubeConnected,
    bool? selectionCompleted,
    bool? isLoading,
    Object? toastMessage = _toastSentinel,
    List<Channel>? channels,
    Set<String>? selectedChannelIds,
    List<Video>? videos,
    Map<String, TranscriptResult>? transcripts,
    Set<String>? transcriptLoading,
    List<ArchiveEntry>? archives,
    int? selectionChangeDay,
    int? selectionChangesToday,
    bool? selectionChangePending,
  }) {
    return AppStateData(
      user: user ?? this.user,
      youtubeConnected: youtubeConnected ?? this.youtubeConnected,
      selectionCompleted: selectionCompleted ?? this.selectionCompleted,
      isLoading: isLoading ?? this.isLoading,
      toastMessage: toastMessage == _toastSentinel ? this.toastMessage : toastMessage as String?,
      channels: channels ?? this.channels,
      selectedChannelIds: selectedChannelIds ?? this.selectedChannelIds,
      videos: videos ?? this.videos,
      transcripts: transcripts ?? this.transcripts,
      transcriptLoading: transcriptLoading ?? this.transcriptLoading,
      archives: archives ?? this.archives,
      selectionChangeDay: selectionChangeDay ?? this.selectionChangeDay,
      selectionChangesToday: selectionChangesToday ?? this.selectionChangesToday,
      selectionChangePending: selectionChangePending ?? this.selectionChangePending,
    );
  }
}

final appControllerProvider = StateNotifierProvider<AppController, AppStateData>((ref) {
  return AppController(ref);
});

class AppController extends StateNotifier<AppStateData> {
  AppController(
    Ref ref, {
    AppStateData? initialState,
    GoogleSignIn? googleSignIn,
    bool restoreSession = true,
  })  : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const [
                'email',
                'profile',
                'https://www.googleapis.com/auth/youtube.readonly',
              ],
              clientId: AppConfig.googleWebClientId.isNotEmpty
                  ? AppConfig.googleWebClientId
                  : null,
              serverClientId: AppConfig.googleServerClientId.isNotEmpty
                  ? AppConfig.googleServerClientId
                  : null,
            ),
        _transcriptCache = TranscriptCache.create(),
        _selectionChangeCache = SelectionChangeCache.create(),
        super(initialState ?? AppStateData.initial()) {
    if (restoreSession) {
      _restoreSession();
    }
  }
  final GoogleSignIn _googleSignIn;
  final Future<TranscriptCache> _transcriptCache;
  final Future<SelectionChangeCache> _selectionChangeCache;
  Map<String, String>? _authHeaders;
  GoogleSignInAccount? _googleAccount;
  List<Video> _transcriptQueue = <Video>[];
  bool _isProcessingQueue = false;
  bool _pendingQueueRestart = false;
  int _queueGeneration = 0;

  bool canSelectMore() {
    final limit = state.channelLimit;
    if (limit <= 0) return false;
    return state.selectedCount < limit;
  }

  bool isTranscriptLoading(String videoId) => state.transcriptLoading.contains(videoId);

  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      if (kIsWeb && AppConfig.googleWebClientId.isEmpty) {
        _setToast('웹 로그인을 위해 GOOGLE_WEB_CLIENT_ID 설정이 필요합니다.');
        _setLoading(false);
        return;
      }
      final account = await _googleSignIn.signIn();
      if (account == null) {
        _setLoading(false);
        return;
      }
      _googleAccount = account;
      _authHeaders = await account.authHeaders;
      state = state.copyWith(
        user: User(
          id: account.id,
          email: account.email,
          plan: const Plan(tier: PlanTier.free),
          createdAt: DateTime.now(),
        ),
      );
      try {
        await _connectAndSyncYouTube();
      } catch (error) {
        _setToast(kDebugMode ? 'YouTube 동기화 실패: $error' : 'YouTube 구독 채널을 불러오지 못했습니다.');
      }
    } catch (error) {
      _setToast(kDebugMode ? 'Google 로그인 실패: $error' : 'Google 로그인에 실패했습니다. 다시 시도해주세요.');
    }
    _setLoading(false);
  }

  Future<void> connectYouTubeAccount() async {
    _setLoading(true);
    try {
      if (_googleAccount == null) {
        await signInWithGoogle();
      } else {
        await _connectAndSyncYouTube();
      }
    } catch (error) {
      _setToast(kDebugMode ? '연동 실패: $error' : 'YouTube 연동에 실패했습니다.');
    }
    _setLoading(false);
  }

  Future<void> refreshSubscriptions() async {
    if (_authHeaders == null) return;
    _setLoading(true);
    try {
      await _loadChannels();
    } catch (error) {
      _setToast(kDebugMode ? '구독 채널 로드 실패: $error' : '구독 채널을 다시 불러오지 못했습니다.');
    }
    _setLoading(false);
  }

  void toggleChannel(String channelId) {
    if (state.selectionCompleted && !_canEditSelection()) {
      _setToast('오늘은 채널 변경을 이미 1회 사용했습니다. 내일 다시 변경할 수 있어요.');
      return;
    }
    final selected = Set<String>.from(state.selectedChannelIds);
    if (selected.contains(channelId)) {
      selected.remove(channelId);
      state = state.copyWith(
        selectedChannelIds: Set.unmodifiable(selected),
        selectionChangePending: state.selectionCompleted ? true : state.selectionChangePending,
      );
      return;
    }

    if (!canSelectMore()) {
      _setToast('최대 ${state.channelLimit}개 채널만 선택 가능합니다.');
      return;
    }

    selected.add(channelId);
    state = state.copyWith(
      selectedChannelIds: Set.unmodifiable(selected),
      selectionChangePending: state.selectionCompleted ? true : state.selectionChangePending,
    );
  }

  void clearToast() {
    state = state.copyWith(toastMessage: null);
  }

  Future<void> finalizeChannelSelection() async {
    _setLoading(true);
    try {
      await _loadSelectedVideos();
      final shouldConsumeChange =
          state.selectionCompleted && state.selectionChangePending;
      if (shouldConsumeChange) {
        _recordSelectionChange();
      }
      state = state.copyWith(
        selectionCompleted: true,
        selectionChangePending: false,
      );
    } catch (error) {
      _setToast(kDebugMode ? '영상 로드 실패: $error' : '선택한 채널의 영상을 불러오지 못했습니다.');
    }
    _setLoading(false);
  }

  void toggleArchive(String videoId) {
    final archives = List<ArchiveEntry>.from(state.archives);
    final existingIndex = archives.indexWhere((entry) => entry.videoId == videoId);
    if (existingIndex >= 0) {
      archives.removeAt(existingIndex);
    } else {
      archives.add(ArchiveEntry(videoId: videoId, archivedAt: DateTime.now()));
    }
    state = state.copyWith(archives: List.unmodifiable(archives));
  }

  bool isArchived(String videoId) {
    return state.archives.any((entry) => entry.videoId == videoId);
  }

  List<Video> archivedVideos() {
    final archivedIds = state.archives.map((e) => e.videoId).toSet();
    return state.videos.where((video) => archivedIds.contains(video.id)).toList();
  }

  Map<DateTime, List<Video>> archivesByDay() {
    final Map<DateTime, List<Video>> grouped = {};
    for (final entry in state.archives) {
      final day = DateTime(entry.archivedAt.year, entry.archivedAt.month, entry.archivedAt.day);
      final videoIndex = state.videos.indexWhere((v) => v.id == entry.videoId);
      if (videoIndex == -1) continue;
      final video = state.videos[videoIndex];
      grouped.putIfAbsent(day, () => []).add(video);
    }
    return grouped;
  }

  void upgradePlan(PlanTier tier) {
    final user = state.user;
    if (user == null) return;

    state = state.copyWith(
      user: User(
        id: user.id,
        email: user.email,
        plan: Plan(tier: tier),
        createdAt: user.createdAt,
      ),
    );

    final limit = state.channelLimit;
    if (limit > 0 && state.selectedChannelIds.length > limit) {
      final trimmed = state.selectedChannelIds.take(limit).toSet();
      state = state.copyWith(selectedChannelIds: Set.unmodifiable(trimmed));
      _loadSelectedVideos();
    }
  }

  void signOut() {
    _googleSignIn.signOut();
    _authHeaders = null;
    _googleAccount = null;
    state = AppStateData.initial();
  }

  Set<String> _normalizeSelection(List<Channel> channels) {
    if (channels.isEmpty || state.selectedChannelIds.isEmpty) {
      return state.selectedChannelIds;
    }
    final available = channels.map((channel) => channel.id).toSet();
    final filtered = state.selectedChannelIds.where(available.contains).toList();
    final limit = state.channelLimit;
    if (limit <= 0) return <String>{};
    return filtered.take(limit).toSet();
  }

  int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

  Future<void> _loadSelectionChangeState() async {
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _selectionChangeCache;
      final data = await cache.read(userId);
      if (data == null) {
        state = state.copyWith(selectionChangeDay: 0, selectionChangesToday: 0);
        return;
      }
      state = state.copyWith(
        selectionChangeDay: data.dayKey,
        selectionChangesToday: data.changesToday,
      );
    } catch (_) {
      // Ignore cache read failures.
    }
  }

  bool _canChangeSelectionToday() {
    final todayKey = _dayKey(DateTime.now());
    if (state.selectionChangeDay != todayKey) {
      _resetSelectionChange(todayKey);
      return true;
    }
    return state.selectionChangesToday < 1;
  }

  bool _canEditSelection() {
    if (!state.selectionCompleted) return true;
    if (state.selectionChangePending) return true;
    return _canChangeSelectionToday();
  }

  void _recordSelectionChange() {
    final todayKey = _dayKey(DateTime.now());
    final count =
        state.selectionChangeDay == todayKey ? state.selectionChangesToday + 1 : 1;
    state = state.copyWith(selectionChangeDay: todayKey, selectionChangesToday: count);
    _persistSelectionChange(todayKey, count);
  }

  void _resetSelectionChange(int todayKey) {
    state = state.copyWith(selectionChangeDay: todayKey, selectionChangesToday: 0);
    _persistSelectionChange(todayKey, 0);
  }

  Future<void> _persistSelectionChange(int dayKey, int count) async {
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _selectionChangeCache;
      await cache.write(userId, SelectionChangeState(dayKey: dayKey, changesToday: count));
    } catch (_) {
      // Ignore cache failures.
    }
  }

  Future<void> _restoreSession() async {
    if (state.isSignedIn) return;
    if (kIsWeb && !AppConfig.webAutoSignIn) {
      return;
    }
    _setLoading(true);
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) {
        _setLoading(false);
        return;
      }
      _googleAccount = account;
      _authHeaders = await account.authHeaders;
      state = state.copyWith(
        user: User(
          id: account.id,
          email: account.email,
          plan: const Plan(tier: PlanTier.free),
          createdAt: DateTime.now(),
        ),
      );
      await _connectAndSyncYouTube();
    } catch (_) {
      // Ignore silent sign-in failures.
    }
    _setLoading(false);
  }

  Future<void> _connectAndSyncYouTube() async {
    if (_authHeaders == null) {
      throw Exception('로그인이 필요합니다.');
    }
    state = state.copyWith(youtubeConnected: true, selectionCompleted: false);
    await _loadSelectionChangeState();
    await _loadChannels();
  }

  Future<void> _loadChannels() async {
    if (_authHeaders == null) return;
    final api = YouTubeApi(authHeaders: _authHeaders!);
    final channels = await api.fetchSubscriptions();
    final normalized = _normalizeSelection(channels);
    state = state.copyWith(
      channels: List.unmodifiable(channels),
      selectedChannelIds: Set.unmodifiable(normalized),
    );
  }

  Future<void> _loadSelectedVideos() async {
    if (_authHeaders == null) return;
    final api = YouTubeApi(authHeaders: _authHeaders!);
    final videos = await api.fetchLatestVideos(state.selectedChannelIds.toList());
    state = state.copyWith(
      videos: List.unmodifiable(videos),
      transcripts: const <String, TranscriptResult>{},
      transcriptLoading: const <String>{},
    );
    _queueGeneration += 1;
    _transcriptQueue = <Video>[];
    _pendingQueueRestart = false;
  }

  Future<void> _processTranscriptQueue(int generation) async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_transcriptQueue.isNotEmpty && generation == _queueGeneration) {
      final video = _transcriptQueue.removeAt(0);
      try {
        await _fetchTranscriptFor(video);
      } catch (error) {
        _handleTranscriptFailure(video, error);
      }
    }

    _isProcessingQueue = false;
    if (_pendingQueueRestart) {
      _pendingQueueRestart = false;
      _processTranscriptQueue(_queueGeneration);
    }
  }

  void requestSummaryFor(Video video) {
    final existing = state.transcripts[video.id];
    if (existing != null && existing.source != 'error' && (existing.summary ?? '').trim().isNotEmpty) {
      return;
    }
    if (state.transcriptLoading.contains(video.id)) {
      return;
    }
    if (_transcriptQueue.any((queued) => queued.id == video.id)) {
      return;
    }

    _transcriptQueue.add(video);
    if (_isProcessingQueue) {
      _pendingQueueRestart = true;
      return;
    }
    _processTranscriptQueue(_queueGeneration);
  }

  Future<void> _fetchTranscriptFor(Video video) async {
    if (state.transcripts.containsKey(video.id) || state.transcriptLoading.contains(video.id)) {
      return;
    }

    final cached = await _readCachedTranscript(video);
    if (cached != null) {
      state = state.copyWith(
        transcripts: Map<String, TranscriptResult>.from(state.transcripts)
          ..[video.id] = cached,
      );
      return;
    }

    final loading = Set<String>.from(state.transcriptLoading)..add(video.id);
    state = state.copyWith(transcriptLoading: Set.unmodifiable(loading));

    final transcript = await TranscriptService.fetchTranscript(video.youtubeId);
    final updatedLoading = Set<String>.from(state.transcriptLoading)..remove(video.id);

    if (transcript != null && transcript.text.trim().isNotEmpty) {
      final updatedTranscripts = Map<String, TranscriptResult>.from(state.transcripts)
        ..[video.id] = transcript;
      state = state.copyWith(
        transcripts: Map.unmodifiable(updatedTranscripts),
        transcriptLoading: Set.unmodifiable(updatedLoading),
      );
      await _writeCachedTranscript(video, transcript);
    } else {
      state = state.copyWith(transcriptLoading: Set.unmodifiable(updatedLoading));
    }
  }

  void _handleTranscriptFailure(Video video, Object error) {
    final updatedLoading = Set<String>.from(state.transcriptLoading)..remove(video.id);
    final message = kDebugMode
        ? '요약 실패: $error'
        : '요약 생성 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.';
    final updatedTranscripts = Map<String, TranscriptResult>.from(state.transcripts)
      ..[video.id] = TranscriptResult(
        text: message,
        source: 'error',
        partial: false,
      );
    state = state.copyWith(
      transcripts: Map.unmodifiable(updatedTranscripts),
      transcriptLoading: Set.unmodifiable(updatedLoading),
    );
  }

  Future<TranscriptResult?> _readCachedTranscript(Video video) async {
    try {
      final cache = await _transcriptCache;
      return cache.read(
        userId: state.user?.id ?? 'anonymous',
        videoId: video.youtubeId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedTranscript(Video video, TranscriptResult transcript) async {
    if (transcript.source == 'error') return;
    try {
      final cache = await _transcriptCache;
      await cache.write(
        userId: state.user?.id ?? 'anonymous',
        videoId: video.youtubeId,
        result: transcript,
      );
    } catch (_) {
      // Ignore cache failures (e.g., storage blocked on web).
    }
  }

  void _setLoading(bool value) {
    state = state.copyWith(isLoading: value);
  }

  void _setToast(String message) {
    state = state.copyWith(toastMessage: message);
  }
}
