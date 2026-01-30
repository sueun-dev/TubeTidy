import 'package:flutter/cupertino.dart';

class AppColors {
  static const Color brand = Color(0xFF0F766E);
  static const Color brandDark = Color(0xFF0B5B56);
  static const Color accent = Color(0xFFF2B544);
  static const Color accentSoft = Color(0xFFFFF3D9);

  static const Color background = Color(0xFFF7F4EE);
  static const Color card = Color(0xFFFFFFFF);
  static const Color elevatedCard = Color(0xFFFFFBF4);

  static const Color textPrimary = Color(0xFF1C1C1C);
  static const Color textSecondary = Color(0xFF4B4B4B);
  static const Color divider = Color(0xFFD9D1C6);

  static const Color success = Color(0xFF1F8A5A);
  static const Color danger = Color(0xFFD64545);

  static const Color shadow = Color(0x1A000000);
  static const Color hairline = Color(0x11000000);
}

class AppGradients {
  static const LinearGradient hero = LinearGradient(
    colors: [Color(0xFFF5F9F7), Color(0xFFFFF5E6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient card = LinearGradient(
    colors: [Color(0x140F766E), Color(0x00F2B544)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.shadow,
      blurRadius: 18,
      offset: Offset(0, 10),
    ),
  ];
}

CupertinoThemeData buildCupertinoTheme() {
  return const CupertinoThemeData(
    primaryColor: AppColors.brand,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    barBackgroundColor: AppColors.background,
    textTheme: CupertinoTextThemeData(
      navTitleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      navLargeTitleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      textStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
      ),
    ),
  );
}
