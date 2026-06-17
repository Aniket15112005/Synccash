import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/transactions/data/services/recycle_bin_service.dart';
import '../../data/models/sale_bill_model.dart';
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
    StreamProvider<List<SaleBillEntity>>((ref) {
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

      await SaleBillRepositoryImpl(db).settleBill(cashbookId, billId);
    });
  }

  /// Soft-deletes a sale bill: moves it to the recycle bin (deleted_bills
  /// collection) where it stays for 15 days before permanent removal.
  Future<void> deleteBill({
    required String cashbookId,
    required String billId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final doc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('sale_bills')
          .doc(billId)
          .get();
      if (!doc.exists) return;
      final bill = SaleBillModel.fromFirestore(doc);
      await RecycleBinService.softDeleteBill(bill, cashbookId);
    });
  }

  /// Updates editable fields on a sale bill.
  Future<void> editBill({
    required String   cashbookId,
    required String   billId,
    required String   billNumber,
    required double   billTotal,
    required DateTime billDate,
    String?           billNote,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('sale_bills')
          .doc(billId)
          .update({
        'billNumber': billNumber,
        'billTotal':  billTotal,
        'billDate':   Timestamp.fromDate(billDate),
        'billNote':   billNote,
      });
    });
  }

  // ── Helper: shared data-fetch used by both overflow methods ─────────────────

  Future<_OverflowData> _fetchOverflowData({
    required FirebaseFirestore db,
    required String cashbookId,
    required String partyName,
  }) async {
    final partyLow = partyName.trim().toLowerCase();
    final cashRef  = db.collection('cashbooks').doc(cashbookId);

    // Bills for this party, sorted oldest first (case-insensitive)
    final billsSnap = await cashRef
        .collection('sale_bills')
        .get();

    final allBills = billsSnap.docs
        .where((doc) =>
            (doc.data()['partyName'] as String? ?? '')
                .trim()
                .toLowerCase() ==
            partyLow)
        .map((doc) {
      final d = doc.data();
      return _BillSnapshot(
        id:        d['saleBillId'] as String? ?? doc.id,
        total:     (d['billTotal'] as num?)?.toDouble() ?? 0.0,
        createdAt: (d['billCreatedAt'] as Timestamp?)?.toDate() ?? DateTime(2000),
        status:    d['billStatus'] as String? ?? 'pending',
      );
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Received amounts from all income transactions in this cashbook
    final txSnap = await cashRef
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .get();

    final receivedPerBill = <String, double>{};
    double obReceived = 0.0;

    for (final doc in txSnap.docs) {
      final raw      = doc.data();
      final linkedId = raw['linkedSaleBillId'] as String?;
      final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
      final desc     = (raw['description'] as String? ?? '').toLowerCase();
      if (linkedId != null && linkedId.isNotEmpty) {
        receivedPerBill[linkedId] = (receivedPerBill[linkedId] ?? 0.0) + amount;
      } else if (desc.contains(partyLow)) {
        obReceived += amount;
      }
    }

    // Opening balance from party document
    final partyDoc = await cashRef.collection('parties').doc(partyLow).get();
    final ob = (partyDoc.data()?['openingBalance'] as num?)?.toDouble() ?? 0.0;
    final obRemaining = (ob - obReceived).clamp(0.0, double.infinity);

    return _OverflowData(
      allBills:        allBills,
      receivedPerBill: receivedPerBill,
      obRemaining:     obRemaining,
    );
  }

  /// Records an income entry for a selected bill and automatically
  /// distributes any overflow amount to:
  ///   1. Opening balance (if still due)
  ///   2. Other pending bills for the same party (oldest first / FIFO)
  ///
  /// NOTE: This method intentionally does NOT change billStatus in Firestore.
  /// Bill settlement is only done through explicit user actions on the bill
  /// detail screen (settleBill / settleWithPayment). This prevents bills from
  /// getting stuck as "settled" if demo transactions are later deleted.
  Future<void> recordPaymentWithOverflow({
    required String   cashbookId,
    required String   selectedBillId,
    required String   partyName,
    required double   totalAmount,
    required String   description,
    required String   category,
    required String   createdBy,
    required String   createdByName,
    required DateTime createdAt,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db      = FirebaseFirestore.instance;
      final cashRef = db.collection('cashbooks').doc(cashbookId);
      final txColl  = cashRef.collection('transactions');

      final data = await _fetchOverflowData(
        db: db, cashbookId: cashbookId, partyName: partyName,
      );

      double left  = totalAmount;
      final batch  = db.batch();

      // isOb: when true, stamps isObPayment + obPartyName on the document
      void alloc({
        required String? linkedBillId,
        required double  amount,
        required String  desc,
        bool             isOb = false,
      }) {
        if (amount <= 0) return;
        final ref = txColl.doc();
        batch.set(ref, {
          'transactionId':    ref.id,
          'cashbookId':       cashbookId,
          'type':             'income',
          'amount':           amount,
          'description':      desc,
          'category':         category,
          'linkedSaleBillId': linkedBillId,
          'createdBy':        createdBy,
          'creatorName':      createdByName,
          'createdAt':        Timestamp.fromDate(createdAt),
          if (isOb) 'isObPayment': true,
          if (isOb) 'obPartyName': partyName.trim(),
        });
      }

      // 1. Selected bill first
      final selBill = data.allBills.firstWhere(
        (b) => b.id == selectedBillId,
        orElse: () => _BillSnapshot(
            id: selectedBillId, total: 0, createdAt: DateTime(2000), status: 'pending'),
      );
      final selRec = data.receivedPerBill[selectedBillId] ?? 0.0;
      final selRem = (selBill.total - selRec).clamp(0.0, double.infinity);
      final toSel  = left.clamp(0.0, selRem);
      left -= toSel;

      alloc(
        linkedBillId: selectedBillId,
        amount:       toSel,
        desc:         description.isNotEmpty ? description : 'Payment – $partyName',
      );

      // 2. Opening balance overflow
      if (left > 0 && data.obRemaining > 0) {
        final toOb = left.clamp(0.0, data.obRemaining);
        left -= toOb;
        // Description MUST contain partyName for _received['_unlinked'] detection
        alloc(
          linkedBillId: null,
          amount:       toOb,
          desc:         'Opening balance payment – $partyName',
          isOb:         true,
        );
      }

      // 3. Other pending bills (oldest first, skipping selected, skip if already fully received)
      // NOTE: Filter by actual remaining balance, NOT billStatus – stale 'settled' flags
      // (left over from previous code that auto-settled) would wrongly exclude bills.
      if (left > 0) {
        final others = data.allBills
            .where((b) {
              if (b.id == selectedBillId) return false;
              final rec = data.receivedPerBill[b.id] ?? 0.0;
              return (b.total - rec) > 0;
            })
            .toList();

        for (final bill in others) {
          if (left <= 0) break;
          final rec = data.receivedPerBill[bill.id] ?? 0.0;
          final rem = (bill.total - rec).clamp(0.0, double.infinity);
          if (rem <= 0) continue;

          final toThis = left.clamp(0.0, rem);
          left -= toThis;

          alloc(
            linkedBillId: bill.id,
            amount:       toThis,
            desc:         description.isNotEmpty ? description : 'Payment – $partyName',
          );
        }
      }

      await batch.commit();
    });
  }

  /// Records an OB (opening balance) income payment and automatically
  /// distributes any overflow to pending bills for the party (oldest first / FIFO).
  ///
  /// NOTE: Does NOT change billStatus in Firestore — same reasoning as above.
  Future<void> recordObPaymentWithOverflow({
    required String   cashbookId,
    required String   partyName,
    required double   totalAmount,
    required String   description,
    required String   category,
    required String   createdBy,
    required String   createdByName,
    required DateTime createdAt,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db      = FirebaseFirestore.instance;
      final cashRef = db.collection('cashbooks').doc(cashbookId);
      final txColl  = cashRef.collection('transactions');
      final partyLow = partyName.trim().toLowerCase();

      final data = await _fetchOverflowData(
        db: db, cashbookId: cashbookId, partyName: partyName,
      );

      double left  = totalAmount;
      final batch  = db.batch();

      // isOb: when true, stamps isObPayment + obPartyName on the document
      void alloc({
        required String? linkedBillId,
        required double  amount,
        required String  desc,
        bool             isOb = false,
      }) {
        if (amount <= 0) return;
        final ref = txColl.doc();
        batch.set(ref, {
          'transactionId':    ref.id,
          'cashbookId':       cashbookId,
          'type':             'income',
          'amount':           amount,
          'description':      desc,
          'category':         category,
          'linkedSaleBillId': linkedBillId,
          'createdBy':        createdBy,
          'creatorName':      createdByName,
          'createdAt':        Timestamp.fromDate(createdAt),
          if (isOb) 'isObPayment': true,
          if (isOb) 'obPartyName': partyName.trim(),
        });
      }

      // 1. Opening balance first
      final toOb = left.clamp(0.0, data.obRemaining);
      left -= toOb;

      // Ensure description always contains partyName for _received['_unlinked'] detection
      final obDesc = description.toLowerCase().contains(partyLow)
          ? description
          : '$description – $partyName';

      alloc(
        linkedBillId: null,
        amount:       toOb,
        desc:         obDesc,
        isOb:         true,
      );

      // 2. Overflow to pending bills (oldest first / FIFO, skip fully received ones)
      // NOTE: Filter by actual remaining balance, NOT billStatus – stale 'settled' flags
      // (left over from previous code that auto-settled) would wrongly exclude bills.
      if (left > 0) {
        final pendingBills = data.allBills
            .where((b) {
              final rec = data.receivedPerBill[b.id] ?? 0.0;
              return (b.total - rec) > 0;
            })
            .toList();

        for (final bill in pendingBills) {
          if (left <= 0) break;
          final rec = data.receivedPerBill[bill.id] ?? 0.0;
          final rem = (bill.total - rec).clamp(0.0, double.infinity);
          if (rem <= 0) continue;

          final toThis = left.clamp(0.0, rem);
          left -= toThis;

          alloc(
            linkedBillId: bill.id,
            amount:       toThis,
            desc:         description.isNotEmpty ? description : 'Payment – $partyName',
          );
        }
      }

      // 3. Remaining amount not covered by OB or bills (all-bills-paid, non-party desc, etc.)
      //    Always ensure at least one transaction is written so the income is never lost.
      if (left > 0) {
        alloc(
          linkedBillId: null,
          amount:       left,
          desc:         description.isNotEmpty ? description : 'Payment – $partyName',
        );
      }

      await batch.commit();
    });
  }
}

final saleBillActionsProvider =
    AsyncNotifierProvider<SaleBillActionsNotifier, void>(
  SaleBillActionsNotifier.new,
);

/// Maps billId → billNumber for all bills in the current cashbook.
/// Used by the transaction list and details sheet for quick, widget-local lookup.
final saleBillNumberMapProvider = StreamProvider<Map<String, String>>((ref) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  if (cashbookId == null) return Stream.value({});

  return FirebaseFirestore.instance
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('sale_bills')
      .snapshots()
      .map((snap) {
    final map = <String, String>{};
    for (final doc in snap.docs) {
      final id  = doc.data()['saleBillId'] as String? ?? doc.id;
      final num = doc.data()['billNumber'] as String? ?? '';
      if (id.isNotEmpty) map[id] = num;
    }
    return map;
  });
});

// ── Internal helpers used by overflow methods ─────────────────────────────────

class _BillSnapshot {
  final String   id;
  final double   total;
  final DateTime createdAt;
  final String   status;
  const _BillSnapshot({
    required this.id,
    required this.total,
    required this.createdAt,
    required this.status,
  });
}

class _OverflowData {
  final List<_BillSnapshot>  allBills;
  final Map<String, double>  receivedPerBill;
  final double               obRemaining;
  const _OverflowData({
    required this.allBills,
    required this.receivedPerBill,
    required this.obRemaining,
  });
}
