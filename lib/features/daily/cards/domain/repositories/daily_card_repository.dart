// lib/features/daily/cards/domain/repositories/daily_card_repository.dart

import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';

abstract class DailyCardRepository {
  Future<void> addCard(DailyCardEntity card);
  Future<void> deleteCard(String cashbookId, String cardId);

  /// All cards for a cashbook, newest first.
  Stream<List<DailyCardEntity>> getCardsStream(String cashbookId);

  Future<void> addTransaction(DailyCardTransactionEntity tx);
  Future<void> updateTransaction(DailyCardTransactionEntity tx);
  Future<void> deleteTransaction(
      String cashbookId, String cardId, String txId);

  /// All transactions that belong to a single card, newest first.
  Stream<List<DailyCardTransactionEntity>> getTransactionsStream(
      String cashbookId, String cardId);
}
