import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'plan_screen.dart';

class MainTabScaffold extends StatelessWidget {
  const MainTabScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        activeColor: AppColors.brand,
        inactiveColor: AppColors.textSecondary,
        backgroundColor: AppColors.background,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house_fill),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            label: '캘린더',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.creditcard_fill),
            label: '플랜',
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
              default:
                return const PlanScreen();
            }
          },
        );
      },
    );
  }
}
