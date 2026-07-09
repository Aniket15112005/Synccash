// lib/features/daily/cards/presentation/screens/daily_card_history_screen.dart
//
// Transaction history for a single Daily Card. Reads only from that card's
// own transactions subcollection, so it can never show or affect another
// card's data.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';
import 'package:synccash/features/daily/cards/presentation/providers/daily_card_provider.dart';
import 'package:synccash/features/daily/cards/presentation/widgets/daily_card_edit_tx_sheet.dart';

const _kAccent = Color(0xFF8B5CF6);
const _kBg = Color(0xFFE8E7E4);
const _kText = Color(0xFF1C1C1A);
const _kTextSub = Color(0xFF8A8882);
const _kCard = Color(0xFFF5F4F1);
const _kCardBorder = Color(0xFFF0EFED);
const _kIncome = Color(0xFF16A34A);
const _kIncBg = Color(0xFFE1F5EA);
const _kExpense = Color(0xFFDC2626);
const _kExpBg = Color(0xFFFBE4E4);

final _dateFmt = DateFormat('dd MMM yyyy · hh:mm a');
final _dayFmt = DateFormat('EEEE, dd MMM yyyy');

class DailyCardHistoryScreen extends ConsumerWidget {
  final DailyCardEntity card;
  const DailyCardHistoryScreen({super.key, required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = DailyCardKey(card.cashbookId, card.cardId);
    final asyncTx = ref.watch(dailyCardTransactionsStreamProvider(key));

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('${card.name} · History',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _kText,
                letterSpacing: -0.3)),
      ),
      body: asyncTx.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _kAccent)),
        error: (e, _) => Center(
          child:
              Text('Error: $e', style: const TextStyle(color: _kTextSub)),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.receipt_long_outlined,
                      color: Color(0xFFC8C6C2), size: 40),
                  SizedBox(height: 12),
                  Text('No transactions yet',
                      style: TextStyle(color: _kTextSub)),
                ],
              ),
            );
          }

          double income = 0, expense = 0;
          for (final e in entries) {
            if (e.type.toLowerCase() == 'income') {
              income += e.amount;
            } else {
              expense += e.amount;
            }
          }

          return Column(
            children: [
              const SizedBox(height: 12),
              _SummaryStrip(count: entries.length, income: income, expense: expense),
              const SizedBox(height: 8),
              Expanded(child: _GroupedList(entries: entries)),
            ],
          );
        },
      ),
    );
  }
}

class _GroupedList extends ConsumerWidget {
  final List<DailyCardTransactionEntity> entries;
  const _GroupedList({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<DailyCardTransactionEntity>>{};
    for (final e in entries) {
      final k = _dayFmt.format(e.createdAt);
      groups.putIfAbsent(k, () => []).add(e);
    }

    final items = <Widget>[];
    groups.forEach((day, dayEntries) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(day,
            style: const TextStyle(
                color: _kTextSub,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      ));
      for (final e in dayEntries) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: _TxRow(tx: e),
        ));
      }
    });

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: items,
    );
  }
}

class _TxRow extends ConsumerWidget {
  final DailyCardTransactionEntity tx;
  const _TxRow({required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = tx.type.toLowerCase() == 'income';
    final title = tx.description.isEmpty ? 'Card entry' : tx.description;

    return GestureDetector(
      onTap: () => _showDetail(context, ref),
      onLongPress: () => _confirmDelete(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isIncome ? _kIncBg : _kExpBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIncome
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: isIncome ? _kIncome : _kExpense,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _kText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_dateFmt.format(tx.createdAt),
                      style: const TextStyle(color: _kTextSub, fontSize: 12)),
                ],
              ),
            ),
            Text(
              '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(tx.amount)}',
              style: TextStyle(
                color: isIncome ? _kIncome : _kExpense,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: _kTextSub.withValues(alpha: 0.6), size: 18),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    HapticFeedback.selectionClick();
    final isIncome = tx.type.toLowerCase() == 'income';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFC8C6C2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isIncome ? _kIncBg : _kExpBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isIncome
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: isIncome ? _kIncome : _kExpense,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tx.description.isEmpty ? 'Card entry' : tx.description,
                    style: const TextStyle(
                        color: _kText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DetailRow(
              label: 'Amount',
              value:
                  '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(tx.amount)}',
              valueColor: isIncome ? _kIncome : _kExpense,
            ),
            _DetailRow(label: 'Type', value: isIncome ? 'Income' : 'Expense'),
            _DetailRow(label: 'Date', value: _dateFmt.format(tx.createdAt)),
            _DetailRow(label: 'Added by', value: tx.creatorName),
            if (tx.lastEditedBy != null)
              const _DetailRow(label: 'Status', value: 'Edited'),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showDailyCardEditTxSheet(context, tx: tx);
                    },
                    icon: const Icon(Icons.edit_outlined,
                        size: 17, color: _kAccent),
                    label: const Text('Edit',
                        style: TextStyle(
                            color: _kAccent, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(
                          color: _kAccent.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _confirmDelete(context, ref);
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 17, color: _kExpense),
                    label: const Text('Delete',
                        style: TextStyle(
                            color: _kExpense, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(
                          color: _kExpense.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This only removes it from this card.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(dailyCardRepositoryProvider).deleteTransaction(
                  tx.cashbookId, tx.cardId, tx.txId);
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(color: _kExpense)),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _kTextSub, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? _kText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final int count;
  final double income;
  final double expense;
  const _SummaryStrip(
      {required this.count, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kCardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Item(label: 'Entries', value: '$count'),
            _Item(
                label: 'Income',
                value: '₹${CurrencyFormatter.format(income)}',
                color: _kIncome),
            _Item(
                label: 'Expense',
                value: '₹${CurrencyFormatter.format(expense)}',
                color: _kExpense),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Item({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _kTextSub,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color ?? _kText,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: -0.3)),
      ],
    );
  }
}
