import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
