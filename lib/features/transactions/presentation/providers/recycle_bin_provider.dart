import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/data/services/recycle_bin_service.dart';
import 'package:synccash/features/transactions/domain/entities/deleted_transaction_entity.dart';

final deletedTransactionsProvider =
    StreamProvider.family<List<DeletedTransactionEntity>, String>(
  (ref, cashbookId) => RecycleBinService.stream(cashbookId),
);