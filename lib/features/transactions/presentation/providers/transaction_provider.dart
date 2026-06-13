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
        data,
        activeCategory: activeCategory,
        activeName: activeName,
        activeDate: activeDate,
        activeDescription: activeDescription,
      ),
    );
  },
);