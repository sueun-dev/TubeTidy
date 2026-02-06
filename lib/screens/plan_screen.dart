import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_strings.dart';
import '../models/plan.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/plan_card.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final tiers = [
      PlanTier.free,
      PlanTier.starter,
      PlanTier.growth,
      PlanTier.unlimited,
    ];
    final plans = tiers.map((tier) => Plan(tier: tier)).toList();
    final strings = ref.watch(appStringsProvider);

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: LiquidGradients.canvas),
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(strings.planTitle),
                backgroundColor: const Color(0x00000000),
                border: null,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: _CurrentPlanCard(
                    strings: strings,
                    plan: appState.plan,
                    selectedCount: appState.selectedCount,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    strings.planIntro,
                    style: LiquidTextStyles.subheadline,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final plan = plans[index];
                      return Padding(
                        key: ValueKey('plan-${plan.tier.name}'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PlanCard(
                          plan: plan,
                          isCurrent: appState.plan.tier == plan.tier,
                          strings: strings,
                          onSelect: () {
                            _handlePlanSelection(
                              context,
                              strings,
                              controller,
                              plan.tier,
                            );
                          },
                        ),
                      );
                    },
                    childCount: plans.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.panel,
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(LiquidRadius.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.billingTitle,
                          style: LiquidTextStyles.headline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.billingSubtitle,
                          style: LiquidTextStyles.footnote,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            LiquidGlassButton(
                              isPrimary: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              onPressed: () {
                                _handleRestorePurchases(
                                    context, strings, controller);
                              },
                              child: Text(
                                strings.viewReceipt,
                                style: const TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            LiquidGlassButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              onPressed: () {
                                _handleRestorePurchases(
                                    context, strings, controller);
                              },
                              child: Text(
                                strings.manageSubscription,
                                style: LiquidTextStyles.caption1.copyWith(
                                  color: LiquidColors.brand,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: GlassSurfaceSoft(
                    borderRadius: BorderRadius.circular(LiquidRadius.lg),
                    padding: const EdgeInsets.all(10),
                    child: Semantics(
                      label: '로그아웃',
                      button: true,
                      child: CupertinoButton(
                        color: LiquidColors.danger,
                        onPressed: controller.signOut,
                        child: Text(
                          strings.logout,
                          style: const TextStyle(color: CupertinoColors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handlePlanSelection(
    BuildContext context,
    AppStrings strings,
    AppController controller,
    PlanTier tier,
  ) async {
    final error = await controller.purchasePlan(tier);
    if (!context.mounted) return;
    if (error != null && error.isNotEmpty) {
      final message = _mapPurchaseError(error, strings);
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(strings.loginErrorTitle),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.ok),
            ),
          ],
        ),
      );
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(strings.planChangeTitle),
        content: Text(strings.planChangedBody(strings.planName(tier))),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRestorePurchases(
    BuildContext context,
    AppStrings strings,
    AppController controller,
  ) async {
    final error = await controller.restorePurchases();
    if (!context.mounted) return;
    if (error != null && error.isNotEmpty) {
      final message = _mapPurchaseError(error, strings);
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(strings.loginErrorTitle),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.ok),
            ),
          ],
        ),
      );
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(strings.actionDone),
        content: Text(strings.manageSubscription),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.ok),
          ),
        ],
      ),
    );
  }

  String _mapPurchaseError(String code, AppStrings strings) {
    switch (code) {
      case AppController.purchaseMissingProductId:
        return strings.iapMissingProductId;
      case AppController.purchaseUnavailable:
        return strings.iapUnavailable;
      case AppController.purchaseFailed:
        return strings.iapFailed;
      case AppController.restoreUnavailable:
        return strings.iapRestoreUnavailable;
      case AppController.restoreNone:
        return strings.iapRestoreEmpty;
      case AppController.restoreNotFound:
        return strings.iapRestoreNotFound;
      default:
        return code;
    }
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.strings,
    required this.plan,
    required this.selectedCount,
  });

  final AppStrings strings;
  final Plan plan;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final limit = plan.channelLimit;
    final limitLabel = strings.planLimitLabel(plan);
    final progress =
        limit == null ? 1.0 : (selectedCount / limit).clamp(0.0, 1.0);

    return GlassSurface(
      settings: LiquidGlassPresets.strong,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(LiquidRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.planTag(
                strings.planName(plan.tier), strings.planPriceLabel(plan.tier)),
            style: LiquidTextStyles.title3,
          ),
          const SizedBox(height: 6),
          Text(
            strings.planPriceLabel(plan.tier),
            style: LiquidTextStyles.subheadline,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${strings.planSelectedChannelsLabel}: $selectedCount / $limitLabel',
                  style: LiquidTextStyles.caption1,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: LiquidTextStyles.caption1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ProgressBar(progress: progress),
        ],
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
              height: 6,
              decoration: BoxDecoration(
                color: LiquidColors.glassDark,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 6,
              width: width,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [LiquidColors.brand, LiquidColors.brandLight],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        );
      },
    );
  }
}
