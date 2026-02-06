import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_strings.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/google_sign_in_button.dart';

class ConnectYouTubeScreen extends ConsumerWidget {
  const ConnectYouTubeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: LiquidGradients.canvas),
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(strings.connectTitle),
                backgroundColor: const Color(0x00000000),
                border: null,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.panel,
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(LiquidRadius.lg),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: LiquidColors.accentSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            CupertinoIcons.play_rectangle_fill,
                            color: LiquidColors.brand,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.connectCardTitle,
                                style: LiquidTextStyles.title3,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                strings.connectCardSubtitle,
                                style: LiquidTextStyles.footnote.copyWith(
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.soft,
                    padding: const EdgeInsets.all(14),
                    borderRadius: BorderRadius.circular(LiquidRadius.lg),
                    child: Column(
                      children: [
                        _PermissionTile(
                          text: strings.permissionReadSubscriptions,
                        ),
                        const SizedBox(height: 10),
                        _PermissionTile(text: strings.permissionReadMetadata),
                        const SizedBox(height: 10),
                        _PermissionTile(text: strings.permissionAnalytics),
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
                    child: kIsWeb
                        ? GoogleSignInButton(
                            disabled: appState.isLoading,
                          )
                        : CupertinoButton.filled(
                            onPressed: appState.isLoading
                                ? null
                                : controller.connectYouTubeAccount,
                            child: appState.isLoading
                                ? const CupertinoActivityIndicator(
                                    color: CupertinoColors.white)
                                : Text(strings.connectButton),
                          ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Text(
                    strings.connectFooter,
                    style: LiquidTextStyles.caption1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassSurfaceThin(
      borderRadius: BorderRadius.circular(LiquidRadius.sm),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.checkmark_circle_fill,
            color: LiquidColors.success,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: LiquidTextStyles.subheadline,
            ),
          ),
        ],
      ),
    );
  }
}
