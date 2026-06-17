import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart'
    show transactionRepositoryProvider;

// ─── Filter enum ──────────────────────────────────────────────────────────────
enum AnalyticsFilter {
  allTime,
  thisWeek,
  thisMonth,
  last3Months;

  String get label {
    switch (this) {
      case AnalyticsFilter.allTime:     return 'All Time';
      case AnalyticsFilter.thisWeek:    return 'This Week';
      case AnalyticsFilter.thisMonth:   return 'This Month';
      case AnalyticsFilter.last3Months: return 'Last 3 Months';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case AnalyticsFilter.allTime: return null;
      case AnalyticsFilter.thisWeek:
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      case AnalyticsFilter.thisMonth:
        return DateTime(now.year, now.month, 1);
      case AnalyticsFilter.last3Months:
        final m = now.month - 2;
        return m <= 0
            ? DateTime(now.year - 1, m + 12, 1)
            : DateTime(now.year, m, 1);
    }
  }
}

// ─── Filter notifier (Riverpod 3-compatible, no StateProvider) ───────────────
class AnalyticsFilterNotifier extends Notifier<AnalyticsFilter> {
  @override
  AnalyticsFilter build() => AnalyticsFilter.allTime;

  void select(AnalyticsFilter filter) => state = filter;
}

final analyticsFilterProvider =
    NotifierProvider<AnalyticsFilterNotifier, AnalyticsFilter>(
        AnalyticsFilterNotifier.new);

// ─── Raw stream (un-paginated) ────────────────────────────────────────────────
final allTransactionsForAnalyticsProvider =
    StreamProvider.family<List<TransactionEntity>, String>(
  (ref, cashbookId) {
    final repo = ref.read(transactionRepositoryProvider);
    return repo.getTransactionsStream(cashbookId);
  },
);

// ─── Analytics data model ─────────────────────────────────────────────────────
class AnalyticsData {
  final double totalIncome;
  final double totalExpense;
  final double netBalance;
  final int    totalCount;
  final int    incomeCount;
  final int    expenseCount;
  final double avgAmount;
  final Map<String, double> categoryTotals;
  final Map<String, int>    categoryCount;
  final Map<String, double> creatorIncome;
  final Map<String, double> creatorExpense;
  final Map<String, int>    creatorCount;
  final Map<String, double> monthlyIncome;
  final Map<String, double> monthlyExpense;
  final List<String>        sortedMonths;
  final TransactionEntity?  highestTx;
  final Map<int, double>    spendingByDayOfWeek; // 1=Mon..7=Sun
  final int    activeDays;
  final double dailyAvgExpense;
  final double incomeExpenseRatio;
  final String peakDayName;
  final double peakDayAmount;
  final List<TransactionEntity> transactions;

  const AnalyticsData({
    required this.totalIncome,
    required this.totalExpense,
    required this.netBalance,
    required this.totalCount,
    required this.incomeCount,
    required this.expenseCount,
    required this.avgAmount,
    required this.categoryTotals,
    required this.categoryCount,
    required this.creatorIncome,
    required this.creatorExpense,
    required this.creatorCount,
    required this.monthlyIncome,
    required this.monthlyExpense,
    required this.sortedMonths,
    this.highestTx,
    required this.spendingByDayOfWeek,
    required this.activeDays,
    required this.dailyAvgExpense,
    required this.incomeExpenseRatio,
    required this.peakDayName,
    required this.peakDayAmount,
    required this.transactions,
  });

  factory AnalyticsData.from(List<TransactionEntity> txs) {
    double income = 0, expense = 0;
    int incomeCount = 0, expenseCount = 0;
    final catTotals  = <String, double>{};
    final catCount   = <String, int>{};
    final crIncome   = <String, double>{};
    final crExpense  = <String, double>{};
    final crCount    = <String, int>{};
    final mIncome    = <String, double>{};
    final mExpense   = <String, double>{};
    final dowSpend   = <int, double>{};
    final activeDaysSet = <String>{};
    TransactionEntity? highest;

    for (final tx in txs) {
      final mk  = _monthKey(tx.createdAt);
      final dow = tx.createdAt.weekday;
      final dk  = '${tx.createdAt.year}-${tx.createdAt.month}-${tx.createdAt.day}';

      activeDaysSet.add(dk);

      if (tx.type == 'income') {
        income += tx.amount;
        incomeCount++;
        crIncome[tx.creatorName] = (crIncome[tx.creatorName] ?? 0) + tx.amount;
        mIncome[mk] = (mIncome[mk] ?? 0) + tx.amount;
      } else {
        expense += tx.amount;
        expenseCount++;
        crExpense[tx.creatorName] = (crExpense[tx.creatorName] ?? 0) + tx.amount;
        mExpense[mk] = (mExpense[mk] ?? 0) + tx.amount;
        dowSpend[dow] = (dowSpend[dow] ?? 0) + tx.amount;
      }

      catTotals[tx.category]  = (catTotals[tx.category]  ?? 0) + tx.amount;
      catCount[tx.category]   = (catCount[tx.category]   ?? 0) + 1;
      crCount[tx.creatorName] = (crCount[tx.creatorName] ?? 0) + 1;
      if (highest == null || tx.amount > highest.amount) highest = tx;
    }

    final allMonths = <String>{...mIncome.keys, ...mExpense.keys}.toList()..sort();
    final last6 = allMonths.length > 6
        ? allMonths.sublist(allMonths.length - 6)
        : allMonths;

    int    peakDow = 1;
    double peakAmt = 0;
    for (final e in dowSpend.entries) {
      if (e.value > peakAmt) { peakAmt = e.value; peakDow = e.key; }
    }

    final days  = activeDaysSet.length;
    final total = income + expense;

    return AnalyticsData(
      totalIncome:  income,
      totalExpense: expense,
      netBalance:   income - expense,
      totalCount:   txs.length,
      incomeCount:  incomeCount,
      expenseCount: expenseCount,
      avgAmount:    txs.isEmpty ? 0 : total / txs.length,
      categoryTotals: catTotals,
      categoryCount:  catCount,
      creatorIncome:  crIncome,
      creatorExpense: crExpense,
      creatorCount:   crCount,
      monthlyIncome:  mIncome,
      monthlyExpense: mExpense,
      sortedMonths:   last6,
      highestTx:      highest,
      spendingByDayOfWeek: dowSpend,
      activeDays:       days,
      dailyAvgExpense:  days == 0 ? 0 : expense / days,
      incomeExpenseRatio: total == 0 ? 0.5 : income / total,
      peakDayName:  _dowName(peakDow),
      peakDayAmount: peakAmt,
      transactions:  txs,
    );
  }

  static String _monthKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

  static String _dowName(int dow) {
    const names = {1:'Monday',2:'Tuesday',3:'Wednesday',4:'Thursday',
                   5:'Friday',6:'Saturday',7:'Sunday'};
    return names[dow] ?? 'Monday';
  }

  List<String> get creators =>
      <String>{...creatorIncome.keys, ...creatorExpense.keys}.toList()..sort();

  List<MapEntry<String, double>> get sortedCategories =>
      categoryTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  String get topCategoryName =>
      sortedCategories.isNotEmpty ? sortedCategories.first.key : '—';

  double get topCategoryAmount =>
      sortedCategories.isNotEmpty ? sortedCategories.first.value : 0;

  double get savingsRate =>
      totalIncome > 0 ? (netBalance / totalIncome).clamp(0.0, 1.0) : 0;
}

// ─── Filtered analytics provider ─────────────────────────────────────────────
final analyticsDataProvider =
    Provider.family<AsyncValue<AnalyticsData>, String>(
  (ref, cashbookId) {
    final asyncTxs = ref.watch(allTransactionsForAnalyticsProvider(cashbookId));
    final filter   = ref.watch(analyticsFilterProvider);

        return asyncTxs.whenData((txs) {
      final start = filter.startDate;
      final nonBank = txs
          .where((tx) => tx.category.toLowerCase() != 'bank')
          .toList();
      final filtered = start == null
          ? nonBank
          : nonBank.where((tx) => !tx.createdAt.isBefore(start)).toList();
      return AnalyticsData.from(filtered);
    });
  },
);
