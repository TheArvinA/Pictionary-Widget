import 'package:cloud_firestore/cloud_firestore.dart';

class Guess {
  final String guesserId;
  final String drawerId;
  final List<String> attempts;
  final bool correct;
  final int? solvedOnAttempt;
  final String? revealedWord;
  final DateTime? completedAt;

  const Guess({
    required this.guesserId,
    required this.drawerId,
    this.attempts = const [],
    this.correct = false,
    this.solvedOnAttempt,
    this.revealedWord,
    this.completedAt,
  });

  static String idFor({required String guesserId, required String drawerId}) =>
      '${guesserId}_$drawerId';

  factory Guess.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Guess(
      guesserId: (data['guesserId'] as String?) ?? '',
      drawerId: (data['drawerId'] as String?) ?? '',
      attempts: List<String>.from(data['attempts'] as List? ?? const []),
      correct: (data['correct'] as bool?) ?? false,
      solvedOnAttempt: (data['solvedOnAttempt'] as num?)?.toInt(),
      revealedWord: data['revealedWord'] as String?,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }
}
