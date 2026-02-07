import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_strings.dart';
import '../theme.dart';
import 'calendar_screen.dart';
import 'channel_selection_screen.dart';
import 'home_screen.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';

class MainTabScaffold extends ConsumerWidget {
  const MainTabScaffold({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        currentIndex: initialTabIndex,
        activeColor: LiquidColors.brand,
        inactiveColor: LiquidColors.textSecondary,
        backgroundColor: const Color(0xF5F7F7FB),
        border: const Border(
          top: BorderSide(
            color: LiquidColors.separatorLight,
            width: 0.7,
          ),
        ),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.house_fill),
            label: strings.tabHome,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.calendar),
            label: strings.tabCalendar,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.plus_app_fill),
            label: strings.tabChannels,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.creditcard_fill),
            label: strings.tabPlan,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.settings),
            label: strings.tabSettings,
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            switch (index) {
              case 0:
                return const HomeScreen();
              case 1:
                return const CalendarScreen();
              case 2:
                return const ChannelSelectionScreen();
              case 3:
                return const PlanScreen();
              case 4:
                return const SettingsScreen();
              default:
                return const HomeScreen();
            }
          },
        );
      },
    );
  }
}
