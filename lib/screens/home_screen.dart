import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_strings.dart';
import '../models/channel.dart';
import '../state/app_controller.dart';
import '../state/ui_providers.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/summary_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final selectedIds = appState.selectedChannelIds;
    final filterChannelId = ref.watch(homeFilterProvider);
    final strings = ref.watch(appStringsProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final channelById = {
      for (final channel in appState.channels) channel.id: channel,
    };

    if (filterChannelId != allChannelsFilter &&
        !selectedIds.contains(filterChannelId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(homeFilterProvider.notifier).state = allChannelsFilter;
      });
    }

    final visibleVideos = appState.videos
        .where((video) =>
            filterChannelId == allChannelsFilter ||
            video.channelId == filterChannelId)
        .toList();
    final archivedIds = {for (final e in appState.archives) e.videoId};

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: LiquidGradients.canvas),
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(strings.homeTitle),
                backgroundColor: const Color(0x00000000),
                border: null,
              ),
              CupertinoSliverRefreshControl(
                onRefresh: controller.refreshHome,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: _OverviewCard(
                    strings: strings,
                    planName: strings.planName(appState.plan.tier),
                    planPrice: strings.planPriceLabel(appState.plan.tier),
                    selectedChannels: appState.selectedCount,
                    totalSummaries: visibleVideos.length,
                    savedCount: appState.archives.length,
                    channelLimitLabel:
                        strings.channelCountLabel(appState.channelLimit),
                  ),
                ),
              ),
              if (appState.selectionCompleted &&
                  appState.isSelectionCooldownActive)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _CooldownBanner(
                      strings: strings,
                      nextChangeAt: appState.nextSelectionChangeAt,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: _ChannelFilter(
                    strings: strings,
                    channels: appState.channels
                        .where((channel) => selectedIds.contains(channel.id))
                        .toList(),
                    selectedChannelId: filterChannelId,
                    onChanged: (value) =>
                        ref.read(homeFilterProvider.notifier).state = value,
                  ),
                ),
              ),
              if (visibleVideos.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    label: strings.emptySummaries,
                    isLoading: appState.isLoading,
                    primaryActionLabel: strings.reload,
                    onPrimaryAction: controller.refreshHome,
                    secondaryActionLabel: strings.manageChannels,
                    onSecondaryAction: () => context.push('/channels'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = visibleVideos[index];
                        final transcript = appState.transcripts[video.id];
                        final isTranscriptLoading =
                            appState.transcriptLoading.contains(video.id);
                        final isQueued =
                            appState.transcriptQueued.contains(video.id);
                        final channel = channelById[video.channelId] ??
                            Channel(
                              id: video.channelId,
                              youtubeChannelId: '',
                              title: strings.unknownChannel,
                              thumbnailUrl: '',
                            );

                        return Padding(
                          key: ValueKey('summary-${video.id}'),
                          padding: const EdgeInsets.only(bottom: 18),
                          child: SummaryCard(
                            video: video,
                            channel: channel,
                            transcript: transcript,
                            isTranscriptLoading: isTranscriptLoading,
                            isQueued: isQueued,
                            strings: strings,
                            onWatchVideo: () {
                              unawaited(() async {
                                ref
                                    .read(appControllerProvider.notifier)
                                    .recordVideoInteraction(video.youtubeId);
                                final uri = Uri.parse(
                                    'https://www.youtube.com/watch?v=${video.youtubeId}');
                                await launchUrl(
                                  uri,
                                  mode: kIsWeb
                                      ? LaunchMode.platformDefault
                                      : LaunchMode.externalApplication,
                                );
                              }());
                            },
                            isArchived: archivedIds.contains(video.id),
                            onToggleArchive: () => ref
                                .read(appControllerProvider.notifier)
                                .toggleArchive(video.id),
                            onRequestSummary: () => ref
                                .read(appControllerProvider.notifier)
                                .requestSummaryFor(video),
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
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.strings,
    required this.planName,
    required this.planPrice,
    required this.selectedChannels,
    required this.totalSummaries,
    required this.savedCount,
    required this.channelLimitLabel,
  });

  final AppStrings strings;
  final String planName;
  final String planPrice;
  final int selectedChannels;
  final int totalSummaries;
  final int savedCount;
  final String channelLimitLabel;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      settings: LiquidGlassPresets.panel,
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(LiquidRadius.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassMetaChip(
                label: '$planName  $planPrice',
                color: LiquidColors.brand,
              ),
              const Spacer(),
              Text(
                strings.selectedChannelsLabel(
                    selectedChannels, channelLimitLabel),
                style: LiquidTextStyles.caption1,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            strings.todaySummary,
            style: LiquidTextStyles.title3,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill(
                icon: CupertinoIcons.doc_text,
                label: strings.summaryLabel,
                value: totalSummaries,
              ),
              const SizedBox(width: 10),
              _StatPill(
                icon: CupertinoIcons.star,
                label: strings.savedLabel,
                value: savedCount,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return GlassSurfaceSoft(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: BorderRadius.circular(LiquidRadius.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LiquidColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: LiquidTextStyles.caption1),
          const SizedBox(width: 6),
          Text(
            value.toString(),
            style: LiquidTextStyles.footnote.copyWith(
              fontWeight: FontWeight.w600,
              color: LiquidColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelFilter extends StatelessWidget {
  const _ChannelFilter({
    required this.strings,
    required this.channels,
    required this.selectedChannelId,
    required this.onChanged,
  });

  final AppStrings strings;
  final List<Channel> channels;
  final String selectedChannelId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      settings: LiquidGlassPresets.soft,
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(LiquidRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            strings.channelFilter,
            style: LiquidTextStyles.headline,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _FilterChip(
                label: strings.all,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? LiquidColors.brand : LiquidColors.glassMid,
          borderRadius: BorderRadius.circular(LiquidRadius.pill),
          border: Border.all(
            color: isSelected ? LiquidColors.brand : LiquidColors.glassStroke,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected
                ? LiquidColors.textInverse
                : LiquidColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.label,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.isLoading = false,
  });

  final String label;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassSurface(
        settings: LiquidGlassPresets.soft,
        padding: const EdgeInsets.all(32),
        borderRadius: BorderRadius.circular(LiquidRadius.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.play_rectangle,
              size: 48,
              color: LiquidColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: LiquidTextStyles.subheadline,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const CupertinoActivityIndicator()
            else ...[
              if (primaryActionLabel != null && onPrimaryAction != null)
                LiquidGlassButton(
                  onPressed: onPrimaryAction!,
                  child: Text(
                    primaryActionLabel!,
                    style: LiquidTextStyles.footnote.copyWith(
                      fontWeight: FontWeight.w600,
                      color: LiquidColors.brand,
                    ),
                  ),
                ),
              if (secondaryActionLabel != null && onSecondaryAction != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onSecondaryAction,
                    child: Text(
                      secondaryActionLabel!,
                      style: LiquidTextStyles.footnote.copyWith(
                        color: LiquidColors.brand,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CooldownBanner extends StatelessWidget {
  const _CooldownBanner({required this.strings, required this.nextChangeAt});

  final AppStrings strings;
  final DateTime nextChangeAt;

  @override
  Widget build(BuildContext context) {
    return GlassSurfaceThin(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: BorderRadius.circular(LiquidRadius.md),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.timer,
            size: 16,
            color: LiquidColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              strings.cooldownLabel(nextChangeAt),
              style: LiquidTextStyles.caption1,
            ),
          ),
        ],
      ),
    );
  }
}
