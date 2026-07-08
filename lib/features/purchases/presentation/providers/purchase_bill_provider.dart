// lib/features/purchases/presentation/providers/purchase_bill_provider.dart
//
// Mirrors lib/features/sales/presentation/providers/sale_bill_provider.dart
// but for purchase bills owed to suppliers. Payments against purchase bills
// are recorded as EXPENSE transactions (money going out), linked via
// TransactionEntity.linkedPurchaseBillId.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/purchase_bill_entity.dart';
import '../../data/repositories/purchase_bill_repository_impl.dart';
import 'purchase_client_provider.dart';

final purchaseBillRepositoryProvider =
    Provider<PurchaseBillRepositoryImpl>((ref) => PurchaseBillRepositoryImpl());

/// Streams every purchase bill in the active cashbook — used to build the
/// party-name suggestion union on the Add Transaction screen.
///
/// FIX (Android party-picker loading delay): was StreamProvider.autoDispose,
/// so the Firestore listener was disposed right after each one-off `.future`
/// read in _resolveAllPartyNames() and had to reconnect from scratch on the
/// next picker open. See purchase_client_provider.dart's purchaseClientsProvider
/// for the full explanation — same fix, same reasoning.
final allPurchaseBillsProvider =
    StreamProvider<List<PurchaseBillEntity>>((ref) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  if (cashbookId == null) return const Stream.empty();
  return ref.read(purchaseBillRepositoryProvider).watchAllBills(cashbookId);
});

/// Bills for a single client, newest first — used on the client detail screen.
final purchaseBillsForClientProvider = StreamProvider.autoDispose
    .family<List<PurchaseBillEntity>, String>((ref, clientName) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  if (cashbookId == null || clientName.trim().isEmpty) {
    return const Stream.empty();
  }
  return ref
      .read(purchaseBillRepositoryProvider)
      .watchBillsForClient(cashbookId, clientName);
});

/// Pending/partial bills for a client — feeds the bill-no dropdown while
/// recording a payment on the Add Transaction screen.
final pendingPurchaseBillsProvider = StreamProvider.autoDispose
    .family<List<PurchaseBillEntity>, String>((ref, clientName) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  if (cashbookId == null || clientName.trim().isEmpty) {
    return const Stream.empty();
  }
  return ref
      .read(purchaseBillRepositoryProvider)
      .watchPendingBillsByClientName(cashbookId, clientName);
});

/// Search query used inside the Purchases client-detail bill list.
class PurchaseBillSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void update(String query) => state = query;
}

final purchaseBillSearchProvider =
    NotifierProvider<PurchaseBillSearchNotifier, String>(
  PurchaseBillSearchNotifier.new,
);

class PurchaseBillActionsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a brand-new purchase bill for [clientName], creating the client
  /// record if it doesn't already exist yet (mirrors _AddBillSheet._submit
  /// in the Sales feature).
  Future<String> addBill({
    required String cashbookId,
    required String clientName,
    required String billNumber,
    required double billAmount,
    required DateTime billDate,
    String? billNote,
    required String createdBy,
    required String createdByName,
  }) async {
    final trimmedName = clientName.trim();
    state = const AsyncLoading();
    String? newBillId;
    state = await AsyncValue.guard(() async {
      await ref
          .read(purchaseClientRepositoryProvider)
          .ensureClientExists(cashbookId, trimmedName);

      final bill = PurchaseBillEntity(
        purchaseBillId: '',
        clientName: trimmedName,
        billNumber: billNumber.trim(),
        billAmount: billAmount,
        billDate: billDate,
        billNote: billNote,
        billCreatedAt: DateTime.now(),
        billCreatedBy: createdBy,
        billCreatedByName: createdByName,
        billStatus: 'pending',
      );
      newBillId =
          await ref.read(purchaseBillRepositoryProvider).addBill(cashbookId, bill);
    });
    // If the guarded block threw, `state` now holds the real AsyncError —
    // rethrow it instead of silently falling through with a null/late id.
    if (state.hasError) {
      Error.throwWithStackTrace(state.error!, state.stackTrace!);
    }
    return newBillId!;
  }

  Future<void> updateBill(String cashbookId, PurchaseBillEntity bill) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(purchaseBillRepositoryProvider).updateBill(cashbookId, bill));
  }

  Future<void> deleteBill(String cashbookId, String billId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(purchaseBillRepositoryProvider).deleteBill(cashbookId, billId));
  }

  // ── Helper: shared data-fetch used by both overflow methods ─────────────────
  //
  // Mirrors SaleBillProvider._fetchOverflowData exactly. Pending amounts are
  // NEVER read from a stored "billStatus"/"amountPaid" field — they are
  // computed live by summing every expense transaction linked to each bill
  // (linkedPurchaseBillId). This means:
  //   • A ₹50,000 bill with a ₹40,000 expense recorded against it will always
  //     show ₹10,000 pending, straight away, with no separate field to keep
  //     in sync.
  //   • Editing or deleting a past expense automatically corrects the
  //     pending amount everywhere (dropdown, client detail, totals) since
  //     nothing is "frozen" into a status flag.
  Future<_PurchaseOverflowData> _fetchOverflowData({
    required FirebaseFirestore db,
    required String cashbookId,
    required String clientName,
  }) async {
    final clientLow = clientName.trim().toLowerCase();
    final cashRef = db.collection('cashbooks').doc(cashbookId);

    // Bills for this client, sorted oldest first (case-insensitive) for FIFO.
    final billsSnap = await cashRef.collection('purchase_bills').get();
    final allBills = billsSnap.docs
        .where((doc) =>
            (doc.data()['clientName'] as String? ?? '').trim().toLowerCase() ==
            clientLow)
        .map((doc) {
      final d = doc.data();
      return _PurchaseBillSnapshot(
        id: d['purchaseBillId'] as String? ?? doc.id,
        total: (d['billAmount'] as num?)?.toDouble() ?? 0.0,
        createdAt:
            (d['billCreatedAt'] as Timestamp?)?.toDate() ?? DateTime(2000),
      );
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Amounts paid so far — from every expense transaction in this cashbook.
    final txSnap = await cashRef
        .collection('transactions')
        .where('type', isEqualTo: 'expense')
        .get();

    final paidPerBill = <String, double>{};
    double obPaid = 0.0;

    for (final doc in txSnap.docs) {
      final raw = doc.data();
      final linkedId = raw['linkedPurchaseBillId'] as String?;
      final amount = (raw['amount'] as num?)?.toDouble() ?? 0.0;
      final desc = (raw['description'] as String? ?? '').toLowerCase();
      if (linkedId != null && linkedId.isNotEmpty) {
        paidPerBill[linkedId] = (paidPerBill[linkedId] ?? 0.0) + amount;
      } else if (raw['isObPayment'] == true &&
          (raw['obPartyName'] as String? ?? '').trim().toLowerCase() ==
              clientLow) {
        obPaid += amount;
      } else if (desc.contains(clientLow)) {
        obPaid += amount;
      }
    }

    // Opening balance from client document. This stored value is NEVER
    // decremented directly — "remaining" is always (openingBalance - obPaid),
    // computed live, exactly like the Sales feature's obRemaining.
    final clientDoc =
        await cashRef.collection('purchase_clients').doc(clientLow).get();
    final ob = (clientDoc.data()?['openingBalance'] as num?)?.toDouble() ?? 0.0;
    final obRemaining = (ob - obPaid).clamp(0.0, double.infinity);

    return _PurchaseOverflowData(
      allBills: allBills,
      paidPerBill: paidPerBill,
      obRemaining: obRemaining,
    );
  }

  /// Records an expense payment of [totalAmount] against a specific bill
  /// ([selectedBillId]). If the payment exceeds the bill's remaining balance,
  /// the overflow rolls forward FIFO into the client's next-oldest pending
  /// bills, and finally into the opening balance if bills are fully cleared.
  ///
  /// Mirrors SaleBillProvider.recordPaymentWithOverflow. Pending amounts are
  /// always derived live from linked transactions — this method never writes
  /// to a "billStatus" field or mutates the stored opening balance.
  Future<void> recordPaymentWithOverflow({
    required String cashbookId,
    required String selectedBillId,
    required String clientName,
    required double totalAmount,
    required String description,
    required String category,
    required String createdBy,
    required String createdByName,
    required DateTime createdAt,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db = FirebaseFirestore.instance;
      final cashRef = db.collection('cashbooks').doc(cashbookId);
      final txColl = cashRef.collection('transactions');

      final data = await _fetchOverflowData(
        db: db,
        cashbookId: cashbookId,
        clientName: clientName,
      );

      double left = totalAmount;
      final batch = db.batch();

      void alloc({
        required String? linkedBillId,
        required double amount,
        required String desc,
        bool isOb = false,
      }) {
        if (amount <= 0) return;
        final ref = txColl.doc();
        batch.set(ref, {
          'transactionId': ref.id,
          'cashbookId': cashbookId,
          'type': 'expense',
          'amount': amount,
          'description': desc,
          'category': category,
          'linkedPurchaseBillId': linkedBillId,
          'createdBy': createdBy,
          'creatorName': createdByName,
          'createdAt': Timestamp.fromDate(createdAt),
          if (isOb) 'isObPayment': true,
          if (isOb) 'obPartyName': clientName.trim(),
        });
      }

      // 1. Selected bill first.
      final selBill = data.allBills.firstWhere(
        (b) => b.id == selectedBillId,
        orElse: () =>
            _PurchaseBillSnapshot(id: selectedBillId, total: 0, createdAt: DateTime(2000)),
      );
      final selPaid = data.paidPerBill[selectedBillId] ?? 0.0;
      final selRem = (selBill.total - selPaid).clamp(0.0, double.infinity);
      final toSel = left.clamp(0.0, selRem);
      left -= toSel;

      alloc(
        linkedBillId: selectedBillId,
        amount: toSel,
        desc: description.isNotEmpty ? description : 'Payment – $clientName',
      );

      // 2. Other pending bills (oldest first, skipping the selected one).
      if (left > 0) {
        final others = data.allBills.where((b) {
          if (b.id == selectedBillId) return false;
          final paid = data.paidPerBill[b.id] ?? 0.0;
          return (b.total - paid) > 0;
        }).toList();

        for (final bill in others) {
          if (left <= 0) break;
          final paid = data.paidPerBill[bill.id] ?? 0.0;
          final rem = (bill.total - paid).clamp(0.0, double.infinity);
          if (rem <= 0) continue;

          final toThis = left.clamp(0.0, rem);
          left -= toThis;

          alloc(
            linkedBillId: bill.id,
            amount: toThis,
            desc: description.isNotEmpty ? description : 'Payment – $clientName',
          );
        }
      }

      // 3. Opening balance overflow (last resort — excess covers OB debt).
      if (left > 0 && data.obRemaining > 0) {
        final toOb = left.clamp(0.0, data.obRemaining);
        left -= toOb;
        alloc(
          linkedBillId: null,
          amount: toOb,
          desc: 'Opening balance payment – $clientName',
          isOb: true,
        );
      }

      // Update cashbook running totals so balance/expense reflect this payment.
      batch.update(cashRef, {
        'balance': FieldValue.increment(-totalAmount),
        'expense': FieldValue.increment(totalAmount),
      });
      await batch.commit();
    });
  }

  /// Records an expense payment applied directly against the client's
  /// Opening Balance (no specific bill selected) — mirrors
  /// SaleBillProvider.recordObPaymentWithOverflow. Any amount beyond the
  /// opening balance rolls forward FIFO into pending bills.
  Future<void> recordObPaymentWithOverflow({
    required String cashbookId,
    required String clientName,
    required double totalAmount,
    required String description,
    required String category,
    required String createdBy,
    required String createdByName,
    required DateTime createdAt,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db = FirebaseFirestore.instance;
      final cashRef = db.collection('cashbooks').doc(cashbookId);
      final txColl = cashRef.collection('transactions');
      final clientLow = clientName.trim().toLowerCase();

      await ref
          .read(purchaseClientRepositoryProvider)
          .ensureClientExists(cashbookId, clientName);

      final data = await _fetchOverflowData(
        db: db,
        cashbookId: cashbookId,
        clientName: clientName,
      );

      double left = totalAmount;
      final batch = db.batch();

      void alloc({
        required String? linkedBillId,
        required double amount,
        required String desc,
        bool isOb = false,
      }) {
        if (amount <= 0) return;
        final ref = txColl.doc();
        batch.set(ref, {
          'transactionId': ref.id,
          'cashbookId': cashbookId,
          'type': 'expense',
          'amount': amount,
          'description': desc,
          'category': category,
          'linkedPurchaseBillId': linkedBillId,
          'createdBy': createdBy,
          'creatorName': createdByName,
          'createdAt': Timestamp.fromDate(createdAt),
          if (isOb) 'isObPayment': true,
          if (isOb) 'obPartyName': clientName.trim(),
        });
      }

      // 1. Opening balance first.
      final toOb = left.clamp(0.0, data.obRemaining);
      left -= toOb;

      final obDesc = description.toLowerCase().contains(clientLow)
          ? description
          : '$description – $clientName';

      alloc(linkedBillId: null, amount: toOb, desc: obDesc, isOb: true);

      // 2. Overflow to pending bills (oldest first).
      if (left > 0) {
        final pendingBills = data.allBills.where((b) {
          final paid = data.paidPerBill[b.id] ?? 0.0;
          return (b.total - paid) > 0;
        }).toList();

        for (final bill in pendingBills) {
          if (left <= 0) break;
          final paid = data.paidPerBill[bill.id] ?? 0.0;
          final rem = (bill.total - paid).clamp(0.0, double.infinity);
          if (rem <= 0) continue;

          final toThis = left.clamp(0.0, rem);
          left -= toThis;

          alloc(
            linkedBillId: bill.id,
            amount: toThis,
            desc: description.isNotEmpty ? description : 'Payment – $clientName',
          );
        }
      }

      // 3. Anything left over (all bills + OB cleared) still gets recorded.
      if (left > 0) {
        alloc(
          linkedBillId: null,
          amount: left,
          desc: description.isNotEmpty ? description : 'Payment – $clientName',
        );
      }

      // Update cashbook running totals so balance/expense reflect this payment.
      batch.update(cashRef, {
        'balance': FieldValue.increment(-totalAmount),
        'expense': FieldValue.increment(totalAmount),
      });
      await batch.commit();
    });
  }

  /// Auto-allocates a payment against a purchase client when the user did NOT
  /// explicitly select a bill or the opening balance.
  ///
  /// Priority order:
  ///   1. OB still pending → pay OB first, any overflow spills into pending
  ///      bills (oldest first).
  ///   2. OB fully settled, ≥1 pending bill → FIFO across all pending bills,
  ///      any remainder after all bills cleared is recorded unlinked.
  ///   3. Nothing pending → plain unlinked expense transaction.
  Future<void> recordAutoPayment({
    required String cashbookId,
    required String clientName,
    required double totalAmount,
    required String description,
    required String category,
    required String createdBy,
    required String createdByName,
    required DateTime createdAt,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db       = FirebaseFirestore.instance;
      final cashRef  = db.collection('cashbooks').doc(cashbookId);
      final txColl   = cashRef.collection('transactions');
      final client   = clientName.trim();

      final data = await _fetchOverflowData(
        db: db,
        cashbookId: cashbookId,
        clientName: client,
      );

      final pendingBills = data.allBills.where((b) {
        final paid = data.paidPerBill[b.id] ?? 0.0;
        return (b.total - paid) > 0;
      }).toList(); // already sorted oldest-first by _fetchOverflowData

      double left      = totalAmount;
      final  batch     = db.batch();
      final  baseDesc  = description.isNotEmpty ? description : 'Payment – $client';

      void alloc({
        required String? linkedBillId,
        required double  amount,
        required String  desc,
        bool isOb = false,
      }) {
        if (amount <= 0) return;
        final ref = txColl.doc();
        batch.set(ref, {
          'transactionId':        ref.id,
          'cashbookId':           cashbookId,
          'type':                 'expense',
          'amount':               amount,
          'description':          desc,
          'category':             category,
          'linkedPurchaseBillId': linkedBillId,
          'createdBy':            createdBy,
          'creatorName':          createdByName,
          'createdAt':            Timestamp.fromDate(createdAt),
          if (isOb) 'isObPayment': true,
          if (isOb) 'obPartyName': client,
        });
      }

      if (data.obRemaining > 0) {
        // ── Priority 1: OB pending ──────────────────────────────────────────
        final toOb = left.clamp(0.0, data.obRemaining);
        left -= toOb;
        alloc(
          linkedBillId: null,
          amount: toOb,
          desc: description.isNotEmpty
              ? description
              : 'Opening balance payment – $client',
          isOb: true,
        );
        // Overflow into pending bills (FIFO).
        for (final bill in pendingBills) {
          if (left <= 0) break;
          final paid    = data.paidPerBill[bill.id] ?? 0.0;
          final rem     = (bill.total - paid).clamp(0.0, double.infinity);
          final toThis  = left.clamp(0.0, rem);
          left -= toThis;
          alloc(linkedBillId: bill.id, amount: toThis, desc: baseDesc);
        }
        // Any remainder (everything cleared): still record unlinked.
        if (left > 0) {
          alloc(linkedBillId: null, amount: left, desc: baseDesc);
        }
      } else if (pendingBills.isNotEmpty) {
        // ── Priority 2: OB settled, bills pending — pure FIFO ──────────────
        for (final bill in pendingBills) {
          if (left <= 0) break;
          final paid   = data.paidPerBill[bill.id] ?? 0.0;
          final rem    = (bill.total - paid).clamp(0.0, double.infinity);
          final toThis = left.clamp(0.0, rem);
          left -= toThis;
          alloc(linkedBillId: bill.id, amount: toThis, desc: baseDesc);
        }
        // Remainder after all bills cleared.
        if (left > 0) {
          alloc(linkedBillId: null, amount: left, desc: baseDesc);
        }
      } else {
        // ── Priority 3: nothing pending — plain unlinked expense ───────────
        alloc(linkedBillId: null, amount: totalAmount, desc: baseDesc);
      }

      batch.update(cashRef, {
        'balance': FieldValue.increment(-totalAmount),
        'expense': FieldValue.increment(totalAmount),
      });
      await batch.commit();
    });
  }

  /// Records a final expense entry settling the remaining balance on a specific
  /// bill (write-off). If remaining == 0 the method is a no-op. Mirrors
  /// saleBillActionsProvider.settleWithPayment on the sales side.
  Future<void> settleWithPayment({
    required String cashbookId,
    required String billId,
    required String billNumber,
    required String clientName,
    required double remaining,
    required String createdBy,
    required String createdByName,
  }) async {
    if (remaining <= 0) return; // already settled — nothing to do
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db       = FirebaseFirestore.instance;
      final cashRef  = db.collection('cashbooks').doc(cashbookId);
      final txRef    = cashRef.collection('transactions').doc();

      final batch = db.batch();
      batch.set(txRef, {
        'transactionId':       txRef.id,
        'cashbookId':          cashbookId,
        'type':                'expense',
        'amount':              remaining,
        'description':         'Settlement – $clientName – Bill #$billNumber',
        'category':            'wholesale',
        'linkedPurchaseBillId': billId,
        'createdBy':           createdBy,
        'creatorName':         createdByName,
        'createdAt':           Timestamp.fromDate(DateTime.now()),
      });
      // Update cashbook running totals
      batch.update(cashRef, {
        'balance': FieldValue.increment(-remaining),
        'expense': FieldValue.increment(remaining),
      });
      await batch.commit();
    });
  }

}

class _PurchaseBillSnapshot {
  final String id;
  final double total;
  final DateTime createdAt;
  const _PurchaseBillSnapshot({
    required this.id,
    required this.total,
    required this.createdAt,
  });
}

class _PurchaseOverflowData {
  final List<_PurchaseBillSnapshot> allBills;
  final Map<String, double> paidPerBill;
  final double obRemaining;
  const _PurchaseOverflowData({
    required this.allBills,
    required this.paidPerBill,
    required this.obRemaining,
  });
}

final purchaseBillActionsProvider =
    AsyncNotifierProvider<PurchaseBillActionsNotifier, void>(
  PurchaseBillActionsNotifier.new,
);

/// Quick lookup of a bill by id — used when editing a transaction that
/// already has a linkedPurchaseBillId, to pre-select it in the dropdown.
final purchaseBillByIdProvider = FutureProvider.autoDispose
    .family<PurchaseBillEntity?, ({String cashbookId, String billId})>((ref, args) {
  return ref
      .read(purchaseBillRepositoryProvider)
      .getBill(args.cashbookId, args.billId);
});

// Convenience direct-Firestore accessor kept for parity with how
// add_transaction_screen.dart loads an existing linked sale bill.
Future<PurchaseBillEntity?> loadPurchaseBillDirect(
    String cashbookId, String billId) async {
  final doc = await FirebaseFirestore.instance
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('purchase_bills')
      .doc(billId)
      .get();
  if (!doc.exists) return null;
  return PurchaseBillEntity(
    purchaseBillId: doc.id,
    clientName: doc.data()?['clientName'] as String? ?? '',
    billNumber: doc.data()?['billNumber'] as String? ?? '',
    billAmount: (doc.data()?['billAmount'] as num?)?.toDouble() ?? 0.0,
    billDate: (doc.data()?['billDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
    billNote: doc.data()?['billNote'] as String?,
    billCreatedAt:
        (doc.data()?['billCreatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    billCreatedBy: doc.data()?['billCreatedBy'] as String? ?? '',
    billCreatedByName: doc.data()?['billCreatedByName'] as String? ?? '',
    billStatus: doc.data()?['billStatus'] as String? ?? 'pending',
  );
}