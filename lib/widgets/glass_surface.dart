import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// A Liquid Glass surface widget that provides the iOS 26 glass material effect.
/// Custom implementation using BackdropFilter for realistic glass effects.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.settings,
    this.shadow,
    // Legacy parameters for backward compatibility
    this.blur,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets? padding;
  final LiquidGlassSettings? settings;
  final List<BoxShadow>? shadow;
  // Legacy parameters
  final double? blur;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final effectiveSettings = settings ?? LiquidGlassPresets.panel;
    final effectiveBlur = blur ?? effectiveSettings.blur;
    final highlightOpacity =
        (0.22 * effectiveSettings.lightIntensity).clamp(0.0, 0.35);
    final ambientOpacity =
        (0.12 * effectiveSettings.ambientStrength).clamp(0.0, 0.2);

    return Container(
      decoration: BoxDecoration(
        boxShadow: shadow ?? LiquidShadows.glass,
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: gradient,
              color: gradient == null ? effectiveSettings.glassColor : null,
              borderRadius: borderRadius,
              border: Border.all(
                color: borderColor ?? LiquidColors.glassStroke,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            LiquidColors.glassHighlight.withValues(
                              alpha: highlightOpacity,
                            ),
                            LiquidColors.glassHighlight.withValues(
                              alpha: ambientOpacity,
                            ),
                            const Color(0x00FFFFFF),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                if (padding != null)
                  Padding(
                    padding: padding!,
                    child: child,
                  )
                else
                  child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft glass surface with less prominent effects
class GlassSurfaceSoft extends StatelessWidget {
  const GlassSurfaceSoft({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      settings: LiquidGlassPresets.soft,
      borderRadius: borderRadius,
      padding: padding,
      shadow: LiquidShadows.subtle,
      child: child,
    );
  }
}

/// A thin glass surface for overlays and sheets
class GlassSurfaceThin extends StatelessWidget {
  const GlassSurfaceThin({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      settings: LiquidGlassPresets.thin,
      borderRadius: borderRadius,
      padding: padding,
      shadow: const [],
      child: child,
    );
  }
}

/// A glass button with Liquid Glass effect
class LiquidGlassButton extends StatelessWidget {
  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.isPrimary = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return CupertinoButton(
        padding: padding,
        color: LiquidColors.brand,
        borderRadius: BorderRadius.circular(LiquidRadius.sm),
        onPressed: onPressed,
        child: child,
      );
    }

    return GestureDetector(
      onTap: onPressed,
      child: GlassSurface(
        settings: LiquidGlassPresets.button,
        borderRadius: BorderRadius.circular(LiquidRadius.sm),
        padding: padding,
        shadow: LiquidShadows.subtle,
        child: child,
      ),
    );
  }
}

/// A glass card for content display
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = GlassSurface(
      settings: LiquidGlassPresets.panel,
      borderRadius: borderRadius ?? BorderRadius.circular(LiquidRadius.lg),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}

/// A meta chip for displaying small info tags
class GlassMetaChip extends StatelessWidget {
  const GlassMetaChip({
    super.key,
    required this.label,
    this.color,
  });

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? LiquidColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LiquidRadius.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: chipColor,
        ),
      ),
    );
  }
}

/// A section header with glass background
class GlassSectionHeader extends StatelessWidget {
  const GlassSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: LiquidTextStyles.headline,
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
