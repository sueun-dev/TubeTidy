import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/channel_selection_screen.dart';
import 'screens/connect_youtube_screen.dart';
import 'screens/main_tab_scaffold.dart';
import 'screens/onboarding_screen.dart';
import 'screens/plan_screen.dart';
import 'state/app_controller.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(appControllerProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: AppRouterRefreshStream(notifier.stream),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/channels',
        builder: (context, state) => const ChannelSelectionScreen(),
      ),
      GoRoute(
        path: '/app',
        builder: (context, state) {
          final rawTab = state.uri.queryParameters['tab'];
          final parsedTab = int.tryParse(rawTab ?? '');
          final tabIndex = parsedTab != null && parsedTab >= 0 && parsedTab <= 4
              ? parsedTab
              : 0;
          return MainTabScaffold(initialTabIndex: tabIndex);
        },
      ),
      GoRoute(
        path: '/plan',
        builder: (context, state) => const PlanScreen(),
      ),
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectYouTubeScreen(),
      ),
    ],
    redirect: (context, state) {
      final appState = ref.read(appControllerProvider);
      final signedIn = appState.isSignedIn;
      final selected = appState.selectionCompleted;
      final location = state.matchedLocation;

      if (!signedIn) {
        return location == '/' ? null : '/';
      }

      if (signedIn && !selected) {
        if (location == '/channels' ||
            location == '/plan' ||
            location == '/connect') {
          return null;
        }
        return '/channels';
      }

      if (signedIn && selected) {
        if (location == '/app' ||
            location == '/plan' ||
            location == '/channels') {
          return null;
        }
        return '/app';
      }

      return null;
    },
  );
});

class AppRouterRefreshStream extends ChangeNotifier {
  AppRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
