import 'package:flutter_riverpod/flutter_riverpod.dart';

const String allChannelsFilter = 'all';

final homeFilterProvider = StateProvider<String>((ref) => allChannelsFilter);

final calendarFilterProvider = StateProvider<String>((ref) => allChannelsFilter);

final calendarFocusedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final calendarSelectedDayProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});
