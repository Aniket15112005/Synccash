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

    // Write cashbook doc
    await docRef.set(model.toJson());

    // Use set+merge so it works whether the user doc exists or not
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

    // Block if already has a participant (null AND empty string both mean "free")
    final pid = cashbook.participantId;
    if (pid != null && pid.isNotEmpty) {
      throw Exception('Terminal Access Denied: Channel Busy.');
    }

    // Block owner from joining their own cashbook
    if (cashbook.ownerId == userId) {
      throw Exception('Cannot join your own cashbook.');
    }

    // Direct update — no transaction needed
    await doc.reference.update({'participantId': userId});

    // Use set+merge so it works whether the user doc exists or not
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
  return _firestore
      .collection('cashbooks')
      .doc(cashbookId)
      .snapshots()
      .where((doc) => doc.exists && doc.data() != null)
      .map((doc) => CashbookModel.fromJson(doc.data()!, doc.id));
}
}
