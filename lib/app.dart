import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import 'core/providers.dart';
import 'core/routing/app_router.dart';

class PictionaryApp extends ConsumerStatefulWidget {
  const PictionaryApp({super.key});

  @override
  ConsumerState<PictionaryApp> createState() => _PictionaryAppState();
}

class _PictionaryAppState extends ConsumerState<PictionaryApp>
    with WidgetsBindingObserver {
  bool _tapsWired = false;
  StreamSubscription<Uri?>? _widgetClickSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClickSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWidget();
    }
  }

  /// Best-effort widget refresh; never throws (refresh swallows its own errors).
  void _refreshWidget() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    ref.read(widgetServiceProvider).refresh(
          firestore: ref.read(firestoreServiceProvider),
          uid: uid,
        );
  }

  /// Parses the `route` query param of a widget deep-link and navigates to it.
  /// URI scheme: pictionary://open?route=<URL-encoded go_router location>.
  void _openFromWidget(Uri? uri, GoRouter router) {
    if (uri == null) return;
    final route = uri.queryParameters['route'];
    if (route == null || route.isEmpty) return;
    router.go(route);
  }

  Future<void> _wireWidgetTaps(GoRouter router) async {
    // Warm taps while the app is running.
    _widgetClickSub =
        HomeWidget.widgetClicked.listen((uri) => _openFromWidget(uri, router));

    // Cold start: app launched by tapping the widget.
    try {
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      _openFromWidget(initial, router);
    } catch (_) {
      // Ignore: not launched from a widget, or platform unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // Register the FCM token (and daily-topic subscription) whenever a user
    // signs in. Without this no token is ever persisted, so push never works.
    ref.listen<AsyncValue<User?>>(authStateChangesProvider, (prev, next) {
      final uid = next.valueOrNull?.uid;
      if (uid != null) {
        ref.read(fcmServiceProvider).registerForUser(uid);
        // Seed the home-screen widget with this user's current state.
        ref.read(widgetServiceProvider).refresh(
              firestore: ref.read(firestoreServiceProvider),
              uid: uid,
            );
      }
    });

    // Wire taps once, now that the router exists.
    if (!_tapsWired) {
      _tapsWired = true;
      ref.read(fcmServiceProvider).wireNotificationTaps(router.go);
      _wireWidgetTaps(router);
    }

    return MaterialApp.router(
      title: 'Pictionary Daily',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
