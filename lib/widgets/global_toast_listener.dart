import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_strings.dart';
import '../state/app_controller.dart';

class GlobalToastListener extends ConsumerStatefulWidget {
  const GlobalToastListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GlobalToastListener> createState() =>
      _GlobalToastListenerState();
}

class _GlobalToastListenerState extends ConsumerState<GlobalToastListener> {
  String? _lastMessage;
  bool _isShowing = false;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    // Wait until after the first frame to mark as ready
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _isReady = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      appControllerProvider.select((state) => state.toastMessage),
      (previous, next) {
        if (next == null || next.isEmpty) return;
        if (_isShowing || next == _lastMessage) return;
        if (!_isReady) {
          // Not ready yet, clear the toast and skip
          ref.read(appControllerProvider.notifier).clearToast();
          return;
        }
        _lastMessage = next;
        _showToast(context, next);
      },
    );

    return widget.child;
  }

  Future<void> _showToast(BuildContext context, String message) async {
    _isShowing = true;
    if (!mounted) return;

    try {
      final strings = ref.read(appStringsProvider);
      await showCupertinoDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(strings.notice),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref.read(appControllerProvider.notifier).clearToast();
              },
              child: Text(strings.ok),
            ),
          ],
        ),
      );
    } catch (e) {
      // Navigator not available, just clear the toast
      ref.read(appControllerProvider.notifier).clearToast();
    }
    _isShowing = false;
  }
}
