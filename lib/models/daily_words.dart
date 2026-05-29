import 'package:cloud_firestore/cloud_firestore.dart';

class DailyWords {
  final String date;
  final List<String> wordChoices;
  final DateTime? generatedAt;

  const DailyWords({
    required this.date,
    required this.wordChoices,
    this.generatedAt,
  });

  factory DailyWords.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return DailyWords(
      date: doc.id,
      wordChoices: List<String>.from(data['wordChoices'] as List? ?? const []),
      generatedAt: (data['generatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
