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
      GoRoute(path: '/', builder: (_, __) => const WordSelectionScreen()),
      GoRoute(
        path: '/canvas',
        builder: (ctx, st) => CanvasScreen(
          word: st.uri.queryParameters['word'] ?? '',
        ),
      ),
      GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
      GoRoute(
        path: '/guess/:drawerId',
        builder: (ctx, st) => GuessingScreen(
          drawerId: st.pathParameters['drawerId'] ?? '',
        ),
      ),
      GoRoute(path: '/results', builder: (_, __) => const ResultsScreen()),
      GoRoute(path: '/friends', builder: (_, __) => const FriendsScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    ],
  );
});

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
