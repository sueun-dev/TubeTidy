import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_strings.dart';
import '../models/plan.dart';
import '../state/app_controller.dart';
import '../state/ui_providers.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/channel_tile.dart';

class ChannelSelectionScreen extends ConsumerWidget {
  const ChannelSelectionScreen({super.key});

  static const int _pageSize = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);
    final searchQuery = ref.watch(channelSearchQueryProvider);
    final pageIndex = ref.watch(channelPageProvider);
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final filteredChannels = appState.channels.where((channel) {
      if (normalizedQuery.isEmpty) return true;
      return channel.title.toLowerCase().contains(normalizedQuery);
    }).toList();
    final totalPages = filteredChannels.isEmpty
        ? 1
        : ((filteredChannels.length - 1) ~/ _pageSize) + 1;
    final safePageIndex = pageIndex.clamp(0, totalPages - 1);
    if (pageIndex != safePageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(channelPageProvider.notifier).state = safePageIndex;
      });
    }
    final pageStart = safePageIndex * _pageSize;
    final pageChannels =
        filteredChannels.skip(pageStart).take(_pageSize).toList();

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: LiquidGradients.canvas),
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(strings.channelSelectionTitle),
                backgroundColor: const Color(0x00000000),
                border: null,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: _PlanOverviewCard(
                    strings: strings,
                    plan: appState.plan,
                    selectedCount: appState.selectedCount,
                    channelLimit: appState.channelLimit,
                    onUpgrade: () => context.push('/plan'),
                  ),
                ),
              ),
              if (appState.channelLimit > 0 &&
                  appState.selectedCount >= appState.channelLimit)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _LimitHintBanner(label: strings.limitBanner),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.soft,
                    padding: const EdgeInsets.all(14),
                    borderRadius: BorderRadius.circular(LiquidRadius.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CupertinoSearchTextField(
                          placeholder: strings.searchPlaceholder,
                          onChanged: (value) {
                            ref
                                .read(channelSearchQueryProvider.notifier)
                                .state = value;
                            ref.read(channelPageProvider.notifier).state = 0;
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          strings.totalCount(filteredChannels.length),
                          style: LiquidTextStyles.caption1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (appState.channels.isNotEmpty && pageChannels.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GlassSurface(
                      settings: LiquidGlassPresets.panel,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      borderRadius: BorderRadius.circular(LiquidRadius.lg),
                      child: Column(
                        children: pageChannels.map((channel) {
                          final isSelected =
                              appState.selectedChannelIds.contains(channel.id);
                          final isDisabled =
                              !isSelected && !controller.canSelectMore();

                          return ChannelTile(
                            key: ValueKey(channel.id),
                            channel: channel,
                            isSelected: isSelected,
                            isDisabled: isDisabled,
                            strings: strings,
                            onChanged: (_) =>
                                controller.toggleChannel(channel.id),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                )
              else if (appState.channels.isNotEmpty && !appState.isLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: GlassSurfaceSoft(
                      padding: const EdgeInsets.all(20),
                      borderRadius: BorderRadius.circular(LiquidRadius.lg),
                      child: Column(
                        children: [
                          const Icon(
                            CupertinoIcons.search,
                            size: 32,
                            color: LiquidColors.textTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            strings.noSearchResults,
                            style: LiquidTextStyles.subheadline,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: GlassSurface(
                      settings: LiquidGlassPresets.panel,
                      padding: const EdgeInsets.all(20),
                      borderRadius: BorderRadius.circular(LiquidRadius.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            appState.isLoading
                                ? CupertinoIcons.arrow_2_circlepath
                                : CupertinoIcons.person_2,
                            size: 36,
                            color: LiquidColors.textTertiary,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            appState.isLoading
                                ? strings.loadingSubscriptions
                                : strings.noSubscriptions,
                            style: LiquidTextStyles.headline,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            appState.isLoading
                                ? strings.syncingMessage
                                : strings.failedSubscriptions,
                            style: LiquidTextStyles.caption1,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          if (appState.isLoading)
                            const CupertinoActivityIndicator()
                          else
                            LiquidGlassButton(
                              onPressed: controller.refreshSubscriptions,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    CupertinoIcons.arrow_clockwise,
                                    size: 14,
                                    color: LiquidColors.brand,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    strings.reload,
                                    style: LiquidTextStyles.footnote.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: LiquidColors.brand,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (appState.channels.isNotEmpty && filteredChannels.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LiquidGlassButton(
                          padding: const EdgeInsets.all(10),
                          onPressed: safePageIndex > 0
                              ? () => ref
                                  .read(channelPageProvider.notifier)
                                  .state = safePageIndex - 1
                              : null,
                          child: Icon(
                            CupertinoIcons.chevron_left,
                            size: 16,
                            color: safePageIndex > 0
                                ? LiquidColors.brand
                                : LiquidColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        GlassSurfaceThin(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          borderRadius: BorderRadius.circular(LiquidRadius.sm),
                          child: Text(
                            '${safePageIndex + 1} / $totalPages',
                            style: LiquidTextStyles.footnote,
                          ),
                        ),
                        const SizedBox(width: 16),
                        LiquidGlassButton(
                          padding: const EdgeInsets.all(10),
                          onPressed: safePageIndex < totalPages - 1
                              ? () => ref
                                  .read(channelPageProvider.notifier)
                                  .state = safePageIndex + 1
                              : null,
                          child: Icon(
                            CupertinoIcons.chevron_right,
                            size: 16,
                            color: safePageIndex < totalPages - 1
                                ? LiquidColors.brand
                                : LiquidColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      key: const ValueKey('selection-complete-button'),
                      borderRadius: BorderRadius.circular(LiquidRadius.sm),
                      onPressed: appState.isLoading || !appState.hasSelection
                          ? null
                          : () async {
                              final completed =
                                  await controller.finalizeChannelSelection();
                              if (completed && context.mounted) {
                                context.go('/app');
                              }
                            },
                      child: appState.isLoading
                          ? const CupertinoActivityIndicator(
                              color: CupertinoColors.white)
                          : Text(strings.selectionComplete),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  child: Text(
                    strings.selectionFooter(appState.selectionCompleted),
                    style: LiquidTextStyles.caption1,
                    textAlign: TextAlign.center,
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

class _PlanOverviewCard extends StatelessWidget {
  const _PlanOverviewCard({
    required this.strings,
    required this.plan,
    required this.selectedCount,
    required this.channelLimit,
    required this.onUpgrade,
  });

  final AppStrings strings;
  final Plan plan;
  final int selectedCount;
  final int channelLimit;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final limit = channelLimit;
    final limitLabel = limit <= 0
        ? strings.channelCountLabel(0)
        : strings.channelCountLabel(limit);
    final progress = limit <= 0 ? 0.0 : (selectedCount / limit).clamp(0.0, 1.0);
    final planName = strings.planName(plan.tier);
    final planPrice = strings.planPriceLabel(plan.tier);

    return GlassSurface(
      settings: LiquidGlassPresets.panel,
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(LiquidRadius.xl),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: progress),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
        builder: (context, animatedProgress, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          planName,
                          style: LiquidTextStyles.title2,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          planPrice,
                          style: LiquidTextStyles.subheadline,
                        ),
                      ],
                    ),
                  ),
                  LiquidGlassButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    onPressed: onUpgrade,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.arrow_up_circle,
                          size: 14,
                          color: LiquidColors.brand,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          strings.upgradeLabel,
                          style: LiquidTextStyles.footnote.copyWith(
                            fontWeight: FontWeight.w600,
                            color: LiquidColors.brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.selectedCountLabel(selectedCount, limitLabel),
                      style: LiquidTextStyles.caption1,
                    ),
                  ),
                  Text(
                    '${(animatedProgress * 100).round()}%',
                    style: LiquidTextStyles.footnote.copyWith(
                      fontWeight: FontWeight.w600,
                      color: LiquidColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ProgressBar(progress: animatedProgress),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * progress;
        return Stack(
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: LiquidColors.glassDark,
                borderRadius: BorderRadius.circular(LiquidRadius.pill),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              height: 8,
              width: width,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    LiquidColors.brand,
                    LiquidColors.brandLight,
                  ],
                ),
                borderRadius: BorderRadius.circular(LiquidRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: LiquidColors.brand.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LimitHintBanner extends StatelessWidget {
  const _LimitHintBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassSurfaceThin(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: BorderRadius.circular(LiquidRadius.md),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle_fill,
            size: 16,
            color: LiquidColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: LiquidTextStyles.caption1,
            ),
          ),
        ],
      ),
    );
  }
}
