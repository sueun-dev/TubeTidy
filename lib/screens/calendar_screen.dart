import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../localization/app_strings.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../state/app_controller.dart';
import '../state/ui_providers.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final channelIds = appState.selectedChannelIds;
    final channelById = {
      for (final channel in appState.channels) channel.id: channel,
    };

    final focusedMonth = ref.watch(calendarFocusedMonthProvider);
    final selectedDay = ref.watch(calendarSelectedDayProvider);
    final filterChannelId = ref.watch(calendarFilterProvider);
    final strings = ref.watch(appStringsProvider);

    if (filterChannelId != allChannelsFilter &&
        !channelIds.contains(filterChannelId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(calendarFilterProvider.notifier).state = allChannelsFilter;
      });
    }

    final archiveMap = _filteredArchives(
      appState,
      filterChannelId,
      useArchives: true,
    );
    final selectedKey =
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final selectedVideos = archiveMap[selectedKey] ?? [];
    final monthSaved = archiveMap.entries
        .where((entry) =>
            entry.key.year == focusedMonth.year &&
            entry.key.month == focusedMonth.month)
        .fold<int>(0, (sum, entry) => sum + entry.value.length);
    final totalItems = appState.archives.length;

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: LiquidGradients.canvas),
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(strings.calendarTitle),
                backgroundColor: const Color(0x00000000),
                border: null,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: _MonthHeader(
                    strings: strings,
                    focusedMonth: focusedMonth,
                    onPrevious: () => ref
                            .read(calendarFocusedMonthProvider.notifier)
                            .state =
                        DateTime(focusedMonth.year, focusedMonth.month - 1, 1),
                    onNext: () => ref
                            .read(calendarFocusedMonthProvider.notifier)
                            .state =
                        DateTime(focusedMonth.year, focusedMonth.month + 1, 1),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      _StatChip(
                        label: strings.monthSavedLabel(monthSaved),
                        value: monthSaved,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        label: strings.totalSavedLabel(totalItems),
                        value: totalItems,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _ChannelFilter(
                    strings: strings,
                    channels: appState.channels
                        .where((channel) => channelIds.contains(channel.id))
                        .toList(),
                    selectedChannelId: filterChannelId,
                    onChanged: (value) =>
                        ref.read(calendarFilterProvider.notifier).state = value,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _CalendarGrid(
                    weekdayLabels: strings.weekdayLabels,
                    month: focusedMonth,
                    selectedDay: selectedDay,
                    archives: archiveMap,
                    onSelectDay: (day) => ref
                        .read(calendarSelectedDayProvider.notifier)
                        .state = day,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      strings.formatSelectedDate(selectedDay),
                      style: LiquidTextStyles.headline,
                    ),
                  ),
                ),
              ),
              if (selectedVideos.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(label: strings.emptySaved),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = selectedVideos[index];
                        final channel = channelById[video.channelId] ??
                            Channel(
                              id: video.channelId,
                              youtubeChannelId: '',
                              title: strings.unknownChannel,
                              thumbnailUrl: '',
                            );

                        return Padding(
                          key: ValueKey('calendar-${video.id}'),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassSurface(
                            settings: LiquidGlassPresets.panel,
                            padding: const EdgeInsets.all(12),
                            borderRadius:
                                BorderRadius.circular(LiquidRadius.md),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(LiquidRadius.sm),
                                  child: Image.network(
                                    video.thumbnailUrl,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 64,
                                      height: 64,
                                      color: LiquidColors.glassDark,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        CupertinoIcons.photo,
                                        color: LiquidColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        video.title,
                                        style: LiquidTextStyles.subheadline
                                            .copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        channel.title,
                                        style: LiquidTextStyles.caption1,
                                      ),
                                    ],
                                  ),
                                ),
                                Semantics(
                                  label: strings.removeFavorite,
                                  button: true,
                                  child: CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () =>
                                        controller.toggleArchive(video.id),
                                    child: const Icon(
                                      CupertinoIcons.star_fill,
                                      color: LiquidColors.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: selectedVideos.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Map<DateTime, List<Video>> _filteredArchives(
    AppStateData state,
    String filterChannelId, {
    required bool useArchives,
  }) {
    final Map<DateTime, List<Video>> result = {};

    if (useArchives) {
      final videoMap = {for (final v in state.videos) v.id: v};
      for (final entry in state.archives) {
        final video = videoMap[entry.videoId];
        if (video == null) continue;
        if (filterChannelId != allChannelsFilter &&
            video.channelId != filterChannelId) {
          continue;
        }
        final day = DateTime(entry.archivedAt.year, entry.archivedAt.month,
            entry.archivedAt.day);
        result.putIfAbsent(day, () => []).add(video);
      }
      return result;
    }

    for (final video in state.videos) {
      if (filterChannelId != allChannelsFilter &&
          video.channelId != filterChannelId) {
        continue;
      }
      final day = DateTime(video.publishedAt.year, video.publishedAt.month,
          video.publishedAt.day);
      result.putIfAbsent(day, () => []).add(video);
    }

    return result;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.strings,
    required this.focusedMonth,
    required this.onPrevious,
    required this.onNext,
  });

  final AppStrings strings;
  final DateTime focusedMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      settings: LiquidGlassPresets.soft,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(LiquidRadius.md),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onPrevious,
            child: const Icon(
              CupertinoIcons.chevron_left,
              color: LiquidColors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              strings.formatMonthYear(focusedMonth),
              textAlign: TextAlign.center,
              style: LiquidTextStyles.headline,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onNext,
            child: const Icon(
              CupertinoIcons.chevron_right,
              color: LiquidColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return GlassSurfaceThin(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: BorderRadius.circular(LiquidRadius.sm),
      child: Row(
        children: [
          Text(
            label,
            style: LiquidTextStyles.caption1,
          ),
          const SizedBox(width: 6),
          Text(
            value.toString(),
            style: LiquidTextStyles.caption1.copyWith(
              color: LiquidColors.textPrimary,
              fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(LiquidRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.calendarFilterTitle,
            style: LiquidTextStyles.headline,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: strings.all,
                isSelected: selectedChannelId == allChannelsFilter,
                onTap: () => onChanged(allChannelsFilter),
              ),
              ...channels.map(
                (channel) => _FilterChip(
                  key: ValueKey('calendar-filter-${channel.id}'),
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? LiquidColors.brand.withValues(alpha: 0.16)
              : LiquidColors.glassDark.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(LiquidRadius.sm),
          border: Border.all(
            color: isSelected ? LiquidColors.brand : LiquidColors.glassStroke,
          ),
        ),
        child: Text(
          label,
          style: LiquidTextStyles.caption1.copyWith(
            color: isSelected
                ? LiquidColors.brandDark
                : LiquidColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.weekdayLabels,
    required this.month,
    required this.selectedDay,
    required this.archives,
    required this.onSelectDay,
  });

  final List<String> weekdayLabels;
  final DateTime month;
  final DateTime selectedDay;
  final Map<DateTime, List<Video>> archives;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final days = _generateCalendarDays(month);

    return GlassSurface(
      settings: LiquidGlassPresets.panel,
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(LiquidRadius.md),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekdayLabels.map(_WeekdayLabel.new).toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final isCurrentMonth = day.month == month.month;
              final isSelected = day.year == selectedDay.year &&
                  day.month == selectedDay.month &&
                  day.day == selectedDay.day;
              final hasArchive =
                  archives.containsKey(DateTime(day.year, day.month, day.day));

              return GestureDetector(
                onTap: () => onSelectDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? LiquidColors.brand.withValues(alpha: 0.88)
                        : LiquidColors.glassUltraLight,
                    borderRadius: BorderRadius.circular(LiquidRadius.xs),
                    border: Border.all(color: LiquidColors.separatorLight),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? CupertinoColors.white
                                : isCurrentMonth
                                    ? LiquidColors.textPrimary
                                    : LiquidColors.textSecondary,
                          ),
                        ),
                        if (hasArchive)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(
                              color: LiquidColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<DateTime> _generateCalendarDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final firstWeekday = firstDay.weekday;
    final start = firstDay.subtract(Duration(days: firstWeekday - 1));
    return List.generate(42, (index) => start.add(Duration(days: index)));
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: LiquidTextStyles.caption1,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassSurfaceSoft(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(LiquidRadius.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.star,
              size: 44,
              color: LiquidColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: LiquidTextStyles.subheadline,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
