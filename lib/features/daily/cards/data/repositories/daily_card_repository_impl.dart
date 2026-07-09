// lib/features/daily/cards/data/repositories/daily_card_repository_impl.dart
//
// IMPORTANT — data isolation:
// Cards live at `cashbooks/{cashbookId}/daily_cards/{cardId}` and each
// card's transactions live in its own subcollection
// `cashbooks/{cashbookId}/daily_cards/{cardId}/transactions`. This means:
//   - Deleting/editing a transaction on one card can never touch another
//     card's data (different subcollection entirely).
//   - Nothing here ever reads or writes /daily_entries, /transactions, or
//     the parent cashbook document's totals. The main Daily feature and the
//     rest of the app stay completely unaffected.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:synccash/features/daily/cards/data/models/daily_card_model.dart';
import 'package:synccash/features/daily/cards/data/models/daily_card_transaction_model.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';
import 'package:synccash/features/daily/cards/domain/repositories/daily_card_repository.dart';

class DailyCardRepositoryImpl implements DailyCardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _cardsCol(String cashbookId) {
    return _firestore
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('daily_cards');
  }

  CollectionReference<Map<String, dynamic>> _txCol(
      String cashbookId, String cardId) {
    return _cardsCol(cashbookId).doc(cardId).collection('transactions');
  }

  @override
  Future<void> addCard(DailyCardEntity card) async {
    final ref = _cardsCol(card.cashbookId).doc();
    final model = DailyCardModel(
      cardId: ref.id,
      cashbookId: card.cashbookId,
      name: card.name,
      number: card.number,
      bankName: card.bankName,
      colorIndex: card.colorIndex,
      createdBy: card.createdBy,
      creatorName: card.creatorName,
      createdAt: card.createdAt,
    );
    await ref.set(model.toJson());
  }

  @override
  Future<void> deleteCard(String cashbookId, String cardId) async {
    // Delete the card's transactions first so no orphaned data is left
    // behind, then the card document itself. Scoped entirely to this one
    // card's subcollection.
    final txSnap = await _txCol(cashbookId, cardId).get();
    final batch = _firestore.batch();
    for (final doc in txSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_cardsCol(cashbookId).doc(cardId));
    await batch.commit();
  }

  @override
  Stream<List<DailyCardEntity>> getCardsStream(String cashbookId) {
    return _cardsCol(cashbookId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map<DailyCardEntity>((d) => DailyCardModel.fromFirestore(d))
            .toList());
  }

  @override
  Future<void> addTransaction(DailyCardTransactionEntity tx) async {
    final ref = _txCol(tx.cashbookId, tx.cardId).doc();
    final model = DailyCardTransactionModel(
      txId: ref.id,
      cashbookId: tx.cashbookId,
      cardId: tx.cardId,
      createdBy: tx.createdBy,
      creatorName: tx.creatorName,
      createdAt: tx.createdAt,
      amount: tx.amount,
      type: tx.type,
      description: tx.description,
    );
    await ref.set(model.toJson());
  }

  @override
  Future<void> updateTransaction(DailyCardTransactionEntity tx) async {
    await _txCol(tx.cashbookId, tx.cardId).doc(tx.txId).update({
      'amount': tx.amount,
      'type': tx.type,
      'description': tx.description,
      'createdAt': Timestamp.fromDate(tx.createdAt),
      if (tx.lastEditedBy != null) 'lastEditedBy': tx.lastEditedBy,
    });
  }

  @override
  Future<void> deleteTransaction(
      String cashbookId, String cardId, String txId) async {
    await _txCol(cashbookId, cardId).doc(txId).delete();
  }

  @override
  Stream<List<DailyCardTransactionEntity>> getTransactionsStream(
      String cashbookId, String cardId) {
    return _txCol(cashbookId, cardId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map<DailyCardTransactionEntity>(
                (d) => DailyCardTransactionModel.fromFirestore(d))
            .toList());
  }
}
