import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/cashbook/data/models/cashbook_model.dart';
import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';
import 'package:synccash/features/cashbook/domain/repositories/cashbook_repository.dart';

class CashbookRepositoryImpl implements CashbookRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(Random().nextInt(chars.length))),
    );
  }

  @override
  Future<CashbookEntity> createCashbook(String userId) async {
    if (userId.isEmpty) throw Exception('User not authenticated.');

    final code = _generateInviteCode();
    final docRef = _firestore.collection('cashbooks').doc();

    final model = CashbookModel(
      id: docRef.id,
      inviteCode: code,
      ownerId: userId,
      participantId: null,
      totalBalance: 0.0,
      totalIncome: 0.0,
      totalExpense: 0.0,
    );

    await docRef.set(model.toJson());

    await _firestore
        .collection('users')
        .doc(userId)
        .set({'currentCashbookId': docRef.id}, SetOptions(merge: true));

    return model;
  }

  @override
  Future<CashbookEntity> joinCashbook(String userId, String inviteCode) async {
    if (userId.isEmpty) throw Exception('User not authenticated.');

    final cleanCode = inviteCode.toUpperCase().trim();

    final query = await _firestore
        .collection('cashbooks')
        .where('inviteCode', isEqualTo: cleanCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Validation Failed: Code not recognized.');
    }

    final doc = query.docs.first;
    final cashbook = CashbookModel.fromJson(doc.data(), doc.id);

    final pid = cashbook.participantId;
    if (pid != null && pid.isNotEmpty) {
      throw Exception('Terminal Access Denied: Channel Busy.');
    }

    if (cashbook.ownerId == userId) {
      throw Exception('Cannot join your own cashbook.');
    }

    await doc.reference.update({'participantId': userId});

    await _firestore
        .collection('users')
        .doc(userId)
        .set({'currentCashbookId': doc.id}, SetOptions(merge: true));

    return CashbookModel(
      id: doc.id,
      inviteCode: cashbook.inviteCode,
      ownerId: cashbook.ownerId,
      participantId: userId,
      totalBalance: cashbook.totalBalance,
      totalIncome: cashbook.totalIncome,
      totalExpense: cashbook.totalExpense,
    );
  }

  @override
  Stream<CashbookEntity> watchCashbook(String cashbookId) {
    // Combine the cashbook doc stream (for metadata: inviteCode, ownerId, etc.)
    // with the transactions subcollection stream (for live-computed totals).
    // This means the balance/income/expense shown in the UI is always derived
    // from the actual transactions that exist — immune to any drift caused by
    // add/update/delete operations not keeping the stored totals in sync.

    late StreamController<CashbookEntity> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? cashbookSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? txSub;

    CashbookModel? latestMeta;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? latestTxDocs;

    void tryEmit() {
      if (latestMeta == null || latestTxDocs == null) return;

      double totalIncome  = 0.0;
      double totalExpense = 0.0;

      for (final doc in latestTxDocs!) {
        final data   = doc.data();
        final type   = (data['type'] as String? ?? '').toLowerCase();
        final amount = (data['amount'] as num? ?? 0).toDouble();
        if (type == 'income') {
          totalIncome += amount;
        } else {
          totalExpense += amount;
        }
      }

      controller.add(CashbookModel(
        id:           latestMeta!.id,
        inviteCode:   latestMeta!.inviteCode,
        ownerId:      latestMeta!.ownerId,
        participantId: latestMeta!.participantId,
        totalIncome:  totalIncome,
        totalExpense: totalExpense,
        totalBalance: totalIncome - totalExpense,
      ));
    }

    controller = StreamController<CashbookEntity>(
      onListen: () {
        // Stream 1: cashbook document (metadata)
        cashbookSub = _firestore
            .collection('cashbooks')
            .doc(cashbookId)
            .snapshots()
            .where((doc) => doc.exists && doc.data() != null)
            .listen(
          (doc) {
            latestMeta = CashbookModel.fromJson(doc.data()!, doc.id);
            tryEmit();
          },
          onError: controller.addError,
        );

        // Stream 2: all active transactions (for live total computation)
        txSub = _firestore
            .collection('cashbooks')
            .doc(cashbookId)
            .collection('transactions')
            .snapshots()
            .listen(
          (snap) {
            latestTxDocs = snap.docs;
            tryEmit();
          },
          onError: controller.addError,
        );
      },
      onCancel: () {
        cashbookSub?.cancel();
        txSub?.cancel();
      },
    );

    return controller.stream;
  }
}
