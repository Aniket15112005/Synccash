import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Stores documents belonging to one purchase-payment transaction.
///
/// Files are kept under the transaction key instead of the bill key because a
/// single bill can have multiple payments (and therefore multiple receipts and
/// payment proofs).
class PaymentStorageService {
  final FirebaseStorage _storage;

  PaymentStorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  Future<String> uploadPaymentFile({
    required Uint8List bytes,
    required String cashbookId,
    required String transactionKey,
    required String fileName,
    required String contentType,
    required String folder,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final ref = _storage
        .ref()
        .child(folder)
        .child(cashbookId)
        .child(transactionKey)
        .child(safeName);

    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return task.ref.getDownloadURL();
  }

  /// Deletes a previously saved payment document. Cleanup is best-effort so a
  /// stale/invalid download URL cannot prevent the Firestore transaction edit
  /// from completing.
  Future<void> deletePaymentFile(String? downloadUrl) async {
    if (downloadUrl == null || downloadUrl.isEmpty) return;
    try {
      await _storage.refFromURL(downloadUrl).delete();
    } catch (_) {
      // The Firestore reference is still removed by the caller.
    }
  }
}