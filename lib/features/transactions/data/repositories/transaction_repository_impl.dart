import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:synccash/features/transactions/data/models/transaction_model.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/domain/repositories/transaction_repository.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isIncome(String type) => type.toLowerCase().trim() == 'income';

  Map<String, dynamic> _counterDeltas({
    required double balance,
    required double income,
    required double expense,
  }) {
    return {
      'totalBalance': FieldValue.increment(balance),
      'totalIncome': FieldValue.increment(income),
      'totalExpense': FieldValue.increment(expense),
    };
  }

  @override
  Future<void> addTransaction(TransactionEntity tx) async {
    final txRef = _firestore
        .collection('cashbooks')
        .doc(tx.cashbookId)
        .collection('transactions')
        .doc();
    final cashbookRef = _firestore.collection('cashbooks').doc(tx.cashbookId);

    final model = TransactionModel(
      transactionId: txRef.id,
      cashbookId: tx.cashbookId,
      createdBy: tx.createdBy,
      creatorName: tx.creatorName,
      createdAt: tx.createdAt,
      amount: tx.amount,
      type: tx.type,
      category: tx.category,
      description: tx.description,
      linkedSaleBillId: tx.linkedSaleBillId,
      linkedPurchaseBillId: tx.linkedPurchaseBillId,
    );

    final batch = _firestore.batch();
    batch.set(txRef, model.toJson());

    final isIncome = _isIncome(tx.type);
    batch.update(
      cashbookRef,
      _counterDeltas(
        balance: isIncome ? tx.amount : -tx.amount,
        income: isIncome ? tx.amount : 0,
        expense: isIncome ? 0 : tx.amount,
      ),
    );

    // Firestore batches are persisted locally and uploaded automatically when
    // the device reconnects. Do not replace this with runTransaction():
    // Firestore transactions cannot complete while offline.
    await batch.commit();
  }

  @override
  Future<void> deleteTransaction(TransactionEntity tx) async {
    final txRef = _firestore
        .collection('cashbooks')
        .doc(tx.cashbookId)
        .collection('transactions')
        .doc(tx.transactionId);
    final cashbookRef = _firestore.collection('cashbooks').doc(tx.cashbookId);

    final batch = _firestore.batch();
    batch.delete(txRef);

    final isIncome = _isIncome(tx.type);
    batch.update(
      cashbookRef,
      _counterDeltas(
        balance: isIncome ? -tx.amount : tx.amount,
        income: isIncome ? -tx.amount : 0,
        expense: isIncome ? 0 : -tx.amount,
      ),
    );

    await batch.commit();
  }

  @override
  Future<void> updateTransaction(
    TransactionEntity tx, {
    TransactionEntity? previous,
  }) async {
    final txRef = _firestore
        .collection('cashbooks')
        .doc(tx.cashbookId)
        .collection('transactions')
        .doc(tx.transactionId);
    final cashbookRef = _firestore.collection('cashbooks').doc(tx.cashbookId);

    // The edit screen passes the locally visible previous value. This avoids
    // a network read, which is the part that makes Firestore transactions fail
    // offline. If no previous value is available, only the document fields are
    // updated and the counters are left unchanged.
    final old = previous;
    final oldIsIncome = old != null && _isIncome(old.type);
    final newIsIncome = _isIncome(tx.type);

    final oldBalance = old == null ? 0.0 : (oldIsIncome ? old.amount : -old.amount);
    final newBalance = newIsIncome ? tx.amount : -tx.amount;
    final oldIncome = old == null || !oldIsIncome ? 0.0 : old.amount;
    final newIncome = newIsIncome ? tx.amount : 0.0;
    final oldExpense = old == null || oldIsIncome ? 0.0 : old.amount;
    final newExpense = newIsIncome ? 0.0 : tx.amount;

    final batch = _firestore.batch();
    batch.update(txRef, {
      'amount': tx.amount,
      'type': tx.type,
      'category': tx.category,
      'description': tx.description,
      'createdAt': Timestamp.fromDate(tx.createdAt),
      'createdBy': tx.createdBy,
      'creatorName': tx.creatorName,
      'lastEditedBy': tx.lastEditedBy,
      'linkedSaleBillId': tx.linkedSaleBillId ?? FieldValue.delete(),
      'linkedPurchaseBillId': tx.linkedPurchaseBillId ?? FieldValue.delete(),
    });

    if (old != null) {
      batch.update(
        cashbookRef,
        _counterDeltas(
          balance: newBalance - oldBalance,
          income: newIncome - oldIncome,
          expense: newExpense - oldExpense,
        ),
      );
    }

    await batch.commit();
  }

  // limit:0 skips .limit() so all records are fetched.
  @override
  Stream<List<TransactionEntity>> getTransactionsStream(
    String cashbookId, {
    int limit = 5000,
  }) {
    var query = _firestore
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .orderBy('createdAt', descending: true);

    if (limit > 0) query = query.limit(limit);

    return query
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs
            .map<TransactionEntity>(
                (d) => TransactionModel.fromFirestore(d))
            .toList());
  }
}
