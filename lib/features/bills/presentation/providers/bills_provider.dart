// lib/features/bills/presentation/providers/bills_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../data/models/custom_bill_model.dart';

// ── Stream provider ───────────────────────────────────────────────────────────

final customBillsStreamProvider =
    StreamProvider<List<CustomBillModel>>((ref) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  if (cashbookId == null || cashbookId.isEmpty) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('custom_bills')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map(CustomBillModel.fromFirestore).toList());
});

// ── Actions notifier ──────────────────────────────────────────────────────────

class CustomBillActions extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> saveBill({
    required String cashbookId,
    required CustomBillModel bill,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final ref = FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('custom_bills')
          .doc(bill.billId);
      await ref.set(bill.toFirestore());
    });
  }

  Future<void> updatePdfUrl({
    required String cashbookId,
    required String billId,
    required String pdfUrl,
  }) async {
    await FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('custom_bills')
        .doc(billId)
        .update({'pdfUrl': pdfUrl});
  }

  Future<void> deleteBill({
    required String cashbookId,
    required String billId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('custom_bills')
          .doc(billId)
          .delete();
    });
  }
}

final customBillActionsProvider =
    AsyncNotifierProvider<CustomBillActions, void>(CustomBillActions.new);
