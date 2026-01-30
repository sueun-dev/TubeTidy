import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plan.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/plan_card.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final plans = PlanTier.values.map((tier) => Plan(tier: tier)).toList();

    return CupertinoPageScaffold(
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('플랜 관리'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: _CurrentPlanCard(
                  plan: appState.plan,
                  selectedCount: appState.selectedCount,
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  '채널 선택 한도 및 요금제를 변경하세요.',
                  style: TextStyle(color: AppColors.textSecondary),
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
                        onSelect: () {
                          controller.upgradePlan(plan.tier);
                          showCupertinoDialog<void>(
                            context: context,
                            builder: (dialogContext) => CupertinoAlertDialog(
                              title: const Text('플랜 변경 완료'),
                              content: Text('${plan.displayName} 플랜으로 변경되었습니다.'),
                              actions: [
                                CupertinoDialogAction(
                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                  child: const Text('확인'),
                                ),
                              ],
                            ),
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
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '결제/영수증',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'iOS 인앱 결제 연동 후 영수증과 갱신 정보를 확인할 수 있습니다.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: AppColors.brand,
                            onPressed: () {},
                            child: const Text(
                              '영수증 보기',
                              style: TextStyle(color: CupertinoColors.white, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: AppColors.divider,
                            onPressed: () {},
                            child: const Text(
                              '구독 관리',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
                child: Semantics(
                  label: '로그아웃',
                  button: true,
                  child: CupertinoButton(
                    color: AppColors.danger,
                    onPressed: controller.signOut,
                    child: const Text(
                      '로그아웃',
                      style: TextStyle(color: CupertinoColors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.plan,
    required this.selectedCount,
  });

  final Plan plan;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final limit = plan.channelLimit;
    final limitLabel = plan.limitLabel;
    final progress = limit == null ? 1.0 : (selectedCount / limit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradients.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plan.displayName} 플랜',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            plan.priceLabel,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '채널 선택: $selectedCount / $limitLabel',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                color: AppColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.hairline),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 6,
              width: width,
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        );
      },
    );
  }
}
