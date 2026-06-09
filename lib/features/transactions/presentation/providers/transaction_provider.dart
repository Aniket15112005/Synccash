import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/domain/repositories/transaction_repository.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepositoryImpl();
});

final transactionsStreamProvider = StreamProvider<List<TransactionEntity>>((ref) {
  final user = ref.watch(authProvider).value;
  if (user?.currentCashbookId == null) return Stream.value([]);
  return ref.watch(transactionRepositoryProvider).getTransactionsStream(user!.currentCashbookId!);
});