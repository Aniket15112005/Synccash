import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../data/repositories/sale_bill_repository_impl.dart';
import '../../domain/entities/sale_bill_entity.dart';

// ── internal repo provider ───────────────────────────────────────────────────

final _saleBillRepoProvider = Provider<SaleBillRepositoryImpl>(
  (ref) => SaleBillRepositoryImpl(FirebaseFirestore.instance),
);

// ── search state ─────────────────────────────────────────────────────────────

class SaleBillSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void update(String query) => state = query;
}

final saleBillSearchProvider =
    NotifierProvider<SaleBillSearchNotifier, String>(
  SaleBillSearchNotifier.new,
);

// ── bills stream with search filter ──────────────────────────────────────────

final filteredSaleBillsProvider =
    StreamProvider.autoDispose<List<SaleBillEntity>>((ref) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  final search = ref.watch(saleBillSearchProvider).toLowerCase().trim();
  final repo = ref.watch(_saleBillRepoProvider);

  if (cashbookId == null) return Stream.value([]);

  return repo.watchBills(cashbookId).map((bills) {
    if (search.isEmpty) return bills;
    return bills
        .where((b) =>
            b.partyName.toLowerCase().contains(search) ||
            b.billNumber.toLowerCase().contains(search))
        .toList();
  });
});

// ── linked transactions for bill detail screen ───────────────────────────────
// FIX: Removed .orderBy('createdAt', descending: true) — that combination with
// .where() required a Firestore composite index that may not exist, causing the
// stream to error silently and the loading spinner to stay forever.
// Sorting is now done in Dart after the snapshot arrives.

class LinkedTransactionItem {
  final String   transactionId;
  final double   amount;
  final DateTime createdAt;
  final String   description;

  const LinkedTransactionItem({
    required this.transactionId,
    required this.amount,
    required this.createdAt,
    required this.description,
  });
}

final billLinkedTransactionsProvider = StreamProvider.autoDispose
    .family<List<LinkedTransactionItem>, String>((ref, compositeKey) {
  final sep = compositeKey.indexOf('|');
  if (sep < 0) return Stream.value([]);
  final cashbookId = compositeKey.substring(0, sep);
  final billId     = compositeKey.substring(sep + 1);

  if (cashbookId.isEmpty || billId.isEmpty) return Stream.value([]);

  // FIX: query ONLY by linkedSaleBillId — exact match, no orderBy needed.
  // Falls back to description match in the bill detail screen for older entries.
  return FirebaseFirestore.instance
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('transactions')
      .where('linkedSaleBillId', isEqualTo: billId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((doc) => LinkedTransactionItem(
                  transactionId:
                      doc['transactionId'] as String? ?? doc.id,
                  amount:
                      (doc['amount'] as num?)?.toDouble() ?? 0.0,
                  createdAt:
                      (doc['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime.now(),
                  description: doc['description'] as String? ?? '',
                ))
            .toList();
        // Sort newest-first in Dart — avoids needing a composite index
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
});

// ── CRUD actions notifier ─────────────────────────────────────────────────────

class SaleBillActionsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> addBill({
    required String   cashbookId,
    required String   partyName,
    required String   billNumber,
    required double   billTotal,
    required DateTime billDate,
    String?           billNote,
    required String   createdBy,
    required String   createdByName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final data = <String, dynamic>{
        'partyName':         partyName,
        'billNumber':        billNumber,
        'billTotal':         billTotal,
        'billDate':          Timestamp.fromDate(billDate),
        'billNote':          billNote,
        'billCreatedAt':     FieldValue.serverTimestamp(),
        'billCreatedBy':     createdBy,
        'billCreatedByName': createdByName,
        'billStatus':        'pending',
      };
      await SaleBillRepositoryImpl(FirebaseFirestore.instance)
          .addBill(cashbookId, data);
    });
  }

  Future<void> settleBill({
    required String cashbookId,
    required String billId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await SaleBillRepositoryImpl(FirebaseFirestore.instance)
          .settleBill(cashbookId, billId);
    });
  }

  /// Records a payment for a specific bill.
  /// Writes a standard income transaction with [linkedSaleBillId] so that the
  /// bill detail screen can match it exactly without relying on description text.
  Future<void> recordPayment({
    required String cashbookId,
    required String billId,
    required String billNumber,
    required String partyName,
    required double amount,
    required String createdBy,
    required String createdByName,
    String          note = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db     = FirebaseFirestore.instance;
      final docRef = db
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('transactions')
          .doc();

      final desc = note.trim().isNotEmpty
          ? note.trim()
          : 'Payment: $billNumber – $partyName';

      await docRef.set({
        'transactionId':    docRef.id,
        'cashbookId':       cashbookId,
        'type':             'income',
        'amount':           amount,
        'description':      desc,
        'category':         'Sales',
        'linkedSaleBillId': billId,
        'createdBy':        createdBy,
        'creatorName':      createdByName,
        'createdAt':        FieldValue.serverTimestamp(),
      });
    });
  }

  /// Settles a bill and optionally records a final payment transaction for the
  /// remaining amount so the bill's received total becomes equal to the bill total.
  Future<void> settleWithPayment({
    required String cashbookId,
    required String billId,
    required String billNumber,
    required String partyName,
    required double remaining,
    required String createdBy,
    required String createdByName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db = FirebaseFirestore.instance;

      // If there's still an outstanding amount, record it as a payment first
      if (remaining > 0) {
        final docRef = db
            .collection('cashbooks')
            .doc(cashbookId)
            .collection('transactions')
            .doc();
        await docRef.set({
          'transactionId':    docRef.id,
          'cashbookId':       cashbookId,
          'type':             'income',
          'amount':           remaining,
          'description':      'Final settlement: $billNumber – $partyName',
          'category':         'Sales',
          'linkedSaleBillId': billId,
          'createdBy':        createdBy,
          'creatorName':      createdByName,
          'createdAt':        FieldValue.serverTimestamp(),
        });
      }

      // Mark the bill as settled
      await SaleBillRepositoryImpl(db).settleBill(cashbookId, billId);
    });
  }
}

final saleBillActionsProvider =
    AsyncNotifierProvider<SaleBillActionsNotifier, void>(
  SaleBillActionsNotifier.new,
);
