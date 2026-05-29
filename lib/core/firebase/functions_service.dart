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

  String _messageFor(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'No one has that code';
      case 'invalid-argument':
        return e.message ?? 'That code is not valid';
      case 'unauthenticated':
        return 'Please sign in to add friends';
      case 'already-exists':
        return e.message ?? 'You are already friends';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}
