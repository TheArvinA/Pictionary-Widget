import 'package:cloud_firestore/cloud_firestore.dart';

class DailyWords {
  final String date;
  final List<String> wordChoices;

  const DailyWords({
    required this.date,
    required this.wordChoices,
  });

  factory DailyWords.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return DailyWords(
      date: doc.id,
      wordChoices: List<String>.from(data['wordChoices'] as List? ?? const []),
    );
  }
}
