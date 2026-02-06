import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../app_config.dart';
import '../models/archive.dart';
import '../models/channel.dart';
import '../models/plan.dart';
import '../models/transcript.dart';
import '../models/user.dart';
import '../models/video.dart';
import '../services/app_services.dart';
import '../services/backend_api.dart';
import '../services/billing_service.dart';
import '../services/selection_change_cache.dart';
import '../services/youtube_api.dart';

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
    this.transcriptQueued = const <String>{},
    this.openedVideoIds = const <String>{},
    this.archives = const <ArchiveEntry>[],
    this.selectionChangeDay = 0,
    this.selectionChangesToday = 0,
    this.selectionChangePending = false,
    this.dailySwapAddedId,
    this.dailySwapRemovedId,
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
  final Set<String> transcriptQueued;
  final Set<String> openedVideoIds;
  final List<ArchiveEntry> archives;
  final int selectionChangeDay;
  final int selectionChangesToday;
  final bool selectionChangePending;
  final String? dailySwapAddedId;
  final String? dailySwapRemovedId;

  factory AppStateData.initial() => const AppStateData();

  bool get isSignedIn => user != null;
  Plan get plan => user?.plan ?? const Plan(tier: PlanTier.free);
  int get channelLimit {
    final planLimit = plan.channelLimit;
    final total = channels.length;
    if (total <= 0) return 0;
    if (planLimit == null) {
      return total;
    }
    return planLimit < total ? planLimit : total;
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

  static int _dayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static const _sentinel = Object();

  AppStateData copyWith({
    User? user,
    bool? youtubeConnected,
    bool? selectionCompleted,
    bool? isLoading,
    Object? toastMessage = _sentinel,
    List<Channel>? channels,
    Set<String>? selectedChannelIds,
    List<Video>? videos,
    Map<String, TranscriptResult>? transcripts,
    Set<String>? transcriptLoading,
    Set<String>? transcriptQueued,
    Set<String>? openedVideoIds,
    List<ArchiveEntry>? archives,
    int? selectionChangeDay,
    int? selectionChangesToday,
    bool? selectionChangePending,
    Object? dailySwapAddedId = _sentinel,
    Object? dailySwapRemovedId = _sentinel,
  }) {
    return AppStateData(
      user: user ?? this.user,
      youtubeConnected: youtubeConnected ?? this.youtubeConnected,
      selectionCompleted: selectionCompleted ?? this.selectionCompleted,
      isLoading: isLoading ?? this.isLoading,
      toastMessage: toastMessage == _sentinel
          ? this.toastMessage
          : toastMessage as String?,
      channels: channels ?? this.channels,
      selectedChannelIds: selectedChannelIds ?? this.selectedChannelIds,
      videos: videos ?? this.videos,
      transcripts: transcripts ?? this.transcripts,
      transcriptLoading: transcriptLoading ?? this.transcriptLoading,
      transcriptQueued: transcriptQueued ?? this.transcriptQueued,
      openedVideoIds: openedVideoIds ?? this.openedVideoIds,
      archives: archives ?? this.archives,
      selectionChangeDay: selectionChangeDay ?? this.selectionChangeDay,
      selectionChangesToday:
          selectionChangesToday ?? this.selectionChangesToday,
      selectionChangePending:
          selectionChangePending ?? this.selectionChangePending,
      dailySwapAddedId: dailySwapAddedId == _sentinel
          ? this.dailySwapAddedId
          : dailySwapAddedId as String?,
      dailySwapRemovedId: dailySwapRemovedId == _sentinel
          ? this.dailySwapRemovedId
          : dailySwapRemovedId as String?,
    );
  }
}

final appControllerProvider =
    StateNotifierProvider<AppController, AppStateData>((ref) {
  return AppController(ref);
});

class AppController extends StateNotifier<AppStateData> {
  factory AppController(
    Ref ref, {
    AppStateData? initialState,
    GoogleSignIn? googleSignIn,
    AppServices? services,
    bool restoreSession = true,
  }) {
    final resolvedServices = services ?? AppServices.defaults();
    return AppController._internal(
      ref,
      resolvedServices,
      initialState: initialState,
      googleSignIn: googleSignIn,
      restoreSession: restoreSession,
    );
  }

  AppController._internal(
    Ref ref,
    this._services, {
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
        super(initialState ?? AppStateData.initial()) {
    _accountSubscription =
        _googleSignIn.onCurrentUserChanged.listen(_handleAccountChange);
    if (restoreSession) {
      _restoreSession();
    }
  }

  final AppServices _services;
  final GoogleSignIn _googleSignIn;
  Future<BillingService?>? _billingService;
  Map<String, String>? _authHeaders;
  GoogleSignInAccount? _googleAccount;
  late final StreamSubscription<GoogleSignInAccount?> _accountSubscription;
  Queue<Video> _transcriptQueue = Queue<Video>();
  bool _isProcessingQueue = false;
  bool _pendingQueueRestart = false;
  int _queueGeneration = 0;
  DateTime? _lastRefreshAt;
  static const _refreshCooldown = Duration(seconds: 10);
  static const List<String> _youtubeScopes = <String>[
    'https://www.googleapis.com/auth/youtube.readonly',
  ];
  bool _isRestoringSession = false;

  DateTime _now() => _services.now();

  bool canSelectMore() {
    final limit = state.channelLimit;
    if (limit <= 0) return false;
    return state.selectedCount < limit;
  }

  bool isTranscriptLoading(String videoId) =>
      state.transcriptLoading.contains(videoId);

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      _setToast('웹에서는 Google 로그인 버튼을 사용해주세요.');
      return;
    }
    _setLoading(true);
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        _setLoading(false);
        return;
      }
      await _processSignedInAccount(account, allowInteractive: true);
    } catch (error) {
      _setToast(kDebugMode
          ? 'Google 로그인 실패: $error'
          : 'Google 로그인에 실패했습니다. 다시 시도해주세요.');
    }
    _setLoading(false);
  }

  Future<void> connectYouTubeAccount() async {
    _setLoading(true);
    try {
      if (_googleAccount == null) {
        await signInWithGoogle();
      } else {
        await _connectAndSyncYouTube(allowInteractive: true);
      }
    } catch (error) {
      _setToast(kDebugMode ? '연동 실패: $error' : 'YouTube 연동에 실패했습니다.');
    }
    _setLoading(false);
  }

  Future<void> refreshSubscriptions() async {
    _setLoading(true);
    try {
      await _loadChannels(allowInteractive: true);
    } catch (error) {
      _setToast(kDebugMode ? '구독 채널 로드 실패: $error' : '구독 채널을 다시 불러오지 못했습니다.');
    }
    _setLoading(false);
  }

  Future<void> refreshHome() async {
    if (state.selectedChannelIds.isEmpty) {
      _setToast('먼저 채널 선택을 완료해주세요.');
      return;
    }
    if (state.isLoading) return;
    final now = _now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshCooldown) {
      final remaining = _refreshCooldown.inSeconds -
          now.difference(_lastRefreshAt!).inSeconds;
      _setToast('$remaining초 후에 새로고침할 수 있습니다.');
      return;
    }
    _lastRefreshAt = now;
    _setLoading(true);
    try {
      await _loadSelectedVideos(allowInteractive: true);
    } catch (error) {
      _setToast(
        kDebugMode ? '영상 새로고침 실패: $error' : '영상을 다시 불러오지 못했습니다.',
      );
    }
    _setLoading(false);
  }

  void toggleChannel(String channelId) {
    final selected = Set<String>.from(state.selectedChannelIds);
    final limit = state.channelLimit;
    final isSelected = selected.contains(channelId);
    final isCompleted = state.selectionCompleted;
    final isSwapPending = state.selectionChangePending;
    final hasFreeSlots = limit > 0 && selected.length < limit;
    final swapCompleted =
        state.dailySwapAddedId != null && state.dailySwapRemovedId != null;

    if (isCompleted && !isSelected && !isSwapPending && hasFreeSlots) {
      selected.add(channelId);
      state = state.copyWith(selectedChannelIds: Set.unmodifiable(selected));
      return;
    }

    if (isCompleted && !isSwapPending && !_canChangeSelectionToday()) {
      _setToast('오늘은 채널 변경을 이미 1회 사용했습니다. 내일 다시 변경할 수 있어요.');
      return;
    }

    if (isCompleted && swapCompleted) {
      _setToast('오늘은 1개 교체만 가능합니다. 변경을 저장하려면 완료를 눌러주세요.');
      return;
    }

    if (isSelected) {
      if (isCompleted && !_canRemoveChannel(channelId, selected)) {
        _setToast('오늘은 채널 1개만 교체할 수 있습니다. 추가/제거를 더 진행할 수 없어요.');
        return;
      }
      selected.remove(channelId);
      state = state.copyWith(
        selectedChannelIds: Set.unmodifiable(selected),
        selectionChangePending:
            isCompleted ? true : state.selectionChangePending,
        dailySwapRemovedId:
            isCompleted ? (state.dailySwapRemovedId ?? channelId) : null,
      );
      return;
    }

    if (!canSelectMore()) {
      _setToast('채널 한도가 가득 찼습니다. 다른 채널을 하나 해제한 뒤 추가해주세요.');
      return;
    }

    if (isCompleted && !_canAddChannel(channelId)) {
      _setToast('오늘은 채널 1개만 교체할 수 있습니다. 추가/제거를 더 진행할 수 없어요.');
      return;
    }

    selected.add(channelId);
    state = state.copyWith(
      selectedChannelIds: Set.unmodifiable(selected),
      selectionChangePending: isCompleted ? true : state.selectionChangePending,
      dailySwapAddedId:
          isCompleted ? (state.dailySwapAddedId ?? channelId) : null,
    );
  }

  void clearToast() {
    state = state.copyWith(toastMessage: null);
  }

  Future<void> finalizeChannelSelection() async {
    _setLoading(true);
    try {
      if (state.selectionCompleted && state.selectionChangePending) {
        if (state.dailySwapAddedId == null ||
            state.dailySwapRemovedId == null) {
          _setToast('채널 변경은 1개 교체(제거 1 + 추가 1)로 완료됩니다.');
          _setLoading(false);
          return;
        }
      }
      await _loadSelectedVideos(allowInteractive: true);
      final shouldConsumeChange =
          state.selectionCompleted && state.selectionChangePending;
      if (shouldConsumeChange) {
        _recordSelectionChange();
      }
      await _persistSelectionToServer();
      state = state.copyWith(
        selectionCompleted: true,
        selectionChangePending: false,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
      );
    } catch (error) {
      _setToast(kDebugMode ? '영상 로드 실패: $error' : '선택한 채널의 영상을 불러오지 못했습니다.');
    }
    _setLoading(false);
  }

  Future<void> toggleArchive(String videoId) async {
    final previous = List<ArchiveEntry>.from(state.archives);
    final archives = List<ArchiveEntry>.from(previous);
    final existingIndex =
        archives.indexWhere((entry) => entry.videoId == videoId);
    final willArchive = existingIndex < 0;
    if (existingIndex >= 0) {
      archives.removeAt(existingIndex);
    } else {
      archives.add(ArchiveEntry(videoId: videoId, archivedAt: _now()));
    }
    state = state.copyWith(archives: List.unmodifiable(archives));

    final userId = state.user?.id;
    if (userId == null) return;
    final result =
        await _services.archiveService.toggleArchive(userId, videoId);
    if (result == null) {
      state = state.copyWith(archives: List.unmodifiable(previous));
      _setToast('즐겨찾기를 저장하지 못했습니다. 다시 시도해주세요.');
      return;
    }

    if (willArchive && result.archivedAt != null) {
      final updated = List<ArchiveEntry>.from(state.archives);
      final index = updated.indexWhere((entry) => entry.videoId == videoId);
      if (index >= 0) {
        updated[index] = ArchiveEntry(
          videoId: videoId,
          archivedAt: result.archivedAt!,
        );
        state = state.copyWith(archives: List.unmodifiable(updated));
      }
    }
  }

  bool isArchived(String videoId) {
    return state.archives.any((entry) => entry.videoId == videoId);
  }

  List<Video> archivedVideos() {
    final archivedIds = state.archives.map((e) => e.videoId).toSet();
    return state.videos
        .where((video) => archivedIds.contains(video.id))
        .toList();
  }

  Map<DateTime, List<Video>> archivesByDay() {
    final Map<DateTime, List<Video>> grouped = {};
    final videoMap = {for (final v in state.videos) v.id: v};
    for (final entry in state.archives) {
      final video = videoMap[entry.videoId];
      if (video == null) continue;
      final day = DateTime(
          entry.archivedAt.year, entry.archivedAt.month, entry.archivedAt.day);
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
      _loadSelectedVideosSilently();
    }
  }

  void signOut() {
    _googleSignIn.signOut();
    _authHeaders = null;
    _googleAccount = null;
    BackendApi.setIdToken(null);
    state = AppStateData.initial();
  }

  @override
  void dispose() {
    _accountSubscription.cancel();
    super.dispose();
  }

  Future<BillingService?> _getBillingService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    _billingService ??= _services.billingServiceFactory();
    return _billingService!;
  }

  String _productIdForTier(PlanTier tier) {
    switch (tier) {
      case PlanTier.starter:
        return AppConfig.iosPlusProductId;
      case PlanTier.growth:
        return AppConfig.iosProProductId;
      case PlanTier.unlimited:
        return AppConfig.iosUnlimitedProductId;
      case PlanTier.free:
      case PlanTier.lifetime:
        return '';
    }
  }

  static const String purchaseMissingProductId = 'iap_missing_product_id';
  static const String purchaseUnavailable = 'iap_unavailable';
  static const String purchaseFailed = 'iap_failed';
  static const String restoreUnavailable = 'iap_restore_unavailable';
  static const String restoreNone = 'iap_restore_none';
  static const String restoreNotFound = 'iap_restore_not_found';

  Future<String?> purchasePlan(PlanTier tier) async {
    if (tier == PlanTier.free) {
      upgradePlan(tier);
      return null;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return purchaseUnavailable;
    }

    final productId = _productIdForTier(tier);
    if (productId.isEmpty) {
      return purchaseMissingProductId;
    }

    final billing = await _getBillingService();
    if (billing == null || !(await billing.isAvailable())) {
      return purchaseUnavailable;
    }

    final purchase = await billing.purchase(productId);
    if (purchase == null) {
      return purchaseFailed;
    }

    upgradePlan(tier);
    await _persistPlan(tier);
    return null;
  }

  Future<String?> restorePurchases() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return restoreUnavailable;
    }
    final billing = await _getBillingService();
    if (billing == null || !(await billing.isAvailable())) {
      return restoreUnavailable;
    }
    final purchases = await billing.restore();
    if (purchases.isEmpty) {
      return restoreNone;
    }

    final restoredTier = _resolveTierFromPurchases(purchases);
    if (restoredTier == null) {
      return restoreNotFound;
    }
    upgradePlan(restoredTier);
    await _persistPlan(restoredTier);
    return null;
  }

  PlanTier? _resolveTierFromPurchases(List<dynamic> purchases) {
    final ids = purchases
        .map((p) {
          if (p is String) return p;
          try {
            return (p as dynamic).productID as String?;
          } catch (_) {
            return null;
          }
        })
        .whereType<String>()
        .toSet();

    if (ids.contains(AppConfig.iosUnlimitedProductId)) {
      return PlanTier.unlimited;
    }
    if (ids.contains(AppConfig.iosProProductId)) {
      return PlanTier.growth;
    }
    if (ids.contains(AppConfig.iosPlusProductId)) {
      return PlanTier.starter;
    }
    return null;
  }

  Future<void> _persistPlan(PlanTier tier) async {
    final userId = state.user?.id;
    if (userId == null) return;
    await _services.userService.updatePlan(userId, tier.name);
  }

  Future<void> _syncUserProfile() async {
    final user = state.user;
    if (user == null) return;
    final profile = await _services.userService.upsertUser(
      userId: user.id,
      email: user.email,
      planTier: user.plan.tier.name,
    );
    if (profile == null) return;
    final tier = _tierFromString(profile.planTier);
    if (tier == null || tier == user.plan.tier) return;
    state = state.copyWith(
      user: User(
        id: user.id,
        email: user.email,
        plan: Plan(tier: tier),
        createdAt: user.createdAt,
      ),
    );
  }

  PlanTier? _tierFromString(String? value) {
    switch (value) {
      case 'free':
        return PlanTier.free;
      case 'starter':
        return PlanTier.starter;
      case 'growth':
        return PlanTier.growth;
      case 'unlimited':
        return PlanTier.unlimited;
      case 'lifetime':
        return PlanTier.lifetime;
    }
    return null;
  }

  Future<void> clearCachedSummaries() async {
    final userId = state.user?.id ?? 'anonymous';
    try {
      final cache = await _services.transcriptCache;
      await cache.clearUser(userId);
    } catch (_) {
      // Ignore cache failures.
    }
    state = state.copyWith(
      transcripts: const <String, TranscriptResult>{},
      transcriptLoading: const <String>{},
      transcriptQueued: const <String>{},
    );
  }

  Future<void> clearVideoHistory() async {
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _services.videoHistoryCache;
      await cache.clear(userId);
    } catch (_) {
      // Ignore cache failures.
    }
    state = state.copyWith(openedVideoIds: const <String>{});
  }

  Future<void> clearFavorites() async {
    if (state.archives.isEmpty) return;
    final previous = List<ArchiveEntry>.from(state.archives);
    state = state.copyWith(archives: const <ArchiveEntry>[]);
    final userId = state.user?.id;
    if (userId == null) return;
    final ok = await _services.archiveService.clearArchives(userId);
    if (!ok) {
      state = state.copyWith(archives: List.unmodifiable(previous));
      _setToast('즐겨찾기 삭제에 실패했습니다.');
    }
  }

  Future<void> resetSelectionCooldown() async {
    final userId = state.user?.id;
    if (userId == null) return;
    state = state.copyWith(
      selectionChangeDay: 0,
      selectionChangesToday: 0,
      selectionChangePending: false,
      dailySwapAddedId: null,
      dailySwapRemovedId: null,
    );
    try {
      final cache = await _services.selectionChangeCache;
      await cache.clear(userId);
    } catch (_) {
      // Ignore cache failures.
    }
  }

  Future<void> resetChannelSelection() async {
    state = state.copyWith(
      selectedChannelIds: const <String>{},
      selectionCompleted: false,
      selectionChangeDay: 0,
      selectionChangesToday: 0,
      selectionChangePending: false,
      dailySwapAddedId: null,
      dailySwapRemovedId: null,
      videos: const <Video>[],
      transcripts: const <String, TranscriptResult>{},
      transcriptLoading: const <String>{},
      transcriptQueued: const <String>{},
      archives: const <ArchiveEntry>[],
    );
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _services.selectionChangeCache;
      await cache.clear(userId);
    } catch (_) {
      // Ignore cache failures.
    }
  }

  Set<String> _normalizeSelection(List<Channel> channels) {
    if (channels.isEmpty || state.selectedChannelIds.isEmpty) {
      return state.selectedChannelIds;
    }
    final available = channels.map((channel) => channel.id).toSet();
    final filtered =
        state.selectedChannelIds.where(available.contains).toList();
    final limit = state.channelLimit;
    if (limit <= 0) return <String>{};
    return filtered.take(limit).toSet();
  }

  int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

  Future<void> _loadSelectionChangeState() async {
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _services.selectionChangeCache;
      final data = await cache.read(userId);
      if (data == null) {
        state = state.copyWith(
          selectionChangeDay: 0,
          selectionChangesToday: 0,
          dailySwapAddedId: null,
          dailySwapRemovedId: null,
          selectionChangePending: false,
        );
        return;
      }
      state = state.copyWith(
        selectionChangeDay: data.dayKey,
        selectionChangesToday: data.changesToday,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
        selectionChangePending: false,
      );
    } catch (_) {
      // Ignore cache read failures.
    }
  }

  Future<void> _loadVideoHistoryState() async {
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _services.videoHistoryCache;
      final ids = await cache.read(userId);
      state = state.copyWith(openedVideoIds: Set.unmodifiable(ids));
    } catch (_) {
      // Ignore cache failures.
    }
  }

  Future<void> recordVideoInteraction(String videoId) async {
    final userId = state.user?.id;
    if (userId == null || videoId.isEmpty) return;
    if (state.openedVideoIds.contains(videoId)) return;
    final updated = Set<String>.from(state.openedVideoIds)..add(videoId);
    state = state.copyWith(openedVideoIds: Set.unmodifiable(updated));
    try {
      final cache = await _services.videoHistoryCache;
      await cache.write(userId, updated);
    } catch (_) {
      // Ignore cache failures.
    }
  }

  bool _canChangeSelectionToday() {
    final todayKey = _dayKey(_now());
    if (state.selectionChangeDay != todayKey) {
      _resetSelectionChange(todayKey);
      return true;
    }
    return state.selectionChangesToday < 1;
  }

  bool _canAddChannel(String channelId) {
    if (!state.selectionCompleted) return true;
    if (!state.selectionChangePending) return true;
    final added = state.dailySwapAddedId;
    return added == null || added == channelId;
  }

  bool _canRemoveChannel(String channelId, Set<String> selected) {
    if (!state.selectionCompleted) return true;
    if (!state.selectionChangePending) {
      return selected.length > 1;
    }
    final removed = state.dailySwapRemovedId;
    if (removed == null || removed == channelId) {
      return true;
    }
    return false;
  }

  void _recordSelectionChange() {
    final todayKey = _dayKey(_now());
    final count = state.selectionChangeDay == todayKey
        ? state.selectionChangesToday + 1
        : 1;
    state = state.copyWith(
        selectionChangeDay: todayKey, selectionChangesToday: count);
    _persistSelectionChange(todayKey, count);
  }

  void _resetSelectionChange(int todayKey) {
    state = state.copyWith(
      selectionChangeDay: todayKey,
      selectionChangesToday: 0,
      dailySwapAddedId: null,
      dailySwapRemovedId: null,
      selectionChangePending: false,
    );
    _persistSelectionChange(todayKey, 0);
  }

  Future<void> _persistSelectionChange(int dayKey, int count) async {
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _services.selectionChangeCache;
      await cache.write(
          userId, SelectionChangeState(dayKey: dayKey, changesToday: count));
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
    _isRestoringSession = true;
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) {
        _setLoading(false);
        _isRestoringSession = false;
        return;
      }
      await _processSignedInAccount(
        account,
        showErrors: false,
        allowInteractive: false,
      );
    } catch (_) {
      // Ignore silent sign-in failures.
    }
    _isRestoringSession = false;
    _setLoading(false);
  }

  void _handleAccountChange(GoogleSignInAccount? account) {
    if (account == null) return;
    if (_googleAccount?.id == account.id && _authHeaders != null) {
      unawaited(_refreshBackendAuthToken(account));
      return;
    }
    _processSignedInAccount(
      account,
      allowInteractive: !_isRestoringSession,
    );
  }

  Future<void> _processSignedInAccount(
    GoogleSignInAccount account, {
    bool showErrors = true,
    bool allowInteractive = false,
  }) async {
    _setLoading(true);
    try {
      _googleAccount = account;
      _authHeaders = await account.authHeaders;
      await _refreshBackendAuthToken(account);
      state = state.copyWith(
        user: User(
          id: account.id,
          email: account.email,
          plan: const Plan(tier: PlanTier.free),
          createdAt: _now(),
        ),
      );
      await Future.wait([_syncUserProfile(), _loadVideoHistoryState()]);
      try {
        await Future.wait([
          _connectAndSyncYouTube(allowInteractive: allowInteractive),
          _loadArchivesFromServer(),
        ]);
      } catch (error) {
        if (showErrors) {
          _setToast(kDebugMode
              ? 'YouTube 동기화 실패: $error'
              : 'YouTube 구독 채널을 불러오지 못했습니다.');
        }
      }
    } catch (error) {
      if (showErrors) {
        _setToast(kDebugMode
            ? 'Google 로그인 실패: $error'
            : 'Google 로그인에 실패했습니다. 다시 시도해주세요.');
      }
    }
    _setLoading(false);
  }

  Future<void> _refreshBackendAuthToken(GoogleSignInAccount account) async {
    try {
      final authentication = await account.authentication;
      BackendApi.setIdToken(authentication.idToken);
    } catch (_) {
      BackendApi.setIdToken(null);
    }
  }

  Future<void> _connectAndSyncYouTube({bool allowInteractive = false}) async {
    if (_googleAccount == null) {
      throw Exception('로그인이 필요합니다.');
    }
    state = state.copyWith(selectionCompleted: false);
    try {
      await _loadSelectionChangeState();
      await _loadChannels(allowInteractive: allowInteractive);
      state = state.copyWith(youtubeConnected: true);
      await _loadSelectionFromServer();
    } catch (_) {
      state = state.copyWith(youtubeConnected: false);
      rethrow;
    }
  }

  Future<void> _loadArchivesFromServer() async {
    final userId = state.user?.id;
    if (userId == null) return;
    final entries = await _services.archiveService.fetchArchives(userId);
    if (entries == null) {
      return;
    }
    state = state.copyWith(archives: List.unmodifiable(entries));
  }

  Future<void> _loadChannels({bool allowInteractive = false}) async {
    await _ensureYouTubeAccess(allowInteractive: allowInteractive);
    final api = _services.youtubeApiFactory(_authHeaders!);
    List<Channel> channels;
    try {
      channels = await api.fetchSubscriptions();
    } on YouTubeApiException catch (error) {
      if (_shouldRetryAuth(error.statusCode) && allowInteractive) {
        await _ensureYouTubeAccess(
          allowInteractive: allowInteractive,
          forceRefresh: true,
        );
        channels = await _services
            .youtubeApiFactory(_authHeaders!)
            .fetchSubscriptions();
      } else {
        rethrow;
      }
    }
    final normalized = _normalizeSelection(channels);
    state = state.copyWith(
      channels: List.unmodifiable(channels),
      selectedChannelIds: Set.unmodifiable(normalized),
    );
  }

  Future<void> _loadSelectionFromServer() async {
    final userId = state.user?.id;
    if (userId == null) return;
    final selected = await _services.selectionService.fetchSelection(userId);
    if (selected == null || selected.isEmpty) return;
    final available = state.channels.map((channel) => channel.id).toSet();
    final filtered = selected.where(available.contains).toSet();
    if (filtered.isEmpty) return;
    final limit = state.channelLimit;
    final limited = limit > 0 ? filtered.take(limit).toSet() : filtered;
    state = state.copyWith(selectedChannelIds: Set.unmodifiable(limited));
  }

  Future<void> _persistSelectionToServer() async {
    final userId = state.user?.id;
    if (userId == null) return;
    await _services.selectionService.saveSelection(
      userId: userId,
      channels: state.channels,
      selectedIds: state.selectedChannelIds,
    );
  }

  Future<void> _loadSelectedVideos({bool allowInteractive = false}) async {
    if (state.selectedChannelIds.isEmpty) return;
    await _ensureYouTubeAccess(allowInteractive: allowInteractive);
    final api = _services.youtubeApiFactory(_authHeaders!);
    List<Video> videos;
    try {
      videos = await api.fetchLatestVideos(state.selectedChannelIds.toList());
    } on YouTubeApiException catch (error) {
      if (_shouldRetryAuth(error.statusCode) && allowInteractive) {
        await _ensureYouTubeAccess(
          allowInteractive: allowInteractive,
          forceRefresh: true,
        );
        videos = await _services
            .youtubeApiFactory(_authHeaders!)
            .fetchLatestVideos(state.selectedChannelIds.toList());
      } else {
        rethrow;
      }
    }
    state = state.copyWith(
      videos: List.unmodifiable(videos),
      transcripts: const <String, TranscriptResult>{},
      transcriptLoading: const <String>{},
      transcriptQueued: const <String>{},
    );
    _queueGeneration += 1;
    _transcriptQueue = Queue<Video>();
    _pendingQueueRestart = false;
  }

  void _loadSelectedVideosSilently() {
    if (_googleAccount == null || state.selectedChannelIds.isEmpty) {
      return;
    }
    unawaited(_loadSelectedVideos().catchError((_) {
      // Ignore background refresh failures.
    }));
  }

  bool _shouldRetryAuth(int statusCode) =>
      statusCode == 401 || statusCode == 403;

  Future<void> _ensureYouTubeAccess({
    required bool allowInteractive,
    bool forceRefresh = false,
  }) async {
    if (_googleAccount == null) {
      throw Exception('로그인이 필요합니다.');
    }
    if (kIsWeb) {
      bool canAccess = false;
      if (!forceRefresh) {
        try {
          canAccess = await _googleSignIn.canAccessScopes(_youtubeScopes);
        } catch (_) {
          canAccess = false;
        }
      }
      if (!canAccess) {
        if (!allowInteractive) {
          throw Exception('YouTube 권한이 필요합니다.');
        }
        final granted = await _googleSignIn.requestScopes(_youtubeScopes);
        if (!granted) {
          throw Exception('YouTube 권한이 필요합니다.');
        }
      }
    }
    _authHeaders = await _googleAccount!.authHeaders;
    await _refreshBackendAuthToken(_googleAccount!);
  }

  Future<void> _processTranscriptQueue(int generation) async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_transcriptQueue.isNotEmpty && generation == _queueGeneration) {
      final video = _transcriptQueue.removeFirst();
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
    recordVideoInteraction(video.youtubeId);
    final existing = state.transcripts[video.id];
    if (existing != null &&
        existing.source != 'error' &&
        (existing.summary ?? '').trim().isNotEmpty) {
      return;
    }
    if (state.transcriptLoading.contains(video.id)) {
      return;
    }
    if (state.transcriptQueued.contains(video.id)) {
      return;
    }
    if (_transcriptQueue.any((queued) => queued.id == video.id)) {
      return;
    }

    _transcriptQueue.addLast(video);
    final queued = Set<String>.from(state.transcriptQueued)..add(video.id);
    state = state.copyWith(transcriptQueued: Set.unmodifiable(queued));
    if (_isProcessingQueue) {
      _pendingQueueRestart = true;
      return;
    }
    _processTranscriptQueue(_queueGeneration);
  }

  Future<void> _fetchTranscriptFor(Video video) async {
    if (state.transcripts.containsKey(video.id) ||
        state.transcriptLoading.contains(video.id)) {
      final queued = Set<String>.from(state.transcriptQueued)..remove(video.id);
      state = state.copyWith(transcriptQueued: Set.unmodifiable(queued));
      return;
    }

    final queued = Set<String>.from(state.transcriptQueued)..remove(video.id);
    final cached = await _readCachedTranscript(video);
    if (cached != null) {
      state = state.copyWith(
        transcripts: Map<String, TranscriptResult>.from(state.transcripts)
          ..[video.id] = cached,
        transcriptQueued: Set.unmodifiable(queued),
      );
      return;
    }

    final loading = Set<String>.from(state.transcriptLoading)..add(video.id);
    state = state.copyWith(
      transcriptLoading: Set.unmodifiable(loading),
      transcriptQueued: Set.unmodifiable(queued),
    );

    final transcript =
        await _services.transcriptService.fetchTranscript(video.youtubeId);
    final updatedLoading = Set<String>.from(state.transcriptLoading)
      ..remove(video.id);

    if (transcript != null && transcript.text.trim().isNotEmpty) {
      final updatedTranscripts =
          Map<String, TranscriptResult>.from(state.transcripts)
            ..[video.id] = transcript;
      state = state.copyWith(
        transcripts: Map.unmodifiable(updatedTranscripts),
        transcriptLoading: Set.unmodifiable(updatedLoading),
        transcriptQueued: Set.unmodifiable(queued),
      );
      await _writeCachedTranscript(video, transcript);
    } else {
      state = state.copyWith(
        transcriptLoading: Set.unmodifiable(updatedLoading),
        transcriptQueued: Set.unmodifiable(queued),
      );
    }
  }

  void _handleTranscriptFailure(Video video, Object error) {
    final updatedLoading = Set<String>.from(state.transcriptLoading)
      ..remove(video.id);
    final queued = Set<String>.from(state.transcriptQueued)..remove(video.id);
    final rawError = error.toString().toLowerCase();
    final isMembershipError =
        rawError.contains('member') || rawError.contains('membership');
    final message = isMembershipError
        ? 'You might not have membership for this video.'
        : (kDebugMode
            ? '요약 실패: $error'
            : '요약 생성 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.');
    final updatedTranscripts =
        Map<String, TranscriptResult>.from(state.transcripts)
          ..[video.id] = TranscriptResult(
            text: message,
            source: 'error',
            partial: false,
          );
    state = state.copyWith(
      transcripts: Map.unmodifiable(updatedTranscripts),
      transcriptLoading: Set.unmodifiable(updatedLoading),
      transcriptQueued: Set.unmodifiable(queued),
    );
  }

  Future<TranscriptResult?> _readCachedTranscript(Video video) async {
    try {
      final cache = await _services.transcriptCache;
      return cache.read(
        userId: state.user?.id ?? 'anonymous',
        videoId: video.youtubeId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedTranscript(
      Video video, TranscriptResult transcript) async {
    if (transcript.source == 'error') return;
    try {
      final cache = await _services.transcriptCache;
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
