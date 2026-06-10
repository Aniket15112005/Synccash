import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/data/repositories/transaction_repository_impl.dart';

/// 1. Transaction Repository Provider
final transactionRepositoryProvider =
    Provider<TransactionRepositoryImpl>((ref) {
  return TransactionRepositoryImpl();
});

/// 2. Stream Provider
final transactionsStreamProvider =
    StreamProvider.family<List<TransactionEntity>, String>(
        (ref, cashbookId) {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.getTransactionsStream(cashbookId);
});

/// 3. CATEGORY FILTER
class SelectedCategoryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? value) => state = value;
}

final selectedCategoryFilterProvider =
    NotifierProvider<SelectedCategoryNotifier, String?>(
        SelectedCategoryNotifier.new);

/// 4. NAME FILTER
class SelectedNameNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? value) => state = value;
}

final selectedNameFilterProvider =
    NotifierProvider<SelectedNameNotifier, String?>(
        SelectedNameNotifier.new);

/// 5. DATE FILTER
class SelectedDateNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void setFilter(DateTime? value) => state = value;
}

final selectedDateFilterProvider =
    NotifierProvider<SelectedDateNotifier, DateTime?>(
        SelectedDateNotifier.new);

/// ⭐ 5.1 DESCRIPTION FILTER (NEW FEATURE ONLY)
class SelectedDescriptionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? value) => state = value;
}

final selectedDescriptionFilterProvider =
    NotifierProvider<SelectedDescriptionNotifier, String?>(
        SelectedDescriptionNotifier.new);

/// 6. FILTERED PROVIDER (UNCHANGED LOGIC + DESCRIPTION ADDED)
final filteredTransactionsProvider =
    Provider.family<AsyncValue<List<TransactionEntity>>, String>(
  (ref, cashbookId) {
    final asyncTransactions =
        ref.watch(transactionsStreamProvider(cashbookId));

    final activeCategory = ref.watch(selectedCategoryFilterProvider);
    final activeName = ref.watch(selectedNameFilterProvider);
    final activeDate = ref.watch(selectedDateFilterProvider);

    /// ⭐ NEW WATCH (DESCRIPTION)
    final activeDescription =
        ref.watch(selectedDescriptionFilterProvider);

    return asyncTransactions.whenData((data) {
      return data.where((tx) {
        // CATEGORY
        if (activeCategory != null &&
            (tx.category ?? '').toLowerCase() !=
                activeCategory.toLowerCase()) {
          return false;
        }

        // NAME
        if (activeName != null &&
            activeName.isNotEmpty &&
            !(tx.creatorName ?? '')
                .toLowerCase()
                .trim()
                .contains(activeName.toLowerCase().trim())) {
          return false;
        }

        // DATE
        if (activeDate != null) {
          final txDate = tx.createdAt;

          if (txDate == null ||
              txDate.year != activeDate.year ||
              txDate.month != activeDate.month ||
              txDate.day != activeDate.day) {
            return false;
          }
        }

        // ⭐ DESCRIPTION FILTER (NEW)
        if (activeDescription != null &&
            activeDescription.isNotEmpty &&
            !(tx.description ?? '')
                .toLowerCase()
                .trim()
                .contains(activeDescription.toLowerCase().trim())) {
          return false;
        }

        return true;
      }).toList();
    });
  },
);