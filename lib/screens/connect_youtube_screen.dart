import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme.dart';

class ConnectYouTubeScreen extends ConsumerWidget {
  const ConnectYouTubeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);

    return CupertinoPageScaffold(
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('YouTube 연동'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppGradients.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          CupertinoIcons.play_rectangle_fill,
                          color: AppColors.brand,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '구독 채널 동기화',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'YouTube 계정을 연동하면 구독 채널과 최신 업로드 영상을 가져올 수 있어요.',
                              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
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
                child: CupertinoListSection.insetGrouped(
                  hasLeading: true,
                  children: const [
                    _PermissionTile(text: '구독 채널 목록 읽기'),
                    _PermissionTile(text: '업로드 영상 메타데이터 읽기'),
                    _PermissionTile(text: '요약 품질 개선을 위한 익명 분석'),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: appState.isLoading ? null : controller.connectYouTubeAccount,
                    child: appState.isLoading
                        ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                        : const Text('YouTube 계정 연동'),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Text(
                  '연동 후 언제든지 해제할 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
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
    return CupertinoListTile.notched(
      leading: const Icon(CupertinoIcons.checkmark_circle_fill, color: AppColors.success),
      title: Text(text),
    );
  }
}
