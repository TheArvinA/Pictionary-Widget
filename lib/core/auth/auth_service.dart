import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user != null) {
      await _ensureUserDoc(user);
    }
    return user;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> _ensureUserDoc(User user) async {
    final ref = _firestore.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update({
        'displayName': user.displayName ?? snap.data()?['displayName'] ?? 'Player',
        'photoUrl': user.photoURL,
      });
      return;
    }
    await ref.set({
      'displayName': user.displayName ?? 'Player',
      'photoUrl': user.photoURL,
      'inviteCode': _generateInviteCode(),
      'friendIds': <String>[],
      'streakCount': 0,
      'lastPlayedDate': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static String _generateInviteCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
  }
}
