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

  /// A widget deep-link captured at cold start before Firebase Auth has
  /// restored the persisted session. Replayed from the auth listener in
  /// [build] once a user is present, so the canvas destination isn't lost to
  /// the go_router redirect (which sends a null user to /sign-in then /).
  String? _pendingDeepLink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_tapsWired) {
      _tapsWired = true;
      final router = ref.read(appRouterProvider);
      ref.read(fcmServiceProvider).wireNotificationTaps(router.go);
      _wireWidgetTaps(router);
    }
  }

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
    unawaited(ref.read(widgetServiceProvider).refresh(
      firestore: ref.read(firestoreServiceProvider),
      uid: uid,
    ));
  }

  /// Parses the `route` query param of a widget deep-link and navigates to it.
  /// URI scheme: pictionary://open?route=<URL-encoded go_router location>.
  void _openFromWidget(Uri? uri, GoRouter router) {
    if (uri == null) return;
    final route = uri.queryParameters['route'];
    if (route == null || route.isEmpty) return;

    // Cold start: Firebase Auth restores the persisted session asynchronously,
    // so currentUser is still null here. Navigating now would be overwritten by
    // the redirect (-> /sign-in then -> /), losing the deep link. Defer it and
    // actively wait for the first restored user — don't rely solely on the
    // authStateChanges listener in [build], whose loading->data transition can
    // be missed if auth restores before that listener registers.
    if (FirebaseAuth.instance.currentUser == null) {
      _pendingDeepLink = route;
      unawaited(_navigateOnceAuthRestored(router));
      return;
    }
    router.go(route);
  }

  /// Waits for Firebase Auth to restore a non-null user (with a timeout), then
  /// replays the pending widget deep-link. Robust against the race where the
  /// auth state becomes non-null before the [build] listener is attached, which
  /// would otherwise strand the app on Home. The listener and this path both
  /// null out [_pendingDeepLink] first, so whichever wins navigates exactly once.
  Future<void> _navigateOnceAuthRestored(GoRouter router) async {
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Timed out or stream error: leave _pendingDeepLink for the listener.
      return;
    }
    final pending = _pendingDeepLink;
    if (pending == null) return; // The auth listener already replayed it.
    _pendingDeepLink = null;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.go(pending);
    });
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
        unawaited(ref.read(widgetServiceProvider).refresh(
              firestore: ref.read(firestoreServiceProvider),
              uid: uid,
            ));

        // Replay a widget deep-link that arrived before auth was restored.
        // Clear the field first so a later auth emission can't double-navigate.
        // Schedule post-frame to avoid navigating during the build/listen pass.
        final pending = _pendingDeepLink;
        if (pending != null) {
          _pendingDeepLink = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            router.go(pending);
          });
        }
      }
    });

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
