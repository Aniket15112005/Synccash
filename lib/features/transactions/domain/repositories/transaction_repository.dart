import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

abstract class TransactionRepository {
  Future<void> addTransaction(TransactionEntity transaction);
  Future<void> deleteTransaction(TransactionEntity transaction);
  Future<void> updateTransaction(
    TransactionEntity transaction, {
    TransactionEntity? previous,
  });
  Stream<List<TransactionEntity>> getTransactionsStream(String cashbookId);
}
