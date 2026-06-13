import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/cashbook/data/repositories/cashbook_repository_impl.dart';
import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';
import 'package:synccash/features/cashbook/domain/repositories/cashbook_repository.dart';

final cashbookRepositoryProvider = Provider<CashbookRepository>((ref) {
  return CashbookRepositoryImpl();
});

final cashbookStreamProvider = StreamProvider<CashbookEntity>((ref) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  if (cashbookId == null) return const Stream.empty();
  // ref.watch (not ref.read) ensures the stream rebuilds if the repo changes
  return ref.watch(cashbookRepositoryProvider).watchCashbook(cashbookId);
});