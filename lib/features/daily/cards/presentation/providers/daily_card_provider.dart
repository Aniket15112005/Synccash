// lib/features/daily/cards/presentation/providers/daily_card_provider.dart
//
// Fully isolated Riverpod providers for the Daily Cards sub-feature. None of
// these read or depend on daily_provider.dart's state, so nothing here can
// leak into, or be affected by, the main Daily list/filters.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/daily/cards/data/repositories/daily_card_repository_impl.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';

final dailyCardRepositoryProvider = Provider<DailyCardRepositoryImpl>((ref) {
  return DailyCardRepositoryImpl();
});

/// All cards saved for a cashbook, newest first.
final dailyCardsStreamProvider =
    StreamProvider.family<List<DailyCardEntity>, String>((ref, cashbookId) {
  final repo = ref.read(dailyCardRepositoryProvider);
  return repo.getCardsStream(cashbookId);
});

/// Composite key so we can key a provider.family by (cashbookId, cardId).
class DailyCardKey {
  final String cashbookId;
  final String cardId;
  const DailyCardKey(this.cashbookId, this.cardId);

  @override
  bool operator ==(Object other) =>
      other is DailyCardKey &&
      other.cashbookId == cashbookId &&
      other.cardId == cardId;

  @override
  int get hashCode => Object.hash(cashbookId, cardId);
}

/// All transactions that belong to a single card, newest first.
final dailyCardTransactionsStreamProvider = StreamProvider.family<
    List<DailyCardTransactionEntity>, DailyCardKey>((ref, key) {
  final repo = ref.read(dailyCardRepositoryProvider);
  return repo.getTransactionsStream(key.cashbookId, key.cardId);
});

class DailyCardSummary {
  final double totalIncome;
  final double totalExpense;
  const DailyCardSummary(
      {required this.totalIncome, required this.totalExpense});
  double get balance => totalIncome - totalExpense;
}

/// Totals computed purely from this card's own transactions — never touches
/// another card, /daily_entries, or the cashbook document.
final dailyCardSummaryProvider =
    Provider.family<AsyncValue<DailyCardSummary>, DailyCardKey>((ref, key) {
  final async = ref.watch(dailyCardTransactionsStreamProvider(key));
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
    return DailyCardSummary(totalIncome: income, totalExpense: expense);
  });
});
