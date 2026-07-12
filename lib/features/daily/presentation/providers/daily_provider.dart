// lib/features/daily/presentation/providers/daily_provider.dart
//
// Fully isolated Riverpod providers for the Daily feature. These are
// deliberately separate from transaction_provider.dart's providers
// (selectedDateFilterProvider, selectedNameFilterProvider, etc.) so that
// filtering/state here never leaks into, or is affected by, the main
// dashboard/history filters.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/daily/data/repositories/daily_repository_impl.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';

class DailyDateFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  const DailyDateFilter({this.startDate, this.endDate});
}

final dailyRepositoryProvider = Provider<DailyRepositoryImpl>((ref) {
  return DailyRepositoryImpl();
});

/// All Daily entries for a cashbook, newest first, no limit. Feeds the
/// History screen (must show everything) and the balance/summary calc
/// (must total every entry to be correct).
///
/// `autoDispose` so this listener closes once nothing is watching it,
/// instead of staying open in the background for the rest of the session.
final dailyEntriesStreamProvider =
    StreamProvider.family<List<DailyEntryEntity>, String>((ref, cashbookId) {
  final repo = ref.read(dailyRepositoryProvider);
  return repo.getEntriesStream(cashbookId, limit: 0);
});

/// A capped preview (most recent ~50) of Daily entries — for the "Recent
/// Entries" section on the Daily home screen. This avoids downloading the
/// entire Daily history just to render a handful of preview rows. The full
/// history remains available via [dailyEntriesStreamProvider] on the
/// dedicated History screen.
final dailyRecentEntriesStreamProvider =
    StreamProvider.family<List<DailyEntryEntity>, String>((ref, cashbookId) {
  final repo = ref.read(dailyRepositoryProvider);
  return repo.getEntriesStream(cashbookId, limit: 50);
});

// ── Isolated filter notifiers (own state, own providers) ────────────────────

class DailyNameFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? value) => state = value;
}

final dailyNameFilterProvider =
    NotifierProvider<DailyNameFilterNotifier, String?>(
        DailyNameFilterNotifier.new);

class DailyDescriptionFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? value) => state = value;
}

final dailyDescriptionFilterProvider =
    NotifierProvider<DailyDescriptionFilterNotifier, String?>(
        DailyDescriptionFilterNotifier.new);

class DailyDateFilterNotifier extends Notifier<DailyDateFilter?> {
  @override
  DailyDateFilter? build() => null;
  void setFilter(DailyDateFilter? value) => state = value;
}

final dailyDateFilterProvider =
    NotifierProvider<DailyDateFilterNotifier, DailyDateFilter?>(
        DailyDateFilterNotifier.new);

class DailyTypeFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? value) => state = value;
}

final dailyTypeFilterProvider =
    NotifierProvider<DailyTypeFilterNotifier, String?>(
        DailyTypeFilterNotifier.new);

bool _hasActiveDailyFilters({
  String? name,
  String? description,
  DailyDateFilter? date,
  String? type,
}) {
  return (name != null && name.isNotEmpty) ||
      (description != null && description.isNotEmpty) ||
      date != null ||
      type != null;
}

List<DailyEntryEntity> _applyDailyFilters(
  List<DailyEntryEntity> data, {
  String? activeName,
  String? activeDescription,
  DailyDateFilter? activeDate,
  String? activeType,
}) {
  if (!_hasActiveDailyFilters(
    name: activeName,
    description: activeDescription,
    date: activeDate,
    type: activeType,
  )) {
    return data;
  }

  final nameLower = activeName?.toLowerCase().trim();
  final descriptionLower = activeDescription?.toLowerCase().trim();
  final startDate = activeDate?.startDate;
  final endDate = activeDate?.endDate;
  final endBoundary = endDate != null
      ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
      : null;

  return data.where((e) {
    if (activeType != null && e.type.toLowerCase() != activeType) {
      return false;
    }
    if (nameLower != null &&
        nameLower.isNotEmpty &&
        !e.creatorName.toLowerCase().trim().contains(nameLower)) {
      return false;
    }
    if (startDate != null && e.createdAt.isBefore(startDate)) return false;
    if (endBoundary != null && e.createdAt.isAfter(endBoundary)) return false;
    if (descriptionLower != null &&
        descriptionLower.isNotEmpty &&
        !e.description.toLowerCase().trim().contains(descriptionLower)) {
      return false;
    }
    return true;
  }).toList();
}

/// Entries with all Daily-only filters applied, over the FULL history.
/// Used by the History screen, which must be able to show/filter every
/// entry that has ever been added.
final dailyFilteredEntriesProvider =
    Provider.family<AsyncValue<List<DailyEntryEntity>>, String>(
  (ref, cashbookId) {
    final async = ref.watch(dailyEntriesStreamProvider(cashbookId));
    final activeName = ref.watch(dailyNameFilterProvider);
    final activeDescription = ref.watch(dailyDescriptionFilterProvider);
    final activeDate = ref.watch(dailyDateFilterProvider);
    final activeType = ref.watch(dailyTypeFilterProvider);

    return async.whenData(
      (data) => _applyDailyFilters(
        data,
        activeName: activeName,
        activeDescription: activeDescription,
        activeDate: activeDate,
        activeType: activeType,
      ),
    );
  },
);

/// Same filtering, but over the capped "recent" window instead of the full
/// history — used only by the Daily home screen's "Recent Entries"
/// preview, so opening the home screen doesn't have to download the whole
/// history just to show a few rows. Filtering behaves identically to
/// [dailyFilteredEntriesProvider]; only the underlying data window is
/// smaller.
final dailyRecentFilteredEntriesProvider =
    Provider.family<AsyncValue<List<DailyEntryEntity>>, String>(
  (ref, cashbookId) {
    final async = ref.watch(dailyRecentEntriesStreamProvider(cashbookId));
    final activeName = ref.watch(dailyNameFilterProvider);
    final activeDescription = ref.watch(dailyDescriptionFilterProvider);
    final activeDate = ref.watch(dailyDateFilterProvider);
    final activeType = ref.watch(dailyTypeFilterProvider);

    return async.whenData(
      (data) => _applyDailyFilters(
        data,
        activeName: activeName,
        activeDescription: activeDescription,
        activeDate: activeDate,
        activeType: activeType,
      ),
    );
  },
);

class DailySummary {
  final double totalIncome;
  final double totalExpense;
  const DailySummary({required this.totalIncome, required this.totalExpense});
  double get balance => totalIncome - totalExpense;
}

/// Totals computed purely from daily_entries — never touches the cashbook
/// document, so it can't drift from or affect the main dashboard's numbers.
final dailySummaryProvider =
    Provider.family<AsyncValue<DailySummary>, String>((ref, cashbookId) {
  final async = ref.watch(dailyEntriesStreamProvider(cashbookId));
  return async.whenData((entries) {
    double income = 0;
    double expense = 0;
    for (final e in entries) {
      if (e.type.toLowerCase() == 'income') {
        income += e.amount;
      } else if (e.type.toLowerCase() == 'expense') {
        expense += e.amount;
      }
    }
    return DailySummary(totalIncome: income, totalExpense: expense);
  });
});
