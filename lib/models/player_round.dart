import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerRound {
  final String drawerId;
  final String? chosenWord;
  final String? drawingUrl;
  final bool hasSubmittedDrawing;
  final DateTime? submittedAt;

  const PlayerRound({
    required this.drawerId,
    this.chosenWord,
    this.drawingUrl,
    this.hasSubmittedDrawing = false,
    this.submittedAt,
  });

  factory PlayerRound.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return PlayerRound(
      drawerId: doc.id,
      chosenWord: data['chosenWord'] as String?,
      drawingUrl: data['drawingUrl'] as String?,
      hasSubmittedDrawing: (data['hasSubmittedDrawing'] as bool?) ?? false,
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'chosenWord': chosenWord,
        'drawingUrl': drawingUrl,
        'hasSubmittedDrawing': hasSubmittedDrawing,
        if (submittedAt != null)
          'submittedAt': Timestamp.fromDate(submittedAt!),
      };
}
