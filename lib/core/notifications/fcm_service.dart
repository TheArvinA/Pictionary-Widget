import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmService {
  FcmService({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
      : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  StreamSubscription<String>? _tokenRefreshSub;

  Future<void> registerForUser(String uid) async {
    await _messaging.requestPermission();
    final token = await _messaging.getToken();
    if (token != null) {
      await _firestore.collection('users').doc(uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    }
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
      _firestore.collection('users').doc(uid).set(
        {'fcmToken': newToken},
        SetOptions(merge: true),
      );
    });

    // Subscribe to the broadcast topic used for the daily word reset push.
    await _messaging.subscribeToTopic('daily');
  }

  /// Wires tap-to-navigate. Call once after the router is available, passing a
  /// callback that navigates to the route found in `message.data['route']`.
  ///
  /// Handles both a cold start (app launched from a notification) and the
  /// warm case (app in background, tapped to open).
  Future<void> wireNotificationTaps(void Function(String route) onOpen) async {
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      final route = initial.data['route'] as String?;
      if (route != null && route.isNotEmpty) onOpen(route);
    }

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = message.data['route'] as String?;
      if (route != null && route.isNotEmpty) onOpen(route);
    });
  }
}
