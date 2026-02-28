import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../localization/app_strings.dart';
import '../state/app_controller.dart';
import '../state/ui_providers.dart';
import '../theme.dart';
import '../widgets/glass_surface.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final language = ref.watch(settingsLanguageProvider);
    final strings = ref.watch(appStringsProvider);

    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: LiquidGradients.canvas),
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(strings.settingsTitle),
                backgroundColor: const Color(0x00000000),
                border: null,
              ),
              // Language Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.panel,
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(LiquidRadius.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.globe,
                              size: 20,
                              color: LiquidColors.brand,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              strings.languageTitle,
                              style: LiquidTextStyles.headline,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _LanguageSelector(
                          strings: strings,
                          currentLanguage: language,
                          onChanged: (target) => _confirmLanguageChange(
                            context,
                            ref,
                            strings,
                            language,
                            target,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Account Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.panel,
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(LiquidRadius.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.person_circle,
                              size: 20,
                              color: LiquidColors.brand,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              strings.accountTitle,
                              style: LiquidTextStyles.headline,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        GlassSurfaceThin(
                          padding: const EdgeInsets.all(14),
                          borderRadius: BorderRadius.circular(LiquidRadius.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appState.user?.email ?? strings.noAccount,
                                style: LiquidTextStyles.subheadline,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  GlassMetaChip(
                                    label: strings.planName(appState.plan.tier),
                                    color: LiquidColors.brand,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    strings.planLimitLabel(appState.plan),
                                    style: LiquidTextStyles.caption1,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // App Info Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.panel,
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(LiquidRadius.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.info_circle,
                              size: 20,
                              color: LiquidColors.brand,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              strings.appInfoTitle,
                              style: LiquidTextStyles.headline,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          label: strings.versionLabel,
                          value: _formatVersion(strings),
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(
                          label: strings.buildLabel,
                          value: AppConfig.buildNumber.isNotEmpty
                              ? AppConfig.buildNumber
                              : strings.notAvailable,
                        ),
                        const SizedBox(height: 14),
                        _InfoLink(
                          icon: CupertinoIcons.lock_shield,
                          label: strings.privacyPolicy,
                          onPressed: AppConfig.privacyPolicyUrl.isNotEmpty
                              ? () => _openUrl(AppConfig.privacyPolicyUrl)
                              : null,
                        ),
                        const SizedBox(height: 10),
                        _InfoLink(
                          icon: CupertinoIcons.doc_text,
                          label: strings.termsOfService,
                          onPressed: AppConfig.termsUrl.isNotEmpty
                              ? () => _openUrl(AppConfig.termsUrl)
                              : null,
                        ),
                        const SizedBox(height: 10),
                        _InfoLink(
                          icon: CupertinoIcons.mail,
                          label: strings.support,
                          onPressed: AppConfig.supportEmail.isNotEmpty
                              ? () => _openEmail(AppConfig.supportEmail)
                              : (AppConfig.supportUrl.isNotEmpty
                                  ? () => _openUrl(AppConfig.supportUrl)
                                  : null),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Data Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.panel,
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(LiquidRadius.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.tray_full,
                              size: 20,
                              color: LiquidColors.brand,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              strings.dataTitle,
                              style: LiquidTextStyles.headline,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _DataAction(
                          icon: CupertinoIcons.doc_on_clipboard,
                          title: strings.clearSummaries,
                          subtitle: strings.clearSummariesBody,
                          onPressed: () => _confirmAction(
                            context,
                            strings,
                            strings.clearSummaries,
                            strings.clearSummariesBody,
                            () => controller.clearCachedSummaries(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DataAction(
                          icon: CupertinoIcons.star_slash,
                          title: strings.clearFavorites,
                          subtitle: strings.clearFavoritesBody,
                          onPressed: () => _confirmAction(
                            context,
                            strings,
                            strings.clearFavorites,
                            strings.clearFavoritesBody,
                            () async => controller.clearFavorites(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Logout Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: GlassSurface(
                    settings: LiquidGlassPresets.soft,
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(LiquidRadius.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.square_arrow_left,
                              size: 20,
                              color: LiquidColors.danger,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              strings.logout,
                              style: LiquidTextStyles.headline.copyWith(
                                color: LiquidColors.danger,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            key: const ValueKey('settings-logout-button'),
                            color: LiquidColors.danger,
                            borderRadius:
                                BorderRadius.circular(LiquidRadius.sm),
                            onPressed: controller.signOut,
                            child: Text(
                              strings.logout,
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _confirmAction(
    BuildContext context,
    AppStrings strings,
    String title,
    String body,
    Future<void> Function() onConfirm,
  ) async {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await onConfirm();
              if (!context.mounted) return;
              await showCupertinoDialog<void>(
                context: context,
                builder: (doneContext) => CupertinoAlertDialog(
                  title: Text(strings.actionDone),
                  content: Text(title),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.of(doneContext).pop(),
                      child: Text(strings.ok),
                    ),
                  ],
                ),
              );
            },
            child: Text(strings.confirm),
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmLanguageChange(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
    AppLanguage current,
    AppLanguage target,
  ) async {
    if (current == target) return;
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(strings.languageChangeTitle),
        content: Text(strings.languageChangeBody(target)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(settingsLanguageProvider.notifier).state = target;
            },
            child: Text(strings.confirm),
          ),
        ],
      ),
    );
  }

  static String _formatVersion(AppStrings strings) {
    if (AppConfig.appVersion.isEmpty) {
      return strings.notAvailable;
    }
    return AppConfig.appVersion;
  }

  static Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _openEmail(String email) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({
    required this.strings,
    required this.currentLanguage,
    required this.onChanged,
  });

  final AppStrings strings;
  final AppLanguage currentLanguage;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppLanguage.values.map((lang) {
        final isSelected = currentLanguage == lang;
        return GestureDetector(
          onTap: () => onChanged(lang),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? LiquidColors.brand : LiquidColors.glassMid,
              borderRadius: BorderRadius.circular(LiquidRadius.sm),
              border: Border.all(
                color:
                    isSelected ? LiquidColors.brand : LiquidColors.glassStroke,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 14,
                    color: LiquidColors.textInverse,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  strings.languageName(lang),
                  style: LiquidTextStyles.footnote.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? LiquidColors.textInverse
                        : LiquidColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: LiquidTextStyles.subheadline),
        ),
        Text(
          value,
          style: LiquidTextStyles.footnote.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InfoLink extends StatelessWidget {
  const _InfoLink({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: GlassSurfaceThin(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: BorderRadius.circular(LiquidRadius.sm),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: LiquidColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: LiquidTextStyles.subheadline),
            ),
            if (onPressed != null)
              const Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: LiquidColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

class _DataAction extends StatelessWidget {
  const _DataAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassSurfaceThin(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(LiquidRadius.md),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: LiquidColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LiquidTextStyles.headline),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: LiquidTextStyles.caption1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          LiquidGlassButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            onPressed: onPressed,
            child: const Icon(
              CupertinoIcons.trash,
              size: 16,
              color: LiquidColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
