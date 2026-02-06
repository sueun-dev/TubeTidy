import 'package:flutter/cupertino.dart';

/// iOS 26 Liquid Glass Design System
/// Inspired by Apple's WWDC 2025 Liquid Glass material design language.

/// Settings for Liquid Glass effects
class LiquidGlassSettings {
  const LiquidGlassSettings({
    this.blur = 40,
    this.thickness = 0.6,
    this.refractiveIndex = 1.15,
    this.chromaticAberration = 0.02,
    this.lightIntensity = 0.8,
    this.lightAngle = -0.5,
    this.ambientStrength = 0.3,
    this.saturation = 1.1,
    this.glassColor = const Color(0xE6FFFFFF),
  });

  final double blur;
  final double thickness;
  final double refractiveIndex;
  final double chromaticAberration;
  final double lightIntensity;
  final double lightAngle;
  final double ambientStrength;
  final double saturation;
  final Color glassColor;
}

class LiquidColors {
  // Primary brand colors
  static const Color brand = Color(0xFF007AFF);
  static const Color brandLight = Color(0xFF5AC8FA);
  static const Color brandDark = Color(0xFF0051A8);

  // Accent colors
  static const Color accent = Color(0xFFFF9F0A);
  static const Color accentSoft = Color(0xFFFFF4E6);

  // Semantic colors
  static const Color success = Color(0xFF30D158);
  static const Color warning = Color(0xFFFFD60A);
  static const Color danger = Color(0xFFFF453A);

  // Background colors - subtle gradients for depth
  static const Color canvasLight = Color(0xFFF2F2F7);
  static const Color canvasMid = Color(0xFFE5E5EA);
  static const Color canvasDark = Color(0xFF1C1C1E);

  // Glass material colors
  static const Color glassLight = Color(0xE6FFFFFF);
  static const Color glassMid = Color(0xCCFFFFFF);
  static const Color glassDark = Color(0x99FFFFFF);
  static const Color glassUltraLight = Color(0xF2FFFFFF);

  // Text colors
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF6E6E73);
  static const Color textTertiary = Color(0xFF8E8E93);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Border & separator colors
  static const Color separator = Color(0x33000000);
  static const Color separatorLight = Color(0x1A000000);
  static const Color glassStroke = Color(0x66FFFFFF);
  static const Color glassHighlight = Color(0x80FFFFFF);

  // Shadow colors
  static const Color shadow = Color(0x26000000);
  static const Color shadowLight = Color(0x14000000);
}

/// Liquid Glass settings presets for different use cases
class LiquidGlassPresets {
  /// Standard glass panel - for cards and containers
  static LiquidGlassSettings get panel => const LiquidGlassSettings(
        blur: 50,
        thickness: 0.65,
        refractiveIndex: 1.17,
        chromaticAberration: 0.025,
        lightIntensity: 0.9,
        lightAngle: -0.55,
        ambientStrength: 0.34,
        saturation: 1.15,
        glassColor: Color(0xD9FFFFFF),
      );

  /// Soft glass - for subtle backgrounds
  static LiquidGlassSettings get soft => const LiquidGlassSettings(
        blur: 34,
        thickness: 0.45,
        refractiveIndex: 1.1,
        chromaticAberration: 0.015,
        lightIntensity: 0.7,
        lightAngle: -0.45,
        ambientStrength: 0.28,
        saturation: 1.08,
        glassColor: Color(0xC2FFFFFF),
      );

  /// Strong glass - for navigation bars and prominent elements
  static LiquidGlassSettings get strong => const LiquidGlassSettings(
        blur: 60,
        thickness: 0.85,
        refractiveIndex: 1.22,
        chromaticAberration: 0.035,
        lightIntensity: 0.95,
        lightAngle: -0.65,
        ambientStrength: 0.38,
        saturation: 1.2,
        glassColor: Color(0xF5FFFFFF),
      );

  /// Ultra thin glass - for overlays and sheets
  static LiquidGlassSettings get thin => const LiquidGlassSettings(
        blur: 20,
        thickness: 0.3,
        refractiveIndex: 1.05,
        chromaticAberration: 0.005,
        lightIntensity: 0.5,
        lightAngle: -0.3,
        ambientStrength: 0.2,
        saturation: 1.0,
        glassColor: Color(0x99FFFFFF),
      );

  /// Button glass - interactive elements
  static LiquidGlassSettings get button => const LiquidGlassSettings(
        blur: 42,
        thickness: 0.55,
        refractiveIndex: 1.14,
        chromaticAberration: 0.02,
        lightIntensity: 0.82,
        lightAngle: -0.5,
        ambientStrength: 0.3,
        saturation: 1.12,
        glassColor: Color(0xD9FFFFFF),
      );

  /// Navigation bar glass
  static LiquidGlassSettings get navBar => const LiquidGlassSettings(
        blur: 55,
        thickness: 0.75,
        refractiveIndex: 1.2,
        chromaticAberration: 0.03,
        lightIntensity: 0.9,
        lightAngle: -0.6,
        ambientStrength: 0.35,
        saturation: 1.15,
        glassColor: Color(0xE8F7F7FB),
      );
}

/// Canvas background gradients
class LiquidGradients {
  /// Main app background gradient
  static const LinearGradient canvas = LinearGradient(
    colors: [
      Color(0xFFF5F5FA),
      Color(0xFFEBEBF5),
      Color(0xFFE0E5F0),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.5, 1.0],
  );

  /// Vibrant canvas for feature screens
  static const LinearGradient vibrantCanvas = LinearGradient(
    colors: [
      Color(0xFFF0F4FF),
      Color(0xFFFFF5F0),
      Color(0xFFF5F0FF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle mesh gradient effect
  static const RadialGradient meshAccent = RadialGradient(
    colors: [
      Color(0x20007AFF),
      Color(0x00007AFF),
    ],
    center: Alignment.topRight,
    radius: 1.5,
  );
}

/// Box shadows for depth
class LiquidShadows {
  static const List<BoxShadow> glass = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 40,
      offset: Offset(0, 18),
      spreadRadius: -8,
    ),
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 20,
      offset: Offset(0, 10),
      spreadRadius: -6,
    ),
  ];

  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 20,
      offset: Offset(0, 10),
      spreadRadius: -5,
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x18000000),
      blurRadius: 40,
      offset: Offset(0, 20),
      spreadRadius: -8,
    ),
    BoxShadow(
      color: Color(0x0C000000),
      blurRadius: 20,
      offset: Offset(0, 10),
      spreadRadius: -5,
    ),
  ];
}

/// Text styles for Liquid Glass design
class LiquidTextStyles {
  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: LiquidColors.textPrimary,
  );

  static const TextStyle title1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: LiquidColors.textPrimary,
  );

  static const TextStyle title2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: LiquidColors.textPrimary,
  );

  static const TextStyle title3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: LiquidColors.textPrimary,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: LiquidColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: LiquidColors.textPrimary,
  );

  static const TextStyle callout = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: LiquidColors.textPrimary,
  );

  static const TextStyle subheadline = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: LiquidColors.textSecondary,
  );

  static const TextStyle footnote = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: LiquidColors.textSecondary,
  );

  static const TextStyle caption1 = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: LiquidColors.textTertiary,
  );

  static const TextStyle caption2 = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: LiquidColors.textTertiary,
  );
}

/// Border radius constants
class LiquidRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double pill = 999;
}

/// Spacing constants
class LiquidSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Cupertino theme configuration
CupertinoThemeData buildCupertinoTheme() {
  return const CupertinoThemeData(
    primaryColor: LiquidColors.brand,
    brightness: Brightness.light,
    scaffoldBackgroundColor: LiquidColors.canvasLight,
    barBackgroundColor: Color(0xE8F7F7FB),
    textTheme: CupertinoTextThemeData(
      navTitleTextStyle: TextStyle(
        color: LiquidColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      navLargeTitleTextStyle: TextStyle(
        color: LiquidColors.textPrimary,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      textStyle: TextStyle(
        color: LiquidColors.textPrimary,
        fontSize: 17,
      ),
    ),
  );
}

// Legacy color aliases for backward compatibility
class AppColors {
  static const Color brand = LiquidColors.brand;
  static const Color brandDark = LiquidColors.brandDark;
  static const Color accent = LiquidColors.accent;
  static const Color accentSoft = LiquidColors.accentSoft;
  static const Color background = LiquidColors.canvasLight;
  static const Color card = Color(0xFFFFFFFF);
  static const Color elevatedCard = LiquidColors.glassLight;
  static const Color glass = LiquidColors.glassMid;
  static const Color glassStrong = LiquidColors.glassLight;
  static const Color glassStroke = LiquidColors.glassStroke;
  static const Color glassHighlight = LiquidColors.glassHighlight;
  static const Color glassNav = Color(0xE8F7F7FB);
  static const Color textPrimary = LiquidColors.textPrimary;
  static const Color textSecondary = LiquidColors.textSecondary;
  static const Color divider = LiquidColors.separator;
  static const Color success = LiquidColors.success;
  static const Color danger = LiquidColors.danger;
  static const Color shadow = LiquidColors.shadow;
  static const Color hairline = LiquidColors.separatorLight;
}

class AppGradients {
  static const LinearGradient canvas = LiquidGradients.canvas;
  static const LinearGradient glass = LinearGradient(
    colors: [Color(0xE6FFFFFF), Color(0xBFFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient glassSoft = LinearGradient(
    colors: [Color(0xCCFFFFFF), Color(0x99FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient card = LinearGradient(
    colors: [Color(0x22007AFF), Color(0x00FF9F0A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppShadows {
  static const List<BoxShadow> card = LiquidShadows.glass;
  static const List<BoxShadow> glass = LiquidShadows.glass;
}
