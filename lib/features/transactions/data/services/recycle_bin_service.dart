import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:synccash/features/transactions/domain/entities/deleted_bill_entity.dart';
import 'package:synccash/features/transactions/domain/entities/deleted_transaction_entity.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/sales/domain/entities/sale_bill_entity.dart';

class RecycleBinService {
  static final _db = FirebaseFirestore.instance;

  // ── Transaction collections ───────────────────────────────────────────────

  static CollectionReference _deleted(String cashbookId) => _db
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('deleted_transactions');

  static CollectionReference _active(String cashbookId) => _db
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('transactions');

  // ── Bill collections ──────────────────────────────────────────────────────

  static CollectionReference _deletedBills(String cashbookId) => _db
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('deleted_bills');

  static CollectionReference _activeBills(String cashbookId) => _db
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('sale_bills');

  // Returns the cashbook document reference for a given cashbook.
  static DocumentReference _cashbook(String cashbookId) =>
      _db.collection('cashbooks').doc(cashbookId);

  // Computes the balance delta when removing a transaction from the active totals.
  // income entry removed  → totalIncome ↓, totalBalance ↓
  // expense entry removed → totalExpense ↓, totalBalance ↑
  static Map<String, dynamic> _decrementTotals(
      String type, double amount) {
    if (type == 'income') {
      return {
        'totalIncome': FieldValue.increment(-amount),
        'totalBalance': FieldValue.increment(-amount),
      };
    } else {
      return {
        'totalExpense': FieldValue.increment(-amount),
        'totalBalance': FieldValue.increment(amount),
      };
    }
  }

  // Reverse of the above — used when restoring.
  static Map<String, dynamic> _incrementTotals(
      String type, double amount) {
    if (type == 'income') {
      return {
        'totalIncome': FieldValue.increment(amount),
        'totalBalance': FieldValue.increment(amount),
      };
    } else {
      return {
        'totalExpense': FieldValue.increment(amount),
        'totalBalance': FieldValue.increment(-amount),
      };
    }
  }

  // ── Soft-delete transaction: move from transactions → deleted_transactions ─

  static Future<void> softDelete(TransactionEntity tx) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final batch = _db.batch();

    // 1. Write to recycle bin
    batch.set(_deleted(tx.cashbookId).doc(tx.transactionId), {
      'cashbookId':   tx.cashbookId,
      'createdBy':    tx.createdBy,
      'creatorName':  tx.creatorName,
      'createdAt':    Timestamp.fromDate(tx.createdAt),
      'amount':       tx.amount,
      'type':         tx.type,
      'category':     tx.category,
      'description':  tx.description,
      if (tx.lastEditedBy != null) 'lastEditedBy': tx.lastEditedBy,
      'deletedAt':    FieldValue.serverTimestamp(),
      'deletedBy':    uid,
    });

    // 2. Remove from active transactions
    batch.delete(_active(tx.cashbookId).doc(tx.transactionId));

    // 3. Subtract from cashbook totals so the balance card updates instantly
    batch.update(_cashbook(tx.cashbookId),
        _decrementTotals(tx.type, tx.amount));

    await batch.commit();
  }

  // ── Restore transaction: move from deleted_transactions → transactions ─────

  static Future<void> restore(DeletedTransactionEntity tx) async {
    final batch = _db.batch();

    // 1. Put back into active transactions
    batch.set(
      _active(tx.cashbookId).doc(tx.transactionId),
      tx.toRestoreMap(),
    );

    // 2. Remove from recycle bin
    batch.delete(_deleted(tx.cashbookId).doc(tx.transactionId));

    // 3. Add back to cashbook totals so the balance card updates instantly
    batch.update(_cashbook(tx.cashbookId),
        _incrementTotals(tx.type, tx.amount));

    await batch.commit();
  }

  // ── Restore all transactions ───────────────────────────────────────────────

  static Future<void> restoreAll(List<DeletedTransactionEntity> items) async {
    if (items.isEmpty) return;

    final batch = _db.batch();

    // Aggregate the total delta across all items so we make a single
    // cashbook document update instead of one per transaction.
    final Map<String, Map<String, double>> deltas = {};

    for (final tx in items) {
      batch.set(
        _active(tx.cashbookId).doc(tx.transactionId),
        tx.toRestoreMap(),
      );
      batch.delete(_deleted(tx.cashbookId).doc(tx.transactionId));

      // Accumulate deltas per cashbook (handles edge case of multi-cashbook list)
      final d = deltas.putIfAbsent(
          tx.cashbookId, () => {'income': 0.0, 'expense': 0.0});
      if (tx.type == 'income') {
        d['income'] = (d['income'] ?? 0) + tx.amount;
      } else {
        d['expense'] = (d['expense'] ?? 0) + tx.amount;
      }
    }

    // Apply one cashbook update per cashbook
    for (final entry in deltas.entries) {
      final income  = entry.value['income']  ?? 0.0;
      final expense = entry.value['expense'] ?? 0.0;
      batch.update(_cashbook(entry.key), {
        'totalIncome':  FieldValue.increment(income),
        'totalExpense': FieldValue.increment(expense),
        'totalBalance': FieldValue.increment(income - expense),
      });
    }

    await batch.commit();
  }

  // ── Permanent delete transaction (from recycle bin) ───────────────────────
  //
  // NOTE: No cashbook update needed here. The transaction was already
  // excluded from totals when it was soft-deleted. Permanently removing
  // it from the bin does not affect the live balance.

  static Future<void> permanentDelete(DeletedTransactionEntity tx) async {
    await _deleted(tx.cashbookId).doc(tx.transactionId).delete();
  }

  // ── Delete all transactions (permanent, from recycle bin) ─────────────────
  //
  // Same reasoning as permanentDelete — totals were already adjusted on
  // soft-delete, so no cashbook update is required here.

  static Future<void> deleteAll(List<DeletedTransactionEntity> items) async {
    if (items.isEmpty) return;
    final batch = _db.batch();
    for (final tx in items) {
      batch.delete(_deleted(tx.cashbookId).doc(tx.transactionId));
    }
    await batch.commit();
  }

  // ── Stream transactions ───────────────────────────────────────────────────

  static Stream<List<DeletedTransactionEntity>> stream(String cashbookId) {
    return _deleted(cashbookId)
        .orderBy('deletedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DeletedTransactionEntity.fromFirestore(d))
            .where((tx) => !tx.isExpired)
            .toList());
  }

  // ── Cleanup expired transactions (call on recycle bin open) ───────────────

  static Future<void> cleanupExpired(String cashbookId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 15)),
    );
    final expired = await _deleted(cashbookId)
        .where('deletedAt', isLessThan: cutoff)
        .get();

    if (expired.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in expired.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Bill soft-delete / restore / permanent-delete
  //
  //  Bills live in sale_bills; deleted copies go to deleted_bills.
  //  Bills do NOT affect cashbook totalIncome / totalExpense / totalBalance,
  //  so no cashbook document update is needed for any bill operation.
  // ─────────────────────────────────────────────────────────────────────────

  // ── Soft-delete bill: move from sale_bills → deleted_bills ────────────────

  static Future<void> softDeleteBill(
      SaleBillEntity bill, String cashbookId) async {
    final uid   = FirebaseAuth.instance.currentUser?.uid;
    final batch = _db.batch();

    // 1. Write to bill recycle bin
    batch.set(_deletedBills(cashbookId).doc(bill.saleBillId), {
      'cashbookId':        cashbookId,
      'partyName':         bill.partyName,
      'billNumber':        bill.billNumber,
      'billTotal':         bill.billTotal,
      'billDate':          Timestamp.fromDate(bill.billDate),
      if (bill.billNote != null) 'billNote': bill.billNote,
      'billStatus':        bill.billStatus,
      'billCreatedBy':     bill.billCreatedBy,
      'billCreatedByName': bill.billCreatedByName,
      'billCreatedAt':     Timestamp.fromDate(bill.billCreatedAt),
      'deletedAt':         FieldValue.serverTimestamp(),
      'deletedBy':         uid,
    });

    // 2. Remove from active sale_bills
    batch.delete(_activeBills(cashbookId).doc(bill.saleBillId));

    await batch.commit();
  }

  // ── Restore bill: move from deleted_bills → sale_bills ────────────────────

  static Future<void> restoreBill(DeletedBillEntity bill) async {
    final batch = _db.batch();

    // 1. Put back into active sale_bills
    batch.set(
      _activeBills(bill.cashbookId).doc(bill.billId),
      bill.toRestoreMap(),
    );

    // 2. Remove from bill recycle bin
    batch.delete(_deletedBills(bill.cashbookId).doc(bill.billId));

    await batch.commit();
  }

  // ── Permanent delete bill (from bill recycle bin) ─────────────────────────

  static Future<void> permanentDeleteBill(DeletedBillEntity bill) async {
    await _deletedBills(bill.cashbookId).doc(bill.billId).delete();
  }

  // ── Delete all bills (permanent, from bill recycle bin) ───────────────────

  static Future<void> deleteAllBills(List<DeletedBillEntity> items) async {
    if (items.isEmpty) return;
    final batch = _db.batch();
    for (final bill in items) {
      batch.delete(_deletedBills(bill.cashbookId).doc(bill.billId));
    }
    await batch.commit();
  }

  // ── Stream deleted bills ──────────────────────────────────────────────────

  static Stream<List<DeletedBillEntity>> streamBills(String cashbookId) {
    return _deletedBills(cashbookId)
        .orderBy('deletedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DeletedBillEntity.fromFirestore(d))
            .where((bill) => !bill.isExpired)
            .toList());
  }

  // ── Cleanup expired bills (call on recycle bin open) ─────────────────────

  static Future<void> cleanupExpiredBills(String cashbookId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 15)),
    );
    final expired = await _deletedBills(cashbookId)
        .where('deletedAt', isLessThan: cutoff)
        .get();

    if (expired.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in expired.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
