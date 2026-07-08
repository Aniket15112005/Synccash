// lib/features/daily/data/repositories/daily_repository_impl.dart
//
// IMPORTANT — data isolation:
// All reads/writes here target `cashbooks/{cashbookId}/daily_entries`, a
// subcollection that is completely separate from `cashbooks/{cashbookId}/
// transactions`. Unlike TransactionRepositoryImpl, this repository never
// reads or updates the parent cashbook document's `totalBalance`,
// `totalIncome`, or `totalExpense` fields — so Daily entries can never affect
// the main dashboard's balance, history, or any other part of the app.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:synccash/features/daily/data/models/daily_entry_model.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';
import 'package:synccash/features/daily/domain/repositories/daily_repository.dart';

class DailyRepositoryImpl implements DailyRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String cashbookId) {
    return _firestore
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('daily_entries');
  }

  @override
  Future<void> addEntry(DailyEntryEntity entry) async {
    final ref = _col(entry.cashbookId).doc();
    final model = DailyEntryModel(
      entryId: ref.id,
      cashbookId: entry.cashbookId,
      createdBy: entry.createdBy,
      creatorName: entry.creatorName,
      createdAt: entry.createdAt,
      amount: entry.amount,
      type: entry.type,
      description: entry.description,
    );
    await ref.set(model.toJson());
  }

  @override
  Future<void> updateEntry(DailyEntryEntity entry) async {
    await _col(entry.cashbookId).doc(entry.entryId).update({
      'amount': entry.amount,
      'type': entry.type,
      'description': entry.description,
      'createdAt': Timestamp.fromDate(entry.createdAt),
      if (entry.lastEditedBy != null) 'lastEditedBy': entry.lastEditedBy,
    });
  }

  @override
  Future<void> deleteEntry(DailyEntryEntity entry) async {
    await _col(entry.cashbookId).doc(entry.entryId).delete();
  }

  @override
  Stream<List<DailyEntryEntity>> getEntriesStream(
    String cashbookId, {
    int limit = 0,
  }) {
    var query =
        _col(cashbookId).orderBy('createdAt', descending: true);
    if (limit > 0) query = query.limit(limit);

    return query.snapshots().map(
          (snap) => snap.docs
              .map<DailyEntryEntity>(
                  (d) => DailyEntryModel.fromFirestore(d))
              .toList(),
        );
  }
}
