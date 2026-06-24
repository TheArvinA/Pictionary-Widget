import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerRound {
  final String drawerId;
  final String? drawingUrl;
  final bool hasSubmittedDrawing;

  const PlayerRound({
    required this.drawerId,
    this.drawingUrl,
    this.hasSubmittedDrawing = false,
  });

  factory PlayerRound.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return PlayerRound(
      drawerId: doc.id,
      drawingUrl: data['drawingUrl'] as String?,
      hasSubmittedDrawing: (data['hasSubmittedDrawing'] as bool?) ?? false,
    );
  }
}
