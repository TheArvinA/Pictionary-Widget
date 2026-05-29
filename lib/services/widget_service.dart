import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/firebase/firestore_service.dart';
import '../core/util/today.dart';
import '../models/app_user.dart';
import '../models/player_round.dart';

/// A single friend entry as the home-screen widget needs it.
typedef WidgetFriend = ({
  String uid,
  String name,
  String? thumbUrl,
  bool submitted,
});

/// Syncs app state into the Android home-screen widget and triggers a redraw.
///
/// The cross-side contract (Kotlin [PictionaryWidgetProvider] reads these exact
/// SharedPreferences keys/types):
///   'w_state'   int     1 | 2 | 3            (default 1)
///   'w_words'   String  JSON array of strings
///   'w_friends' String  JSON array of {uid,name,thumbUrl,submitted}
///   'w_streak'  int     streak count         (default 0)
///   'w_day'     int     day number (state 3) (default 0)
///   'w_solved'  int     friends guessed today (default 0)
///   'w_total'   int     friend drawings available today (default 0)
class WidgetService {
  WidgetService();

  /// Must match the Kotlin provider class registered in the manifest.
  static const String androidName = 'PictionaryWidgetProvider';
  static const String qualifiedAndroidName =
      'com.pictionary.pictionary_app.PictionaryWidgetProvider';

  static const _kState = 'w_state';
  static const _kWords = 'w_words';
  static const _kFriends = 'w_friends';
  static const _kStreak = 'w_streak';
  static const _kDay = 'w_day';
  static const _kSolved = 'w_solved';
  static const _kTotal = 'w_total';

  /// Writes the given widget state to shared storage and asks Android to redraw.
  Future<void> sync({
    required int state,
    required List<String> words,
    required List<WidgetFriend> friends,
    required int streak,
    required int day,
    required int solved,
    required int total,
  }) async {
    final friendsJson = jsonEncode([
      for (final f in friends)
        {
          'uid': f.uid,
          'name': f.name,
          'thumbUrl': f.thumbUrl,
          'submitted': f.submitted,
        },
    ]);

    await Future.wait([
      HomeWidget.saveWidgetData<int>(_kState, state),
      HomeWidget.saveWidgetData<String>(_kWords, jsonEncode(words)),
      HomeWidget.saveWidgetData<String>(_kFriends, friendsJson),
      HomeWidget.saveWidgetData<int>(_kStreak, streak),
      HomeWidget.saveWidgetData<int>(_kDay, day),
      HomeWidget.saveWidgetData<int>(_kSolved, solved),
      HomeWidget.saveWidgetData<int>(_kTotal, total),
    ]);

    await HomeWidget.updateWidget(
      androidName: androidName,
      qualifiedAndroidName: qualifiedAndroidName,
    );
  }

  /// Gathers the current per-user state from Firestore and pushes it to the
  /// widget. Best-effort: any failure (e.g. Firebase unconfigured in dev) is
  /// swallowed so it can never crash startup or a UI action.
  Future<void> refresh({
    required FirestoreService firestore,
    required String? uid,
  }) async {
    try {
      if (uid == null || uid.isEmpty) return;
      final today = todayKey();

      // Own round decides the anti-cheat gate between state 1 and 2/3.
      final PlayerRound? myRound = await firestore
          .watchPlayerRound(date: today, drawerId: uid)
          .first;
      final AppUser? me = await firestore.watchUser(uid).first;
      final int streak = me?.streakCount ?? 0;

      // State 1: haven't submitted a drawing yet — show the word choices.
      if (myRound == null || !myRound.hasSubmittedDrawing) {
        final daily = await firestore.watchDailyWords(today).first;
        final words = daily?.wordChoices ?? const <String>[];
        await sync(
          state: 1,
          words: words.take(3).toList(),
          friends: const [],
          streak: streak,
          day: streak,
          solved: 0,
          total: 0,
        );
        return;
      }

      // Already submitted — look at friends' drawings to pick state 2 vs 3.
      final friendIds = me?.friendIds ?? const <String>[];
      final List<PlayerRound> friendRounds = await firestore
          .watchFriendDrawings(date: today, friendIds: friendIds)
          .first;

      // Only friends who actually submitted a drawing are guessable.
      final submitted = friendRounds
          .where((r) => r.hasSubmittedDrawing && r.drawingUrl != null)
          .toList();
      final total = submitted.length;

      // `completed` drives the state 2->3 transition (have you finished guessing
      // everyone available, regardless of outcome). `correct` is the count shown
      // in the state-3 "you guessed X/Y correctly" summary.
      var completed = 0;
      var correct = 0;
      final friends = <WidgetFriend>[];
      for (final r in submitted) {
        final guess = await firestore
            .watchGuess(date: today, guesserId: uid, drawerId: r.drawerId)
            .first;
        if (guess != null) {
          completed++;
          if (guess.correct) correct++;
        }
        friends.add((
          uid: r.drawerId,
          name: await _displayName(firestore, r.drawerId),
          thumbUrl: r.drawingUrl,
          submitted: true,
        ));
      }

      // Also surface friends who haven't drawn yet as "waiting" entries.
      final submittedIds = submitted.map((r) => r.drawerId).toSet();
      for (final id in friendIds) {
        if (submittedIds.contains(id)) continue;
        friends.add((
          uid: id,
          name: await _displayName(firestore, id),
          thumbUrl: null,
          submitted: false,
        ));
      }

      // State 3 once every available friend drawing has been guessed; otherwise
      // state 2. With no friend drawings to guess, stay in state 2 (feed).
      final allGuessed = total > 0 && completed >= total;
      await sync(
        state: allGuessed ? 3 : 2,
        words: const [],
        friends: friends,
        streak: streak,
        day: streak,
        solved: correct,
        total: total,
      );
    } catch (e, st) {
      debugPrint('WidgetService.refresh failed: $e\n$st');
    }
  }

  Future<String> _displayName(FirestoreService firestore, String uid) async {
    try {
      final user = await firestore.watchUser(uid).first;
      return user?.displayName ?? 'Player';
    } catch (_) {
      return 'Player';
    }
  }
}
