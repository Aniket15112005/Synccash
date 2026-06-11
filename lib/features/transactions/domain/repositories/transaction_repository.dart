import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

abstract class TransactionRepository {
  Future<void> addTransaction(TransactionEntity transaction);
  Future<void> deleteTransaction(TransactionEntity transaction);
  Stream<List<TransactionEntity>> getTransactionsStream(String cashbookId);
}