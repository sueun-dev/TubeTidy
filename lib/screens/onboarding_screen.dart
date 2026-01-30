import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(
      appControllerProvider.select((state) => state.toastMessage),
      (previous, next) {
        if (next == null || next.isEmpty) return;
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('로그인 오류'),
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
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.hero),
        child: SafeArea(
          child: Stack(
            children: [
              const _BackdropOrbs(),
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'YouTube\n3줄 요약',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            '구독 채널의 최신 업로드를\n3줄 요약으로 바로 확인하세요.',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.divider),
                          boxShadow: AppShadows.card,
                        ),
                        child: const Column(
                          children: [
                            _FeatureRow(
                              icon: CupertinoIcons.play_rectangle_fill,
                              title: '구독 채널 자동 동기화',
                              subtitle: '로그인 후 연결 즉시 최신 채널을 불러옵니다.',
                            ),
                            SizedBox(height: 12),
                            _FeatureRow(
                              icon: CupertinoIcons.text_alignleft,
                              title: '핵심만 3줄 요약',
                              subtitle: '긴 영상도 핵심만 빠르게 읽어보세요.',
                            ),
                            SizedBox(height: 12),
                            _FeatureRow(
                              icon: CupertinoIcons.calendar,
                              title: '아카이빙 캘린더',
                              subtitle: '저장한 요약을 날짜별로 모아볼 수 있어요.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton.filled(
                              onPressed: appState.isLoading ? null : controller.signInWithGoogle,
                              child: appState.isLoading
                                  ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                                  : const Text('Google로 로그인'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '로그인하면 YouTube 계정이 자동으로 연동됩니다.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropOrbs extends StatelessWidget {
  const _BackdropOrbs();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(31),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.brand.withAlpha(20),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.brand, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
