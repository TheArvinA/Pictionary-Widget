import 'package:cloud_functions/cloud_functions.dart';

class FunctionsService {
  FunctionsService(this._functions);
  final FirebaseFunctions _functions;

  /// Links the current user with the owner of [code] via the
  /// `addFriendByCode` callable (admin SDK writes both users' friendIds).
  Future<({String friendId, String displayName, bool alreadyFriends})>
      addFriendByCode(String code) async {
    try {
      final callable = _functions.httpsCallable('addFriendByCode');
      final result = await callable.call<Map<String, dynamic>>({'code': code});
      final data = result.data;
      return (
        friendId: (data['friendId'] as String?) ?? '',
        displayName: (data['displayName'] as String?) ?? 'Player',
        alreadyFriends: (data['alreadyFriends'] as bool?) ?? false,
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(_messageFor(e));
    }
  }

  /// Submits a guess via the `submitGuess` callable. The word lives in an
  /// owner-only Firestore location, so correctness is validated server-side
  /// (admin SDK) and the answer is only returned once the guess is finished.
  Future<
      ({
        bool correct,
        List<String> attempts,
        bool finished,
        int? solvedOnAttempt,
        String? revealedWord,
      })> submitGuess({
    required String date,
    required String drawerId,
    required String guess,
  }) async {
    try {
      final callable = _functions.httpsCallable('submitGuess');
      final result = await callable.call<Map<String, dynamic>>({
        'date': date,
        'drawerId': drawerId,
        'guess': guess,
      });
      final data = result.data;
      return (
        correct: (data['correct'] as bool?) ?? false,
        attempts: List<String>.from(data['attempts'] as List? ?? const []),
        finished: (data['finished'] as bool?) ?? false,
        solvedOnAttempt: (data['solvedOnAttempt'] as num?)?.toInt(),
        revealedWord: data['revealedWord'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(_messageFor(e));
    }
  }

  String _messageFor(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'No one has that code';
      case 'invalid-argument':
        return e.message ?? 'That code is not valid';
      case 'failed-precondition':
        return e.message ?? "This drawing isn't ready to guess yet";
      case 'unauthenticated':
        return 'Please sign in to add friends';
      case 'already-exists':
        return e.message ?? 'You are already friends';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}
