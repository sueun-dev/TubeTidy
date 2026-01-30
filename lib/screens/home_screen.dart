import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/channel.dart';
import '../state/app_state.dart';
import '../state/ui_state.dart';
import '../theme.dart';
import '../widgets/summary_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final selectedIds = appState.selectedChannelIds;
    final filterChannelId = ref.watch(homeFilterProvider);

    if (filterChannelId != allChannelsFilter && !selectedIds.contains(filterChannelId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(homeFilterProvider.notifier).state = allChannelsFilter;
      });
    }

    final visibleVideos = appState.videos
        .where((video) => filterChannelId == allChannelsFilter || video.channelId == filterChannelId)
        .toList();

    return CupertinoPageScaffold(
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('요약 홈'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: _OverviewCard(
                  planName: appState.plan.displayName,
                  planPrice: appState.plan.priceLabel,
                  selectedChannels: appState.selectedCount,
                  totalSummaries: visibleVideos.length,
                  savedCount: appState.archives.length,
                  channelLimitLabel: '${appState.channelLimit} 채널',
                ),
              ),
            ),
            if (appState.selectionCompleted && appState.isSelectionCooldownActive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _CooldownBanner(nextChangeAt: appState.nextSelectionChangeAt),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _ChannelFilter(
                  channels: appState.channels
                      .where((channel) => selectedIds.contains(channel.id))
                      .toList(),
                  selectedChannelId: filterChannelId,
                  onChanged: (value) => ref.read(homeFilterProvider.notifier).state = value,
                  onEdit: () => context.push('/channels'),
                ),
              ),
            ),
            if (visibleVideos.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final video = visibleVideos[index];
                      final transcript = appState.transcripts[video.id];
                      final isTranscriptLoading = appState.transcriptLoading.contains(video.id);
                      final channel = appState.channels.firstWhere(
                        (c) => c.id == video.channelId,
                        orElse: () => Channel(
                          id: video.channelId,
                          youtubeChannelId: '',
                          title: '알 수 없음',
                          thumbnailUrl: '',
                        ),
                      );

                      return Padding(
                        key: ValueKey('summary-${video.id}'),
                        padding: const EdgeInsets.only(bottom: 18),
                        child: SummaryCard(
                          video: video,
                          channel: channel,
                          transcript: transcript,
                          isTranscriptLoading: isTranscriptLoading,
                          isArchived: appState.archives.any((entry) => entry.videoId == video.id),
                          onToggleArchive: () =>
                              ref.read(appControllerProvider.notifier).toggleArchive(video.id),
                          onRequestSummary: () =>
                              ref.read(appControllerProvider.notifier).requestSummaryFor(video),
                        ),
                      );
                    },
                    childCount: visibleVideos.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.planName,
    required this.planPrice,
    required this.selectedChannels,
    required this.totalSummaries,
    required this.savedCount,
    required this.channelLimitLabel,
  });

  final String planName;
  final String planPrice;
  final int selectedChannels;
  final int totalSummaries;
  final int savedCount;
  final String channelLimitLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradients.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$planName 플랜 · $planPrice',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandDark,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '선택 채널 $selectedChannels / $channelLimitLabel',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '오늘의 기술/트렌드 요약',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatPill(label: '요약', value: totalSummaries),
              const SizedBox(width: 8),
              _StatPill(label: '별표', value: savedCount),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 6),
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ChannelFilter extends StatelessWidget {
  const _ChannelFilter({
    required this.channels,
    required this.selectedChannelId,
    required this.onChanged,
    required this.onEdit,
  });

  final List<Channel> channels;
  final String selectedChannelId;
  final ValueChanged<String> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '채널 필터',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minSize: 28,
                color: AppColors.brand,
                onPressed: onEdit,
                child: const Text(
                  '편집',
                  style: TextStyle(fontSize: 11, color: CupertinoColors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: '전체',
                isSelected: selectedChannelId == allChannelsFilter,
                onTap: () => onChanged(allChannelsFilter),
              ),
              ...channels.map(
                (channel) => _FilterChip(
                  key: ValueKey('filter-${channel.id}'),
                  label: channel.title,
                  isSelected: selectedChannelId == channel.id,
                  onTap: () => onChanged(channel.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isSelected ? AppColors.brand : AppColors.elevatedCard,
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? CupertinoColors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(CupertinoIcons.play_rectangle, size: 44, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text(
            '요약된 영상이 아직 없어요.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CooldownBanner extends StatelessWidget {
  const _CooldownBanner({required this.nextChangeAt});

  final DateTime nextChangeAt;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('M월 d일').format(nextChangeAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.timer, size: 16, color: AppColors.brandDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '채널 변경 쿨타임 · 다음 변경 가능: $label',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
