import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../localization/app_strings.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/glass_surface.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration:
            const BoxDecoration(gradient: LiquidGradients.vibrantCanvas),
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
                        children: [
                          Text(
                            strings.appTitle,
                            style: LiquidTextStyles.largeTitle.copyWith(
                              fontSize: 36,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            strings.appSubtitle,
                            style: LiquidTextStyles.subheadline.copyWith(
                              fontSize: 16,
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
                      child: GlassSurface(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _FeatureRow(
                              icon: CupertinoIcons.play_rectangle_fill,
                              title: strings.featureSyncTitle,
                              subtitle: strings.featureSyncSubtitle,
                            ),
                            const SizedBox(height: 12),
                            _FeatureRow(
                              icon: CupertinoIcons.text_alignleft,
                              title: strings.featureSummaryTitle,
                              subtitle: strings.featureSummarySubtitle,
                            ),
                            const SizedBox(height: 12),
                            _FeatureRow(
                              icon: CupertinoIcons.calendar,
                              title: strings.featureArchiveTitle,
                              subtitle: strings.featureArchiveSubtitle,
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
                            child: AppConfig.e2eTestMode
                                ? CupertinoButton(
                                    key: const ValueKey('e2e-login-button'),
                                    color: LiquidColors.glassLight,
                                    borderRadius:
                                        BorderRadius.circular(LiquidRadius.sm),
                                    onPressed: appState.isLoading
                                        ? null
                                        : controller.signInForE2E,
                                    child: Text(
                                      'E2E 테스트 로그인',
                                      style: LiquidTextStyles.footnote.copyWith(
                                        color: LiquidColors.brand,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : (kIsWeb
                                    ? GoogleSignInButton(
                                        disabled: appState.isLoading,
                                      )
                                    : CupertinoButton.filled(
                                        onPressed: appState.isLoading
                                            ? null
                                            : controller.signInWithGoogle,
                                        child: appState.isLoading
                                            ? const CupertinoActivityIndicator(
                                                color: CupertinoColors.white)
                                            : Text(strings.signInWithGoogle),
                                      )),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            strings.loginHelper,
                            style: LiquidTextStyles.caption1,
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
                  color: LiquidColors.accent.withValues(alpha: 0.12),
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
                  color: LiquidColors.brand.withValues(alpha: 0.08),
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
            color: LiquidColors.accentSoft,
            borderRadius: BorderRadius.circular(LiquidRadius.sm),
          ),
          child: Icon(icon, color: LiquidColors.brand, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: LiquidTextStyles.subheadline.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: LiquidTextStyles.caption1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
