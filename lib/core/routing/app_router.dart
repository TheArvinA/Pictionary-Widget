import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/sign_in_screen.dart';
import '../../features/canvas/canvas_screen.dart';
import '../../features/feed/feed_screen.dart';
import '../../features/friends/friends_screen.dart';
import '../../features/guessing/guessing_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/results/results_screen.dart';
import '../../features/word_selection/word_selection_screen.dart';
import '../providers.dart';

// Tab routes in order: Home, Feed, Friends, Profile.
const _tabRoutes = ['/', '/feed', '/friends', '/profile'];

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStream = ref.watch(authServiceProvider).authStateChanges();

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _GoRouterRefresh(authStream),
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final signingIn = state.matchedLocation == '/sign-in';
      if (user == null) return signingIn ? null : '/sign-in';
      if (signingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      // Routes that push on top of the shell (no nav bar).
      GoRoute(
        path: '/canvas',
        builder: (ctx, st) => CanvasScreen(
          word: st.uri.queryParameters['word'] ?? '',
        ),
      ),
      GoRoute(
        path: '/guess/:drawerId',
        builder: (ctx, st) => GuessingScreen(
          drawerId: st.pathParameters['drawerId'] ?? '',
        ),
      ),
      GoRoute(path: '/results', builder: (_, __) => const ResultsScreen()),
      // Shell wrapping the four tab destinations.
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const WordSelectionScreen()),
          GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
          GoRoute(path: '/friends', builder: (_, __) => const FriendsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

// ---------------------------------------------------------------------------
// App shell with bottom NavigationBar (Material 3).
// ---------------------------------------------------------------------------

class _AppShell extends StatelessWidget {
  const _AppShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    // Find the best-matching tab index; default to 0 for unknown paths.
    int selectedIndex = 0;
    for (int i = _tabRoutes.length - 1; i >= 0; i--) {
      if (location.startsWith(_tabRoutes[i])) {
        selectedIndex = i;
        break;
      }
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(_tabRoutes[index]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Friends',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _GoRouterRefresh extends ChangeNotifier {
  _GoRouterRefresh(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
