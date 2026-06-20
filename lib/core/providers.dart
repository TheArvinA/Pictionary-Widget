import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../services/widget_service.dart';
import 'auth/auth_service.dart';
import 'firebase/firestore_service.dart';
import 'firebase/functions_service.dart';
import 'firebase/storage_service.dart';
import 'notifications/fcm_service.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((_) => FirebaseAuth.instance);

final firestoreProvider =
    Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);

final firebaseStorageProvider =
    Provider<FirebaseStorage>((_) => FirebaseStorage.instance);

final firebaseFunctionsProvider =
    Provider<FirebaseFunctions>((_) => FirebaseFunctions.instance);

final authServiceProvider = Provider<AuthService>((ref) => AuthService(
      auth: ref.watch(firebaseAuthProvider),
      firestore: ref.watch(firestoreProvider),
    ));

final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(ref.watch(firestoreProvider)),
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(ref.watch(firebaseStorageProvider)),
);

final functionsServiceProvider = Provider<FunctionsService>(
  (ref) => FunctionsService(ref.watch(firebaseFunctionsProvider)),
);

final fcmServiceProvider = Provider<FcmService>(
  (ref) => FcmService(firestore: ref.watch(firestoreProvider)),
);

final widgetServiceProvider = Provider<WidgetService>((_) => WidgetService());

final authStateChangesProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// Watches user documents for each uid in [uids] and emits a merged
/// Map<uid, displayName>.  Emits once all sources have produced a value.
final friendNamesProvider = StreamProvider.autoDispose
    .family<Map<String, String>, List<String>>((ref, uids) {
  if (uids.isEmpty) return Stream.value(const <String, String>{});

  final service = ref.watch(firestoreServiceProvider);
  final streams = uids.map(service.watchUser).toList();

  final controller = StreamController<Map<String, String>>();
  final latest = List<AppUser?>.filled(uids.length, null);
  // Track which slots have received their first value.
  final received = List<bool>.filled(uids.length, false);
  var open = streams.length;

  void emit() {
    if (received.any((r) => !r)) return;
    final map = <String, String>{};
    for (var i = 0; i < uids.length; i++) {
      final user = latest[i];
      map[uids[i]] = user?.displayName ?? uids[i];
    }
    controller.add(map);
  }

  final subs = <StreamSubscription<AppUser?>>[];
  for (var i = 0; i < streams.length; i++) {
    final index = i;
    subs.add(
      streams[index].listen(
        (user) {
          latest[index] = user;
          received[index] = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          open--;
          if (open == 0) controller.close();
        },
      ),
    );
  }

  controller.onCancel = () async {
    for (final sub in subs) {
      await sub.cancel();
    }
  };

  return controller.stream;
});
