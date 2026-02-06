import 'package:flutter/cupertino.dart';

import '../localization/app_strings.dart';
import '../models/plan.dart';
import '../theme.dart';
import 'glass_surface.dart';

class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.isCurrent,
    required this.onSelect,
    required this.strings,
  });

  final Plan plan;
  final bool isCurrent;
  final VoidCallback onSelect;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      settings:
          isCurrent ? LiquidGlassPresets.strong : LiquidGlassPresets.panel,
      borderRadius: BorderRadius.circular(LiquidRadius.lg),
      borderColor: isCurrent ? LiquidColors.brand : LiquidColors.glassStroke,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  LiquidColors.glassUltraLight,
                  LiquidColors.glassMid,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(LiquidRadius.lg),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    strings.planName(plan.tier),
                    style: LiquidTextStyles.title3,
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: LiquidColors.accentSoft,
                      borderRadius: BorderRadius.circular(LiquidRadius.sm),
                    ),
                    child: Text(
                      strings.planInUse,
                      style: LiquidTextStyles.caption1.copyWith(
                        color: LiquidColors.brandDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              strings.planPriceLabel(plan.tier),
              style: LiquidTextStyles.headline,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              strings.planLimitLabel(plan),
              style: LiquidTextStyles.footnote,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: isCurrent
                  ? GlassSurfaceThin(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      borderRadius: BorderRadius.circular(LiquidRadius.sm),
                      child: Center(
                        child: Text(
                          strings.currentPlan,
                          style: LiquidTextStyles.footnote.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : LiquidGlassButton(
                      isPrimary: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onPressed: onSelect,
                      child: Text(
                        strings.selectPlan,
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
