import 'dart:async';

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
import '../services/selection_change_cache.dart';
import '../services/user_state_service.dart';
import 'auth_session_controller.dart';
import 'channel_sync_controller.dart';
import 'plan_billing_controller.dart';
import 'selection_policy.dart';
import 'transcript_queue_controller.dart';

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
              // google_sign_in_web does not support serverClientId.
              serverClientId:
                  !kIsWeb && AppConfig.googleServerClientId.isNotEmpty
                      ? AppConfig.googleServerClientId
                      : null,
            ),
        super(initialState ?? AppStateData.initial()) {
    _accountSubscription =
        _googleSignIn.onCurrentUserChanged.listen(_handleAccountChange);
    if (kIsWeb) {
      _primeGoogleSignInForWeb();
    }
    if (restoreSession) {
      _restoreSession();
    }
  }

  final AppServices _services;
  final GoogleSignIn _googleSignIn;
  final AuthSessionController _authSession = AuthSessionController();
  late final ChannelSyncController _channelSync = ChannelSyncController(
    selectionService: _services.selectionService,
    youtubeApiFactory: _services.youtubeApiFactory,
  );
  late final PlanBillingController _planBilling = PlanBillingController(
    gatewayFactory: () async {
      final service = await _services.billingServiceFactory();
      if (service == null) return null;
      return BillingServiceGateway(service);
    },
    isIapSupportedPlatform:
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
    iosPlusProductId: AppConfig.iosPlusProductId,
    iosProProductId: AppConfig.iosProProductId,
    iosUnlimitedProductId: AppConfig.iosUnlimitedProductId,
  );
  final TranscriptQueueController _transcriptQueueController =
      TranscriptQueueController();
  late final StreamSubscription<GoogleSignInAccount?> _accountSubscription;
  DateTime? _lastRefreshAt;
  static const _refreshCooldown = Duration(seconds: 10);
  static const List<String> _youtubeScopes = <String>[
    'https://www.googleapis.com/auth/youtube.readonly',
  ];
  static const Duration _scopeCheckTimeout = Duration(seconds: 8);
  static const Duration _scopeRequestTimeout = Duration(seconds: 20);
  static const Duration _authHeadersTimeout = Duration(seconds: 12);
  static const Duration _initialSyncTimeout = Duration(seconds: 25);
  static const String _e2eUserId = 'e2e_user_0001';
  static const String _e2eUserEmail = 'e2e-user@example.com';
  bool _isRestoringSession = false;

  DateTime _now() => _services.now();
  bool _isAuthFlowCurrent(int revision) =>
      mounted && _authSession.isFlowCurrent(revision);
  bool _isCurrentAccountId(String accountId) =>
      _authSession.matchesAccountId(accountId);

  void _clearAuthSession() {
    _authSession.clearSession();
  }

  Map<String, String> _currentAuthHeaders() {
    final headers = _authSession.authHeaders;
    if (headers == null) {
      throw Exception('로그인 상태가 변경되었습니다. 다시 시도해주세요.');
    }
    return headers;
  }

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

  Future<void> signInForE2E() async {
    if (!AppConfig.e2eTestMode) {
      return;
    }
    _setLoading(true);
    try {
      await _bootstrapE2EUserSession();
    } catch (error) {
      _setToast(
        kDebugMode ? 'E2E 로그인 실패: $error' : '테스트 로그인에 실패했습니다.',
      );
    }
    _setLoading(false);
  }

  Future<void> connectYouTubeAccount() async {
    _setLoading(true);
    try {
      if (_authSession.account == null) {
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
    var canChangeSelectionToday = true;
    if (state.selectionCompleted && !state.selectionChangePending) {
      canChangeSelectionToday = _canChangeSelectionToday();
    }
    final outcome = SelectionPolicy.toggle(
      SelectionPolicyInput(
        channelId: channelId,
        selectedChannelIds: state.selectedChannelIds,
        channelLimit: state.channelLimit,
        selectionCompleted: state.selectionCompleted,
        selectionChangePending: state.selectionChangePending,
        dailySwapAddedId: state.dailySwapAddedId,
        dailySwapRemovedId: state.dailySwapRemovedId,
        canChangeSelectionToday: canChangeSelectionToday,
      ),
    );
    if (outcome.toastMessage != null) {
      _setToast(outcome.toastMessage!);
    }
    if (!outcome.changed) {
      return;
    }
    state = state.copyWith(
      selectedChannelIds: outcome.selectedChannelIds,
      selectionChangePending: outcome.selectionChangePending,
      dailySwapAddedId: outcome.dailySwapAddedId,
      dailySwapRemovedId: outcome.dailySwapRemovedId,
    );
  }

  bool _validatePendingSwapSelection() {
    final result = SelectionPolicy.validatePendingSwap(
      selectionCompleted: state.selectionCompleted,
      selectionChangePending: state.selectionChangePending,
      dailySwapAddedId: state.dailySwapAddedId,
      dailySwapRemovedId: state.dailySwapRemovedId,
    );
    if (result.toastMessage != null) {
      _setToast(result.toastMessage!);
    }
    return result.isValid;
  }

  void clearToast() {
    state = state.copyWith(toastMessage: null);
  }

  Future<bool> finalizeChannelSelection() async {
    if (state.isLoading) {
      return false;
    }
    _setLoading(true);
    try {
      if (!_validatePendingSwapSelection()) {
        return false;
      }
      await _loadSelectedVideos(allowInteractive: true);
      final shouldConsumeChange =
          state.selectionCompleted && state.selectionChangePending;
      final saved = await _persistSelectionToServer();
      if (!saved) {
        _setToast('채널 선택을 저장하지 못했습니다. 다시 시도해주세요.');
        return false;
      }
      if (shouldConsumeChange) {
        await _recordSelectionChange();
      }
      state = state.copyWith(
        selectionCompleted: true,
        selectionChangePending: false,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
      );
      return true;
    } catch (error) {
      _setToast(kDebugMode ? '영상 로드 실패: $error' : '선택한 채널의 영상을 불러오지 못했습니다.');
      return false;
    } finally {
      _setLoading(false);
    }
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
    _authSession.invalidateFlow();
    _isRestoringSession = false;
    unawaited(_googleSignIn.signOut().catchError((_) => null));
    _clearAuthSession();
    state = AppStateData.initial();
  }

  @override
  void dispose() {
    _accountSubscription.cancel();
    super.dispose();
  }

  static const String purchaseMissingProductId =
      PlanBillingController.purchaseMissingProductId;
  static const String purchaseUnavailable =
      PlanBillingController.purchaseUnavailable;
  static const String purchaseFailed = PlanBillingController.purchaseFailed;
  static const String restoreUnavailable =
      PlanBillingController.restoreUnavailable;
  static const String restoreNone = PlanBillingController.restoreNone;
  static const String restoreNotFound = PlanBillingController.restoreNotFound;

  Future<String?> purchasePlan(PlanTier tier) async {
    return _planBilling.purchasePlan(
      tier: tier,
      onActivateLocalPlan: (resolvedTier) async {
        upgradePlan(resolvedTier);
      },
      onPersistPlan: _persistPlan,
    );
  }

  Future<String?> restorePurchases() async {
    return _planBilling.restorePurchases(
      onActivateLocalPlan: (resolvedTier) async {
        upgradePlan(resolvedTier);
      },
      onPersistPlan: _persistPlan,
    );
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
    final synced = await _persistUserStateToServer(openedVideoIds: <String>{});
    if (!synced) {
      _setToast('시청 기록 서버 동기화에 실패했습니다.');
    }
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
    final synced = await _persistUserStateToServer(
      selectionChangeDay: 0,
      selectionChangesToday: 0,
    );
    if (!synced) {
      _setToast('채널 변경 상태 서버 동기화에 실패했습니다.');
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
    final saved = await _persistSelectionToServer();
    try {
      final cache = await _services.selectionChangeCache;
      await cache.clear(userId);
    } catch (_) {
      // Ignore cache failures.
    }
    final synced = await _persistUserStateToServer(
      selectionChangeDay: 0,
      selectionChangesToday: 0,
    );
    if (!saved || !synced) {
      _setToast('채널 선택 초기화 상태를 서버에 저장하지 못했습니다.');
    }
  }

  int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

  Future<void> _loadSelectionChangeState(
      {UserStatePayload? remoteState}) async {
    final userId = state.user?.id;
    if (userId == null) return;
    SelectionChangeState? localData;
    try {
      final cache = await _services.selectionChangeCache;
      localData = await cache.read(userId);
    } catch (_) {
      localData = null;
    }

    final remote =
        remoteState ?? await _services.userStateService.fetchState(userId);
    if (remote != null) {
      var mergedDay = remote.selectionChangeDay;
      var mergedCount = remote.selectionChangesToday;
      if (localData != null) {
        if (localData.dayKey > mergedDay) {
          mergedDay = localData.dayKey;
          mergedCount = localData.changesToday;
        } else if (localData.dayKey == mergedDay &&
            localData.changesToday > mergedCount) {
          mergedCount = localData.changesToday;
        }
      }
      state = state.copyWith(
        selectionChangeDay: mergedDay,
        selectionChangesToday: mergedCount,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
        selectionChangePending: false,
      );
      try {
        final cache = await _services.selectionChangeCache;
        await cache.write(
          userId,
          SelectionChangeState(
            dayKey: mergedDay,
            changesToday: mergedCount,
          ),
        );
      } catch (_) {
        // Ignore cache write failures.
      }
      if (mergedDay != remote.selectionChangeDay ||
          mergedCount != remote.selectionChangesToday) {
        await _persistUserStateToServer(
          selectionChangeDay: mergedDay,
          selectionChangesToday: mergedCount,
        );
      }
      return;
    }

    if (localData == null) {
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
      selectionChangeDay: localData.dayKey,
      selectionChangesToday: localData.changesToday,
      dailySwapAddedId: null,
      dailySwapRemovedId: null,
      selectionChangePending: false,
    );
  }

  Future<void> _loadVideoHistoryState({UserStatePayload? remoteState}) async {
    final userId = state.user?.id;
    if (userId == null) return;
    Set<String> localIds = <String>{};
    try {
      final cache = await _services.videoHistoryCache;
      localIds = await cache.read(userId);
    } catch (_) {
      localIds = <String>{};
    }

    final remote =
        remoteState ?? await _services.userStateService.fetchState(userId);
    if (remote != null) {
      final merged = <String>{...remote.openedVideoIds, ...localIds};
      state = state.copyWith(
        openedVideoIds: Set.unmodifiable(merged),
      );
      try {
        final cache = await _services.videoHistoryCache;
        await cache.write(userId, merged);
      } catch (_) {
        // Ignore cache write failures.
      }
      if (merged.length != remote.openedVideoIds.length) {
        await _persistUserStateToServer(openedVideoIds: merged);
      }
      return;
    }
    state = state.copyWith(openedVideoIds: Set.unmodifiable(localIds));
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
    await _persistUserStateToServer(openedVideoIds: updated);
  }

  bool _canChangeSelectionToday() {
    final todayKey = _dayKey(_now());
    if (state.selectionChangeDay != todayKey) {
      _resetSelectionChange(todayKey);
      return true;
    }
    return state.selectionChangesToday < 1;
  }

  Future<void> _recordSelectionChange() async {
    final todayKey = _dayKey(_now());
    final count = state.selectionChangeDay == todayKey
        ? state.selectionChangesToday + 1
        : 1;
    state = state.copyWith(
        selectionChangeDay: todayKey, selectionChangesToday: count);
    await _persistSelectionChange(todayKey, count);
  }

  void _resetSelectionChange(int todayKey) {
    state = state.copyWith(
      selectionChangeDay: todayKey,
      selectionChangesToday: 0,
      dailySwapAddedId: null,
      dailySwapRemovedId: null,
      selectionChangePending: false,
    );
    unawaited(_persistSelectionChange(todayKey, 0));
  }

  Future<void> _persistSelectionChange(int dayKey, int count) async {
    if (!mounted) return;
    final userId = state.user?.id;
    if (userId == null) return;
    try {
      final cache = await _services.selectionChangeCache;
      await cache.write(
          userId, SelectionChangeState(dayKey: dayKey, changesToday: count));
    } catch (_) {
      // Ignore cache failures.
    }
    await _persistUserStateToServer(
      selectionChangeDay: dayKey,
      selectionChangesToday: count,
    );
  }

  Future<void> _restoreSession() async {
    if (state.isSignedIn) return;
    if (AppConfig.e2eTestMode) {
      if (!AppConfig.webAutoSignIn) {
        return;
      }
      _setLoading(true);
      try {
        await _bootstrapE2EUserSession();
      } catch (_) {
        // Ignore e2e session restore failures.
      }
      _setLoading(false);
      return;
    }
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

  Future<void> _bootstrapE2EUserSession() async {
    final now = _now();
    final channels = _e2eChannels();
    state = state.copyWith(
      user: User(
        id: _e2eUserId,
        email: _e2eUserEmail,
        plan: const Plan(tier: PlanTier.free),
        createdAt: now,
      ),
      youtubeConnected: true,
      selectionCompleted: false,
      channels: List.unmodifiable(channels),
      selectedChannelIds: const <String>{},
      videos: const <Video>[],
      transcripts: const <String, TranscriptResult>{},
      transcriptLoading: const <String>{},
      transcriptQueued: const <String>{},
    );
    final remoteState = await _fetchRemoteUserState(_e2eUserId);
    await Future.wait([
      _syncUserProfile(),
      _loadVideoHistoryState(remoteState: remoteState),
      _loadSelectionChangeState(remoteState: remoteState),
      _loadArchivesFromServer(),
    ]);
    await _loadSelectionFromServer();
    if (state.selectionCompleted) {
      await _loadSelectedVideos();
    }
  }

  List<Channel> _e2eChannels() {
    return <Channel>[
      Channel(
        id: 'e2echannel01',
        youtubeChannelId: 'e2echannel01',
        title: 'E2E 채널 1',
        thumbnailUrl: '',
      ),
      Channel(
        id: 'e2echannel02',
        youtubeChannelId: 'e2echannel02',
        title: 'E2E 채널 2',
        thumbnailUrl: '',
      ),
      Channel(
        id: 'e2echannel03',
        youtubeChannelId: 'e2echannel03',
        title: 'E2E 채널 3',
        thumbnailUrl: '',
      ),
      Channel(
        id: 'e2echannel04',
        youtubeChannelId: 'e2echannel04',
        title: 'E2E 채널 4',
        thumbnailUrl: '',
      ),
    ];
  }

  List<Video> _e2eVideos(Set<String> selectedChannelIds) {
    final channelsById = {
      for (final channel in state.channels) channel.id: channel
    };
    final now = _now();
    final sortedChannelIds = selectedChannelIds.toList()..sort();
    final videos = <Video>[];
    var rank = 0;
    for (final channelId in sortedChannelIds) {
      final channelTitle = channelsById[channelId]?.title ?? channelId;
      for (var index = 0; index < 2; index += 1) {
        final offsetHours = rank * 3 + index;
        final publishedAt = now.subtract(Duration(hours: offsetHours));
        final videoId = 'e2evideo_${channelId}_${index + 1}';
        videos.add(
          Video(
            id: videoId,
            youtubeId: videoId,
            channelId: channelId,
            title: '$channelTitle 요약 영상 ${index + 1}',
            publishedAt: publishedAt,
            thumbnailUrl: '',
          ),
        );
      }
      rank += 1;
    }
    videos.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return videos;
  }

  Future<void> _primeGoogleSignInForWeb() async {
    try {
      await _googleSignIn.isSignedIn();
    } catch (_) {
      // Ignore initialization failures; user-triggered login still works.
    }
  }

  void _handleAccountChange(GoogleSignInAccount? account) {
    if (account == null) return;
    if (_authSession.matchesAccountId(account.id) &&
        _authSession.hasAuthHeaders) {
      unawaited(
        _authSession.refreshBackendToken(
          account: account,
          expectedAccountId: account.id,
          expectedAuthRevision: _authSession.revision,
        ),
      );
      return;
    }
    // On web, requesting extra OAuth scopes from this async callback can be
    // blocked as a popup by browsers. Ask scopes from explicit user actions
    // (e.g., refresh button) instead.
    final allowInteractiveScopes = !_isRestoringSession && !kIsWeb;
    unawaited(
      _processSignedInAccount(
        account,
        allowInteractive: allowInteractiveScopes,
      ),
    );
  }

  Future<void> _processSignedInAccount(
    GoogleSignInAccount account, {
    bool showErrors = true,
    bool allowInteractive = false,
  }) async {
    final authRevision = _authSession.beginFlow();
    _setLoading(true);
    try {
      final headers = await account.authHeaders.timeout(_authHeadersTimeout);
      if (!_isAuthFlowCurrent(authRevision)) {
        return;
      }
      _authSession.setAccount(account);
      _authSession.setAuthHeaders(headers);
      await _authSession.refreshBackendToken(
        account: account,
        expectedAccountId: account.id,
        expectedAuthRevision: authRevision,
      );
      if (!_isAuthFlowCurrent(authRevision)) {
        return;
      }
      state = state.copyWith(
        user: User(
          id: account.id,
          email: account.email,
          plan: const Plan(tier: PlanTier.free),
          createdAt: _now(),
        ),
      );
      final remoteState = await _fetchRemoteUserState(account.id);
      if (!_isAuthFlowCurrent(authRevision)) {
        return;
      }
      await Future.wait([
        _syncUserProfile(),
        _loadVideoHistoryState(remoteState: remoteState),
      ]);
      if (!_isAuthFlowCurrent(authRevision)) {
        return;
      }
      try {
        await Future.wait([
          _connectAndSyncYouTube(
            allowInteractive: allowInteractive,
            remoteState: remoteState,
          ),
          _loadArchivesFromServer(),
        ]).timeout(_initialSyncTimeout);
      } on TimeoutException {
        if (showErrors && _isAuthFlowCurrent(authRevision)) {
          _setToast('동기화 시간이 초과되었습니다. 새로고침 후 다시 시도해주세요.');
        }
      } catch (error) {
        if (showErrors && _isAuthFlowCurrent(authRevision)) {
          _setToast(kDebugMode
              ? 'YouTube 동기화 실패: $error'
              : 'YouTube 구독 채널을 불러오지 못했습니다.');
        }
      }
    } on TimeoutException {
      if (showErrors && _isAuthFlowCurrent(authRevision)) {
        _setToast(
          'Google 인증 토큰을 가져오지 못했습니다. '
          '다시 로그인하거나 새로고침 후 재시도해주세요.',
        );
      }
    } catch (error) {
      if (showErrors && _isAuthFlowCurrent(authRevision)) {
        _setToast(kDebugMode
            ? 'Google 로그인 실패: $error'
            : 'Google 로그인에 실패했습니다. 다시 시도해주세요.');
      }
    } finally {
      if (_isAuthFlowCurrent(authRevision)) {
        _setLoading(false);
      }
    }
  }

  Future<UserStatePayload?> _fetchRemoteUserState(String userId) async {
    try {
      return await _services.userStateService.fetchState(userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _connectAndSyncYouTube({
    bool allowInteractive = false,
    UserStatePayload? remoteState,
  }) async {
    if (_authSession.account == null) {
      throw Exception('로그인이 필요합니다.');
    }
    state = state.copyWith(selectionCompleted: false);
    try {
      await _loadSelectionChangeState(remoteState: remoteState);
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
    final channels = await _channelSync.fetchChannels(
      allowInteractive: allowInteractive,
      ensureYouTubeAccess: _ensureYouTubeAccess,
      currentAuthHeaders: _currentAuthHeaders,
    );
    final normalized = _channelSync.normalizeSelection(
      channels: channels,
      selectedChannelIds: state.selectedChannelIds,
      channelLimit: state.channelLimit,
    );
    state = state.copyWith(
      channels: List.unmodifiable(channels),
      selectedChannelIds: Set.unmodifiable(normalized),
    );
  }

  Future<void> _loadSelectionFromServer() async {
    final userId = state.user?.id;
    if (userId == null) return;
    final selected = await _channelSync.fetchSelection(userId);
    if (selected == null) return;
    if (selected.isEmpty) {
      state = state.copyWith(
        selectedChannelIds: const <String>{},
        selectionCompleted: false,
      );
      return;
    }
    final filtered = _channelSync.filterServerSelection(
      selected: selected,
      channels: state.channels,
      channelLimit: state.channelLimit,
    );
    if (filtered.isEmpty) {
      state = state.copyWith(
        selectedChannelIds: const <String>{},
        selectionCompleted: false,
      );
      return;
    }
    state = state.copyWith(
      selectedChannelIds: Set.unmodifiable(filtered),
      selectionCompleted: true,
    );
    _loadSelectedVideosSilently();
  }

  Future<bool> _persistSelectionToServer() async {
    final userId = state.user?.id;
    if (userId == null) return false;
    return _channelSync.saveSelection(
      userId: userId,
      channels: state.channels,
      selectedIds: state.selectedChannelIds,
    );
  }

  Future<bool> _persistUserStateToServer({
    int? selectionChangeDay,
    int? selectionChangesToday,
    Set<String>? openedVideoIds,
  }) async {
    if (!mounted) return false;
    final userId = state.user?.id;
    if (userId == null) return false;
    return _services.userStateService.saveState(
      userId: userId,
      selectionChangeDay: selectionChangeDay ?? state.selectionChangeDay,
      selectionChangesToday:
          selectionChangesToday ?? state.selectionChangesToday,
      openedVideoIds:
          (openedVideoIds ?? state.openedVideoIds).toList(growable: false),
    );
  }

  Future<void> _loadSelectedVideos({bool allowInteractive = false}) async {
    if (state.selectedChannelIds.isEmpty) return;
    if (AppConfig.e2eTestMode) {
      final videos = _e2eVideos(state.selectedChannelIds);
      state = state.copyWith(
        videos: List.unmodifiable(videos),
        transcripts: const <String, TranscriptResult>{},
        transcriptLoading: const <String>{},
        transcriptQueued: const <String>{},
      );
      _transcriptQueueController.reset();
      return;
    }
    final videos = await _channelSync.fetchLatestVideos(
      selectedChannelIds: state.selectedChannelIds.toList(),
      allowInteractive: allowInteractive,
      ensureYouTubeAccess: _ensureYouTubeAccess,
      currentAuthHeaders: _currentAuthHeaders,
    );
    state = state.copyWith(
      videos: List.unmodifiable(videos),
      transcripts: const <String, TranscriptResult>{},
      transcriptLoading: const <String>{},
      transcriptQueued: const <String>{},
    );
    _transcriptQueueController.reset();
  }

  void _loadSelectedVideosSilently() {
    if (_authSession.account == null || state.selectedChannelIds.isEmpty) {
      return;
    }
    unawaited(_loadSelectedVideos().catchError((_) {
      // Ignore background refresh failures.
    }));
  }

  Future<void> _ensureYouTubeAccess({
    required bool allowInteractive,
    bool forceRefresh = false,
  }) async {
    final account = _authSession.account;
    if (account == null) {
      throw Exception('로그인이 필요합니다.');
    }
    if (kIsWeb) {
      bool canAccess = false;
      if (!forceRefresh) {
        try {
          canAccess = await _googleSignIn
              .canAccessScopes(_youtubeScopes)
              .timeout(_scopeCheckTimeout);
        } catch (_) {
          canAccess = false;
        }
      }
      if (!canAccess) {
        if (!allowInteractive) {
          throw Exception('YouTube 권한이 필요합니다.');
        }
        bool granted;
        try {
          granted = await _googleSignIn
              .requestScopes(_youtubeScopes)
              .timeout(_scopeRequestTimeout);
        } on TimeoutException {
          throw Exception(
            'YouTube 권한 승인 대기 시간이 초과되었습니다. '
            '브라우저 팝업 차단을 해제하고 다시 시도해주세요.',
          );
        } catch (error) {
          final raw = error.toString().toLowerCase();
          if (raw.contains('popup_failed_to_open') ||
              (raw.contains('popup') && raw.contains('block'))) {
            throw Exception(
              '브라우저가 권한 팝업을 차단했습니다. '
              '팝업 허용 후 다시 시도해주세요.',
            );
          }
          throw Exception('YouTube 권한 요청에 실패했습니다. 다시 시도해주세요.');
        }
        if (!granted) {
          throw Exception('YouTube 권한이 필요합니다.');
        }
      }
    }
    try {
      final headers = await account.authHeaders.timeout(_authHeadersTimeout);
      if (!_isCurrentAccountId(account.id)) {
        throw Exception('로그인 상태가 변경되었습니다. 다시 시도해주세요.');
      }
      _authSession.setAuthHeaders(headers);
    } on TimeoutException {
      throw Exception(
        'Google 인증 토큰을 가져오지 못했습니다. '
        '다시 로그인하거나 새로고침 후 재시도해주세요.',
      );
    }
    await _authSession.refreshBackendToken(
      account: account,
      expectedAccountId: account.id,
    );
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
    if (_transcriptQueueController.containsVideoId(video.id)) {
      return;
    }

    final enqueued = _transcriptQueueController.enqueue(video);
    if (!enqueued) {
      return;
    }
    final queued = Set<String>.from(state.transcriptQueued)..add(video.id);
    state = state.copyWith(transcriptQueued: Set.unmodifiable(queued));
    unawaited(
      _transcriptQueueController.processQueue(
        runTask: _fetchTranscriptFor,
        onError: _handleTranscriptFailure,
      ),
    );
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
