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

  /// Transactions that belong to a single card, newest first. When [limit]
  /// is 0 (default) every transaction is returned — used by the full
  /// History screen. A positive [limit] caps the query at the database
  /// level (instead of downloading everything and truncating client-side)
  /// — used by lightweight "recent" previews.
  Stream<List<DailyCardTransactionEntity>> getTransactionsStream(
      String cashbookId, String cardId, {int limit});
}
