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

  /// Returns this user's personal 3-word subset for [date], chosen randomly
  /// from the shared daily pool and persisted (idempotently) to their
  /// owner-only private round doc. Giving each user a different subset means
  /// friends rarely draw the same word, so guessing stays meaningful. The app
  /// and the home-screen widget both call this, so they always agree.
  ///
  /// Returns `const []` when the pool isn't ready yet. Never reshuffles: once a
  /// valid 3-word selection exists in the private doc it's returned unchanged.
  Future<List<String>> ensureMyWords({
    required String date,
    required String drawerId,
  }) async {
    final daily = await watchDailyWords(date).first;
    final pool = daily?.wordChoices ?? const <String>[];
    if (pool.isEmpty) return const [];

    final ref = privateRoundRef(date: date, drawerId: drawerId);
    return _db.runTransaction<List<String>>((tx) async {
      final snap = await tx.get(ref);
      final existing = snap.data()?['wordChoices'];
      if (existing is List &&
          existing.length == 3 &&
          existing.every((e) => e is String)) {
        return existing.cast<String>();
      }

      final shuffled = [...pool]..shuffle(math.Random());
      final picked = shuffled.take(3).toList();
      tx.set(ref, {'wordChoices': picked}, SetOptions(merge: true));
      return picked;
    });
  }

  DocumentReference<Map<String, dynamic>> playerRoundRef({
    required String date,
    required String drawerId,
  }) =>
      _db.collection('rounds').doc(date).collection('players').doc(drawerId);

  /// Owner-only doc holding the drawer's secret word. Lives under the player
  /// doc but in a `private` subcollection that firestore.rules locks to the
  /// owner, so guessers can't read the answer. The submitGuess callable reads
  /// it via the admin SDK to validate guesses server-side.
  DocumentReference<Map<String, dynamic>> privateRoundRef({
    required String date,
    required String drawerId,
  }) =>
      playerRoundRef(date: date, drawerId: drawerId)
          .collection('private')
          .doc('round');

  Stream<PlayerRound?> watchPlayerRound({
    required String date,
    required String drawerId,
  }) =>
      playerRoundRef(date: date, drawerId: drawerId).snapshots().map(
            (snap) => snap.exists ? PlayerRound.fromFirestore(snap) : null,
          );

  /// Records the chosen word for today's round into the owner-only private
  /// doc, never the player doc (which is readable by friends once a drawing is
  /// submitted). An orphan private doc with no parent player doc is fine in
  /// Firestore; the player doc is created later by [submitDrawing].
  Future<void> chooseWord({
    required String date,
    required String drawerId,
    required String word,
  }) =>
      privateRoundRef(date: date, drawerId: drawerId).set({
        'chosenWord': word,
      }, SetOptions(merge: true));

  /// Streams the owner's own secret word from their private round doc. Only the
  /// owner may read it per firestore.rules; used by the owner's results screen.
  Stream<String?> watchMyChosenWord({
    required String date,
    required String drawerId,
  }) =>
      privateRoundRef(date: date, drawerId: drawerId).snapshots().map(
            (snap) => snap.data()?['chosenWord'] as String?,
          );

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
}
