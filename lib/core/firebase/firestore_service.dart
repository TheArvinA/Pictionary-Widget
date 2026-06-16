import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/app_user.dart';
import '../../models/daily_words.dart';
import '../../models/guess.dart';
import '../../models/player_round.dart';

class FirestoreService {
  FirestoreService(this._db);
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _db.collection('users').doc(uid);

  Stream<AppUser?> watchUser(String uid) => userRef(uid).snapshots().map(
        (snap) => snap.exists ? AppUser.fromFirestore(snap) : null,
      );

  Stream<DailyWords?> watchDailyWords(String date) =>
      _db.collection('daily').doc(date).snapshots().map(
            (snap) => snap.exists ? DailyWords.fromFirestore(snap) : null,
          );

  DocumentReference<Map<String, dynamic>> playerRoundRef({
    required String date,
    required String drawerId,
  }) =>
      _db.collection('rounds').doc(date).collection('players').doc(drawerId);

  Stream<PlayerRound?> watchPlayerRound({
    required String date,
    required String drawerId,
  }) =>
      playerRoundRef(date: date, drawerId: drawerId).snapshots().map(
            (snap) => snap.exists ? PlayerRound.fromFirestore(snap) : null,
          );

  /// Records the chosen word for today's round. Must NOT touch
  /// `hasSubmittedDrawing`: merging it as false would clobber an already-true
  /// submission (re-locking feed/guessing/storage reads and double-firing the
  /// streak/notification triggers). The flag defaults to false via
  /// [PlayerRound.hasSubmittedDrawing] / the firestore rules treat an absent
  /// field as not-submitted, so a brand-new round still starts not-submitted.
  Future<void> chooseWord({
    required String date,
    required String drawerId,
    required String word,
  }) =>
      playerRoundRef(date: date, drawerId: drawerId).set({
        'chosenWord': word,
      }, SetOptions(merge: true));

  Future<void> submitDrawing({
    required String date,
    required String drawerId,
    required String drawingUrl,
  }) =>
      playerRoundRef(date: date, drawerId: drawerId).set({
        'drawingUrl': drawingUrl,
        'hasSubmittedDrawing': true,
        'submittedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Stream<List<PlayerRound>> watchFriendDrawings({
    required String date,
    required List<String> friendIds,
  }) {
    if (friendIds.isEmpty) return Stream.value(const []);

    // Firestore caps `whereIn` at 30 values, so chunk and merge the streams.
    final players =
        _db.collection('rounds').doc(date).collection('players');
    final streams = <Stream<List<PlayerRound>>>[];
    for (var i = 0; i < friendIds.length; i += 30) {
      final chunk =
          friendIds.sublist(i, math.min(i + 30, friendIds.length));
      streams.add(
        players
            .where(FieldPath.documentId, whereIn: chunk)
            .snapshots()
            .map((qs) => qs.docs.map(PlayerRound.fromFirestore).toList()),
      );
    }
    return streams.length == 1 ? streams.first : _combineLatest(streams);
  }

  /// Combines several list-streams into one stream of the concatenated lists,
  /// emitting only once every source has produced at least one value.
  Stream<List<PlayerRound>> _combineLatest(
    List<Stream<List<PlayerRound>>> streams,
  ) {
    final controller = StreamController<List<PlayerRound>>();
    final latest = List<List<PlayerRound>?>.filled(streams.length, null);
    final subs = <StreamSubscription<List<PlayerRound>>>[];
    var open = streams.length;

    void emit() {
      if (latest.any((e) => e == null)) return;
      controller.add([for (final list in latest) ...list!]);
    }

    for (var i = 0; i < streams.length; i++) {
      final index = i;
      subs.add(
        streams[i].listen(
          (data) {
            latest[index] = data;
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
  }

  DocumentReference<Map<String, dynamic>> guessRef({
    required String date,
    required String guesserId,
    required String drawerId,
  }) =>
      _db.collection('rounds').doc(date).collection('guesses').doc(
            Guess.idFor(guesserId: guesserId, drawerId: drawerId),
          );

  Stream<Guess?> watchGuess({
    required String date,
    required String guesserId,
    required String drawerId,
  }) =>
      guessRef(date: date, guesserId: guesserId, drawerId: drawerId)
          .snapshots()
          .map((snap) => snap.exists ? Guess.fromFirestore(snap) : null);

  Future<void> recordGuess({
    required String date,
    required Guess guess,
  }) =>
      guessRef(
        date: date,
        guesserId: guess.guesserId,
        drawerId: guess.drawerId,
      ).set({
        ...guess.toFirestore(),
        'completedAt': FieldValue.serverTimestamp(),
      });
}
