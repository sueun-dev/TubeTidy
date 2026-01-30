import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class YouTubeSummaryApp extends ConsumerWidget {
  const YouTubeSummaryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return CupertinoApp.router(
      theme: buildCupertinoTheme(),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
