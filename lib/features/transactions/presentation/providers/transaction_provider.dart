import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/data/repositories/transaction_repository_impl.dart';

class TransactionDateFilter {
  final DateTime? startDate;
  final DateTime? endDate;

  const TransactionDateFilter({
    this.startDate,
    this.endDate,
  });
}

final transactionRepositoryProvider =
    Provider<TransactionRepositoryImpl>((ref) {
  return TransactionRepositoryImpl();
});

const _kTransactionPageSize = 50;

class TransactionLimitNotifier extends Notifier<int> {
  @override
  int build() => _kTransactionPageSize;

  void increment() => state += _kTransactionPageSize;
  void set(int value) => state = value;
}

final transactionLimitProvider =
    NotifierProvider<TransactionLimitNotifier, int>(
        TransactionLimitNotifier.new);

final transactionsStreamProvider =
    StreamProvider.family<List<TransactionEntity>, String>(
        (ref, cashbookId) {
  final repo  = ref.read(transactionRepositoryProvider);
  final limit = ref.watch(transactionLimitProvider);
  return repo.getTransactionsStream(cashbookId, limit: limit);
});

class SelectedCategoryNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? value) => state = value;
}

final selectedCategoryFilterProvider =
    NotifierProvider<SelectedCategoryNotifier, String?>(
        SelectedCategoryNotifier.new);

class SelectedNameNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? value) => state = value;
}

final selectedNameFilterProvider =
    NotifierProvider<SelectedNameNotifier, String?>(
        SelectedNameNotifier.new);

class SelectedDateNotifier extends Notifier<TransactionDateFilter?> {
  @override
  TransactionDateFilter? build() => null;
  void setFilter(TransactionDateFilter? value) => state = value;
}

final selectedDateFilterProvider =
    NotifierProvider<SelectedDateNotifier, TransactionDateFilter?>(
        SelectedDateNotifier.new);

class SelectedDescriptionNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? value) => state = value;
}

final selectedDescriptionFilterProvider =
    NotifierProvider<SelectedDescriptionNotifier, String?>(
        SelectedDescriptionNotifier.new);

bool _hasActiveFilters({
  String? category,
  String? name,
  TransactionDateFilter? date,
  String? description,
}) {
  return category != null ||
      (name != null && name.isNotEmpty) ||
      date != null ||
      (description != null && description.isNotEmpty);
}

List<TransactionEntity> _applyTransactionFilters(
  List<TransactionEntity> data, {
  String? activeCategory,
  String? activeName,
  TransactionDateFilter? activeDate,
  String? activeDescription,
}) {
  if (!_hasActiveFilters(
    category: activeCategory,
    name: activeName,
    date: activeDate,
    description: activeDescription,
  )) {
    return data;
  }

  final categoryLower = activeCategory?.toLowerCase();
  final nameLower = activeName?.toLowerCase().trim();
  final descriptionLower = activeDescription?.toLowerCase().trim();
  final startDate = activeDate?.startDate;
  final endDate = activeDate?.endDate;
  final endBoundary = endDate != null
      ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
      : null;

  return data.where((tx) {
    if (categoryLower != null &&
        tx.category.toLowerCase() != categoryLower) return false;
    if (nameLower != null &&
        nameLower.isNotEmpty &&
        !tx.creatorName.toLowerCase().trim().contains(nameLower)) return false;
    if (startDate != null && tx.createdAt.isBefore(startDate)) return false;
    if (endBoundary != null && tx.createdAt.isAfter(endBoundary)) return false;
    if (descriptionLower != null &&
        descriptionLower.isNotEmpty &&
        !tx.description.toLowerCase().trim().contains(descriptionLower)) return false;
    return true;
  }).toList();
}

final filteredTransactionsProvider =
    Provider.family<AsyncValue<List<TransactionEntity>>, String>(
  (ref, cashbookId) {
    final asyncTransactions = ref.watch(transactionsStreamProvider(cashbookId));
    final activeCategory = ref.watch(selectedCategoryFilterProvider);
    final activeName = ref.watch(selectedNameFilterProvider);
    final activeDate = ref.watch(selectedDateFilterProvider);
    final activeDescription = ref.watch(selectedDescriptionFilterProvider);

    return asyncTransactions.whenData(
      (data) => _applyTransactionFilters(
        data.where((tx) => tx.category.toLowerCase() != 'bank').toList(),
        activeCategory: activeCategory,
        activeName: activeName,
        activeDate: activeDate,
        activeDescription: activeDescription,
      ),
    );
  },
);

// ── NEW ADDITIONS BELOW — nothing above this line was changed ─────────────────

// Fetches ALL transactions with no limit (limit:0 skips .limit() in the repo)
final allTransactionsStreamProvider =
    StreamProvider.family<List<TransactionEntity>, String>(
        (ref, cashbookId) {
  final repo = ref.read(transactionRepositoryProvider);
  return repo.getTransactionsStream(cashbookId, limit: 0);
});

// Used by the history screen — all transactions with the same filters applied
final allFilteredTransactionsProvider =
    Provider.family<AsyncValue<List<TransactionEntity>>, String>(
  (ref, cashbookId) {
    final asyncTransactions =
        ref.watch(allTransactionsStreamProvider(cashbookId));
    final activeCategory    = ref.watch(selectedCategoryFilterProvider);
    final activeName        = ref.watch(selectedNameFilterProvider);
    final activeDate        = ref.watch(selectedDateFilterProvider);
    final activeDescription = ref.watch(selectedDescriptionFilterProvider);

    return asyncTransactions.whenData(
      (data) => _applyTransactionFilters(
        data.where((tx) => tx.category.toLowerCase() != 'bank').toList(),
        activeCategory:    activeCategory,
        activeName:        activeName,
        activeDate:        activeDate,
        activeDescription: activeDescription,
      ),
    );
  },
);

// ── Bank category providers ────────────────────────────────────────────────────

class BankAmountFilter {
  final double? minAmount;
  final double? maxAmount;
  const BankAmountFilter({this.minAmount, this.maxAmount});
}

class BankTypeFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? v) => state = v;
}
final bankTypeFilterProvider =
    NotifierProvider<BankTypeFilterNotifier, String?>(BankTypeFilterNotifier.new);

class BankDateFilterNotifier extends Notifier<TransactionDateFilter?> {
  @override
  TransactionDateFilter? build() => null;
  void setFilter(TransactionDateFilter? v) => state = v;
}
final bankDateFilterProvider =
    NotifierProvider<BankDateFilterNotifier, TransactionDateFilter?>(BankDateFilterNotifier.new);

class BankAmountFilterNotifier extends Notifier<BankAmountFilter?> {
  @override
  BankAmountFilter? build() => null;
  void setFilter(BankAmountFilter? v) => state = v;
}
final bankAmountFilterProvider =
    NotifierProvider<BankAmountFilterNotifier, BankAmountFilter?>(BankAmountFilterNotifier.new);

class BankDescFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? v) => state = v;
}
final bankDescFilterProvider =
    NotifierProvider<BankDescFilterNotifier, String?>(BankDescFilterNotifier.new);

final bankTransactionsStreamProvider =
    StreamProvider.family<List<TransactionEntity>, String>(
  (ref, cashbookId) {
    final repo = ref.read(transactionRepositoryProvider);
    return repo.getTransactionsStream(cashbookId, limit: 0).map(
      (txs) => txs.where((tx) => tx.category.toLowerCase() == 'bank').toList(),
    );
  },
);

List<TransactionEntity> _applyBankFilters(
  List<TransactionEntity> data, {
  String? typeFilter,
  TransactionDateFilter? dateFilter,
  BankAmountFilter? amountFilter,
  String? descFilter,
}) {
  return data.where((tx) {
    if (typeFilter != null && tx.type.toLowerCase() != typeFilter) return false;
    if (dateFilter?.startDate != null && tx.createdAt.isBefore(dateFilter!.startDate!)) return false;
    if (dateFilter?.endDate != null) {
      final end = DateTime(
          dateFilter!.endDate!.year, dateFilter.endDate!.month,
          dateFilter.endDate!.day, 23, 59, 59);
      if (tx.createdAt.isAfter(end)) return false;
    }
    if (amountFilter?.minAmount != null && tx.amount < amountFilter!.minAmount!) return false;
    if (amountFilter?.maxAmount != null && tx.amount > amountFilter!.maxAmount!) return false;
    if (descFilter != null && descFilter.isNotEmpty &&
        !tx.description.toLowerCase().contains(descFilter.toLowerCase())) return false;
    return true;
  }).toList();
}

final filteredBankTransactionsProvider =
    Provider.family<AsyncValue<List<TransactionEntity>>, String>(
  (ref, cashbookId) {
    final async        = ref.watch(bankTransactionsStreamProvider(cashbookId));
    final typeFilter   = ref.watch(bankTypeFilterProvider);
    final dateFilter   = ref.watch(bankDateFilterProvider);
    final amountFilter = ref.watch(bankAmountFilterProvider);
    final descFilter   = ref.watch(bankDescFilterProvider);
    return async.whenData(
      (data) => _applyBankFilters(
        data,
        typeFilter:   typeFilter,
        dateFilter:   dateFilter,
        amountFilter: amountFilter,
        descFilter:   descFilter,
      ),
    );
  },
);
