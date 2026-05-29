import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  StorageService(this._storage);
  final FirebaseStorage _storage;

  Future<String> uploadDrawing({
    required String date,
    required String drawerId,
    required Uint8List pngBytes,
  }) async {
    final ref = _storage.ref('rounds/$date/$drawerId.png');
    await ref.putData(
      pngBytes,
      SettableMetadata(contentType: 'image/png'),
    );
    return ref.getDownloadURL();
  }
}
