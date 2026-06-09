import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/cashbook/data/models/cashbook_model.dart';
import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';
import 'package:synccash/features/cashbook/domain/repositories/cashbook_repository.dart';

class CashbookRepositoryImpl implements CashbookRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(Random().nextInt(chars.length))));
  }

  @override
  Future<CashbookEntity> createCashbook(String userId) async {
    final code = _generateInviteCode();
    final docRef = _firestore.collection('cashbooks').doc();
    final model = CashbookModel(
      id: docRef.id,
      inviteCode: code,
      ownerId: userId,
      totalBalance: 0.0,
      totalIncome: 0.0,
      totalExpense: 0.0,
    );
    
    await _firestore.runTransaction((transaction) async {
      transaction.set(docRef, model.toJson());
      transaction.update(_firestore.collection('users').doc(userId), {'currentCashbookId': docRef.id});
    });
    return model;
  }

  @override
  Future<CashbookEntity> joinCashbook(String userId, String inviteCode) async {
    final query = await _firestore.collection('cashbooks')
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase().trim())
        .limit(1)
        .get();

    if (query.docs.isEmpty) throw Exception('Validation Failed: Code not recognized.');
    final doc = query.docs.first;
    final cashbook = CashbookModel.fromJson(doc.data(), doc.id);

    if (cashbook.participantId != null) throw Exception('Terminal Access Denied: Channel Busy.');

    await _firestore.runTransaction((transaction) async {
      transaction.update(doc.reference, {'participantId': userId});
      transaction.update(_firestore.collection('users').doc(userId), {'currentCashbookId': doc.id});
    });

    return cashbook;
  }

  @override
  Stream<CashbookEntity> watchCashbook(String cashbookId) {
    return _firestore.collection('cashbooks').doc(cashbookId).snapshots().map((doc) {
      return CashbookModel.fromJson(doc.data()!, doc.id);
    });
  }
}