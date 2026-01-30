import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/channel.dart';
import '../models/video.dart';
import '../state/app_state.dart';
import '../state/ui_state.dart';
import '../theme.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final channelIds = appState.selectedChannelIds;

    final focusedMonth = ref.watch(calendarFocusedMonthProvider);
    final selectedDay = ref.watch(calendarSelectedDayProvider);
    final filterChannelId = ref.watch(calendarFilterProvider);

    if (filterChannelId != allChannelsFilter && !channelIds.contains(filterChannelId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(calendarFilterProvider.notifier).state = allChannelsFilter;
      });
    }

    final archiveMap = _filteredArchives(appState, filterChannelId);
    final selectedKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final selectedVideos = archiveMap[selectedKey] ?? [];
    final monthSaved = archiveMap.entries
        .where((entry) => entry.key.year == focusedMonth.year && entry.key.month == focusedMonth.month)
        .fold<int>(0, (sum, entry) => sum + entry.value.length);

    return CupertinoPageScaffold(
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('캘린더'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: _MonthHeader(
                  focusedMonth: focusedMonth,
                  onPrevious: () => ref.read(calendarFocusedMonthProvider.notifier).state =
                      DateTime(focusedMonth.year, focusedMonth.month - 1, 1),
                  onNext: () => ref.read(calendarFocusedMonthProvider.notifier).state =
                      DateTime(focusedMonth.year, focusedMonth.month + 1, 1),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    _StatChip(label: '이번 달 저장', value: monthSaved),
                    const SizedBox(width: 8),
                    _StatChip(label: '전체 저장', value: appState.archives.length),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _ChannelFilter(
                  channels: appState.channels
                      .where((channel) => channelIds.contains(channel.id))
                      .toList(),
                  selectedChannelId: filterChannelId,
                  onChanged: (value) => ref.read(calendarFilterProvider.notifier).state = value,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _CalendarGrid(
                  month: focusedMonth,
                  selectedDay: selectedDay,
                  archives: archiveMap,
                  onSelectDay: (day) =>
                      ref.read(calendarSelectedDayProvider.notifier).state = day,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    DateFormat('MM월 dd일').format(selectedDay),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            if (selectedVideos.isEmpty)
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
                      final video = selectedVideos[index];
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
                        key: ValueKey('calendar-${video.id}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                            boxShadow: AppShadows.card,
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  video.thumbnailUrl,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 64,
                                    height: 64,
                                    color: AppColors.elevatedCard,
                                    alignment: Alignment.center,
                                    child: const Icon(CupertinoIcons.photo, color: AppColors.textSecondary),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      video.title,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      channel.title,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
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
    );
  }

  Map<DateTime, List<Video>> _filteredArchives(AppStateData state, String filterChannelId) {
    final Map<DateTime, List<Video>> result = {};

    for (final entry in state.archives) {
      final day = DateTime(entry.archivedAt.year, entry.archivedAt.month, entry.archivedAt.day);
      final videoIndex = state.videos.indexWhere((video) => video.id == entry.videoId);
      if (videoIndex == -1) continue;
      final video = state.videos[videoIndex];
      if (filterChannelId != allChannelsFilter && video.channelId != filterChannelId) {
        continue;
      }

      result.putIfAbsent(day, () => []).add(video);
    }

    return result;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.focusedMonth,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime focusedMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onPrevious,
            child: const Icon(CupertinoIcons.chevron_left, color: AppColors.textSecondary),
          ),
          Expanded(
            child: Text(
              DateFormat('yyyy년 MM월').format(focusedMonth),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onNext,
            child: const Icon(CupertinoIcons.chevron_right, color: AppColors.textSecondary),
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
  });

  final List<Channel> channels;
  final String selectedChannelId;
  final ValueChanged<String> onChanged;

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
          const Text(
            '채널 필터',
            style: TextStyle(fontWeight: FontWeight.w600),
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

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.selectedDay,
    required this.archives,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime selectedDay;
  final Map<DateTime, List<Video>> archives;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final days = _generateCalendarDays(month);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _WeekdayLabel('월'),
              _WeekdayLabel('화'),
              _WeekdayLabel('수'),
              _WeekdayLabel('목'),
              _WeekdayLabel('금'),
              _WeekdayLabel('토'),
              _WeekdayLabel('일'),
            ],
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
              final hasArchive = archives.containsKey(DateTime(day.year, day.month, day.day));

              return GestureDetector(
                onTap: () => onSelectDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brand : AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.hairline),
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
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                          ),
                        ),
                        if (hasArchive)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
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
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
          Icon(CupertinoIcons.star, size: 44, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text(
            '저장된 요약이 아직 없어요.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
