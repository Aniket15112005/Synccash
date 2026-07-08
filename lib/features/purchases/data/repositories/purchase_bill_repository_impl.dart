// lib/features/purchases/data/repositories/purchase_bill_repository_impl.dart
//
// Mirrors lib/features/sales/data/repositories/sale_bill_repository_impl.dart
// Firestore layout: cashbooks/{cashbookId}/purchase_bills/{autoId}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/purchase_bill_entity.dart';
import '../models/purchase_bill_model.dart';

class PurchaseBillRepositoryImpl {
  final FirebaseFirestore _db;
  PurchaseBillRepositoryImpl({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference _col(String cashbookId) => _db
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('purchase_bills');

  /// Streams every purchase bill in the cashbook (used for the client list,
  /// search suggestions, and the description-picker party-name union).
  Stream<List<PurchaseBillEntity>> watchAllBills(String cashbookId) {
    return _col(cashbookId).snapshots().map(
          (snap) =>
              snap.docs.map((d) => PurchaseBillModel.fromFirestore(d)).toList(),
        );
  }

  /// Streams only the bills belonging to [clientName], newest first.
  Stream<List<PurchaseBillEntity>> watchBillsForClient(
    String cashbookId,
    String clientName,
  ) {
    return _col(cashbookId)
        .where('clientName', isEqualTo: clientName)
        .snapshots()
        .map((snap) {
      final bills =
          snap.docs.map((d) => PurchaseBillModel.fromFirestore(d)).toList();
      bills.sort((a, b) => b.billDate.compareTo(a.billDate));
      return bills;
    });
  }

  /// Streams every bill belonging to [clientName], oldest first (FIFO order).
  /// NOTE: this intentionally does NOT filter by a stored "billStatus" field.
  /// Whether a bill is pending/partial/settled is always computed live by the
  /// UI from linked expense transactions (see PurchaseBillActions and
  /// PurchaseBillNoDropdownField) — mirrors how the Sales feature treats
  /// billStatus as informational only, never as the source of truth for the
  /// remaining amount.
  Stream<List<PurchaseBillEntity>> watchPendingBillsByClientName(
    String cashbookId,
    String clientName,
  ) {
    return _col(cashbookId)
        .where('clientName', isEqualTo: clientName)
        .snapshots()
        .map((snap) {
      final bills =
          snap.docs.map((d) => PurchaseBillModel.fromFirestore(d)).toList();
      bills.sort((a, b) => a.billDate.compareTo(b.billDate)); // FIFO
      return bills;
    });
  }

  Future<PurchaseBillEntity?> getBill(String cashbookId, String billId) async {
    final doc = await _col(cashbookId).doc(billId).get();
    if (!doc.exists) return null;
    return PurchaseBillModel.fromFirestore(doc);
  }

  Future<String> addBill(String cashbookId, PurchaseBillEntity bill) async {
    final docRef = _col(cashbookId).doc();
    final model = PurchaseBillModel(
      purchaseBillId: docRef.id,
      clientName: bill.clientName,
      billNumber: bill.billNumber,
      billAmount: bill.billAmount,
      billDate: bill.billDate,
      billNote: bill.billNote,
      billCreatedAt: bill.billCreatedAt,
      billCreatedBy: bill.billCreatedBy,
      billCreatedByName: bill.billCreatedByName,
      billStatus: bill.billStatus,
    );
    await docRef.set(model.toFirestore());
    return docRef.id;
  }

  Future<void> updateBill(String cashbookId, PurchaseBillEntity bill) async {
    final model = PurchaseBillModel(
      purchaseBillId: bill.purchaseBillId,
      clientName: bill.clientName,
      billNumber: bill.billNumber,
      billAmount: bill.billAmount,
      billDate: bill.billDate,
      billNote: bill.billNote,
      billCreatedAt: bill.billCreatedAt,
      billCreatedBy: bill.billCreatedBy,
      billCreatedByName: bill.billCreatedByName,
      billStatus: bill.billStatus,
    );
    await _col(cashbookId)
        .doc(bill.purchaseBillId)
        .set(model.toFirestore(), SetOptions(merge: true));
  }

  Future<void> updateBillStatus(
    String cashbookId,
    String billId,
    String status,
  ) async {
    await _col(cashbookId).doc(billId).update({'billStatus': status});
  }

  /// Saves (or clears) the Firebase Storage download URL for a bill's
  /// attached invoice image/PDF. Pass [imageUrl] as null to remove.
  Future<void> updateBillImageUrl(
    String cashbookId,
    String billId,
    String? imageUrl,
  ) async {
    if (imageUrl == null) {
      await _col(cashbookId).doc(billId).update({
        'billImageUrl': FieldValue.delete(),
      });
    } else {
      await _col(cashbookId).doc(billId).update({'billImageUrl': imageUrl});
    }
  }

  Future<void> deleteBill(String cashbookId, String billId) async {
    await _col(cashbookId).doc(billId).delete();
  }
}
