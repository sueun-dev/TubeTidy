import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/plan.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/channel_tile.dart';

class ChannelSelectionScreen extends ConsumerWidget {
  const ChannelSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(
      appControllerProvider.select((state) => state.toastMessage),
      (previous, next) {
        if (next == null || next.isEmpty) return;
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('알림'),
            content: Text(next),
            actions: [
              CupertinoDialogAction(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  ref.read(appControllerProvider.notifier).clearToast();
                },
                child: const Text('확인'),
              ),
            ],
          ),
        );
      },
    );

    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);

    return CupertinoPageScaffold(
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('채널 선택'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: _PlanOverviewCard(
                  plan: appState.plan,
                  selectedCount: appState.selectedCount,
                  channelLimit: appState.channelLimit,
                  onUpgrade: () => context.push('/plan'),
                ),
              ),
            ),
            if (appState.channels.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CupertinoListSection.insetGrouped(
                    hasLeading: true,
                    children: appState.channels.map((channel) {
                      final isSelected = appState.selectedChannelIds.contains(channel.id);
                      final isDisabled = !isSelected && !controller.canSelectMore();

                      return ChannelTile(
                        key: ValueKey(channel.id),
                        channel: channel,
                        isSelected: isSelected,
                        isDisabled: isDisabled,
                        onChanged: (_) => controller.toggleChannel(channel.id),
                      );
                    }).toList(),
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                        Text(
                          appState.isLoading ? '구독 채널 불러오는 중' : '구독 채널이 없습니다.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          appState.isLoading
                              ? 'Google 로그인과 YouTube 동기화를 진행하고 있어요.'
                              : 'YouTube 구독 목록을 불러오지 못했어요. 다시 시도해주세요.',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        if (appState.isLoading)
                          const CupertinoActivityIndicator()
                        else
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: AppColors.brand,
                            onPressed: controller.refreshSubscriptions,
                            child: const Text(
                              '다시 불러오기',
                              style: TextStyle(color: CupertinoColors.white, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: appState.isLoading || !appState.hasSelection
                        ? null
                        : controller.finalizeChannelSelection,
                    child: appState.isLoading
                        ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                        : const Text('채널 선택 완료'),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Text(
                  appState.selectionCompleted
                      ? '채널 변경은 하루에 1회만 가능합니다.'
                      : '구독 수에 따라 선택 가능한 채널 수가 자동으로 조정됩니다.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanOverviewCard extends StatelessWidget {
  const _PlanOverviewCard({
    required this.plan,
    required this.selectedCount,
    required this.channelLimit,
    required this.onUpgrade,
  });

  final Plan plan;
  final int selectedCount;
  final int channelLimit;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final limit = channelLimit;
    final limitLabel = limit <= 0 ? '0 채널' : '$limit 채널';
    final progress =
        limit <= 0 ? 0.0 : (selectedCount / limit).clamp(0.0, 1.0);

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
          Row(
            children: [
              Text(
                '${plan.displayName} 플랜',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: AppColors.accent,
                onPressed: onUpgrade,
                child: const Text(
                  '업그레이드',
                  style: TextStyle(color: CupertinoColors.white, fontSize: 12),
                ),
              ),
            ],
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
                  '선택됨 $selectedCount / $limitLabel',
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
