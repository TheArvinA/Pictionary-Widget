import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? fcmToken;
  final String inviteCode;
  final List<String> friendIds;
  final int streakCount;
  final String? lastPlayedDate;

  const AppUser({
    required this.uid,
    required this.displayName,
    required this.inviteCode,
    this.photoUrl,
    this.fcmToken,
    this.friendIds = const [],
    this.streakCount = 0,
    this.lastPlayedDate,
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
    );
  }

  Map<String, dynamic> toFirestore() => {
        'displayName': displayName,
        'photoUrl': photoUrl,
        'fcmToken': fcmToken,
        'inviteCode': inviteCode,
        'friendIds': friendIds,
        'streakCount': streakCount,
        'lastPlayedDate': lastPlayedDate,
      };
}
