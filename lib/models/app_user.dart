import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifetime guessing stats, aggregated server-side on the user doc.
class GuessStats {
  final int correct;
  final int failed;
  final int win1;
  final int win2;
  final int win3;

  const GuessStats({
    this.correct = 0,
    this.failed = 0,
    this.win1 = 0,
    this.win2 = 0,
    this.win3 = 0,
  });

  factory GuessStats.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const GuessStats();
    int read(String k) => (m[k] as num?)?.toInt() ?? 0;
    return GuessStats(
      correct: read('correct'),
      failed: read('failed'),
      win1: read('win1'),
      win2: read('win2'),
      win3: read('win3'),
    );
  }

  int get total => correct + failed;
  bool get isEmpty => total == 0;
}

class AppUser {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? fcmToken;
  final String inviteCode;
  final List<String> friendIds;
  final int streakCount;
  final String? lastPlayedDate;
  final GuessStats guessStats;

  const AppUser({
    required this.uid,
    required this.displayName,
    required this.inviteCode,
    this.photoUrl,
    this.fcmToken,
    this.friendIds = const [],
    this.streakCount = 0,
    this.lastPlayedDate,
    this.guessStats = const GuessStats(),
  });

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AppUser(
      uid: doc.id,
      displayName: (data['displayName'] as String?) ?? 'Player',
      photoUrl: data['photoUrl'] as String?,
      fcmToken: data['fcmToken'] as String?,
      inviteCode: (data['inviteCode'] as String?) ?? '',
      friendIds: List<String>.from(data['friendIds'] as List? ?? const []),
      streakCount: (data['streakCount'] as num?)?.toInt() ?? 0,
      lastPlayedDate: data['lastPlayedDate'] as String?,
      guessStats: GuessStats.fromMap(data['guessStats'] as Map<String, dynamic>?),
    );
  }
}
