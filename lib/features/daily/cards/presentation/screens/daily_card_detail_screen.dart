// lib/features/daily/cards/presentation/screens/daily_card_detail_screen.dart
//
// Opens after tapping a card in DailyCardsScreen. Shows the animated card,
// this card's own balance/stats, the last 5–6 recent transactions, and a
// floating "Add Entry" button that opens a bottom sheet form.
// Everything here is scoped to `card.cardId` only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';
import 'package:synccash/features/daily/cards/presentation/providers/daily_card_provider.dart';
import 'package:synccash/features/daily/cards/presentation/screens/daily_card_history_screen.dart';
import 'package:synccash/features/daily/cards/presentation/widgets/daily_card_edit_tx_sheet.dart';
import 'package:synccash/features/daily/cards/presentation/widgets/daily_credit_card_widget.dart';
import 'package:intl/intl.dart';

const _kAccent = Color(0xFF8B5CF6);
const _kBg = Color(0xFFE8E7E4);
const _kText = Color(0xFF1C1C1A);
const _kTextSub = Color(0xFF8A8882);
const _kCard = Color(0xFFF5F4F1);
const _kCardBorder = Color(0xFFF0EFED);
const _kIncome = Color(0xFF16A34A);
const _kExpense = Color(0xFFDC2626);

class DailyCardDetailScreen extends ConsumerWidget {
  final DailyCardEntity card;
  const DailyCardDetailScreen({super.key, required this.card});

  void _openAddEntry(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEntrySheet(card: card),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = DailyCardKey(card.cashbookId, card.cardId);
    final asyncSummary = ref.watch(dailyCardSummaryProvider(key));
    final asyncTxns = ref.watch(dailyCardTransactionsStreamProvider(key));

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(
          card.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: _kText,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyCardHistoryScreen(card: card),
                  ),
                );
              },
              icon: const Icon(Icons.history_rounded, size: 17, color: _kAccent),
              label: const Text(
                'History',
                style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _AddEntryFAB(
        onPressed: () => _openAddEntry(context, ref),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Animated credit card ─────────────────────────────────────
              DailyCreditCardWidget(
                name: card.name,
                number: card.number,
                bankName: card.bankName,
                colorIndex: card.colorIndex,
                expanded: true,
              ),
              const SizedBox(height: 18),

              // ── Balance / Income / Expense summary ───────────────────────
              asyncSummary.when(
                loading: () => const SizedBox(
                  height: 70,
                  child: Center(
                    child: CircularProgressIndicator(
                        color: _kAccent, strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Text('Error: $e',
                    style: const TextStyle(color: _kTextSub)),
                data: (summary) => Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Balance',
                        value: summary.balance,
                        color: summary.balance >= 0 ? _kIncome : _kExpense,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Income',
                        value: summary.totalIncome,
                        color: _kIncome,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Expense',
                        value: summary.totalExpense,
                        color: _kExpense,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Recent Transactions header ────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Transactions',
                    style: TextStyle(
                      color: _kText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DailyCardHistoryScreen(card: card),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'See all',
                        style: TextStyle(
                          color: _kAccent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Transactions list ─────────────────────────────────────────
              asyncTxns.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(
                        color: _kAccent, strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: _kTextSub)),
                ),
                data: (txns) {
                  if (txns.isEmpty) {
                    return _EmptyTransactions();
                  }
                  final recent = txns.take(6).toList();
                  return Column(
                    children: [
                      ...recent.asMap().entries.map((entry) {
                        final i = entry.key;
                        final tx = entry.value;
                        return _RecentTxTile(
                          tx: tx,
                          isLast: i == recent.length - 1,
                        );
                      }),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB
// ─────────────────────────────────────────────────────────────────────────────

class _AddEntryFAB extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddEntryFAB({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Add Entry',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyTransactions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: _kAccent, size: 26),
          ),
          const SizedBox(height: 14),
          const Text(
            'No transactions yet',
            style: TextStyle(
              color: _kText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Tap "Add Entry" below to record\nyour first transaction.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTextSub, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent transaction tile
// ─────────────────────────────────────────────────────────────────────────────

class _RecentTxTile extends StatelessWidget {
  final DailyCardTransactionEntity tx;
  final bool isLast;

  const _RecentTxTile({
    required this.tx,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.type.toLowerCase() == 'income';
    final color = isIncome ? _kIncome : _kExpense;
    final sign = isIncome ? '+' : '−';
    final dateStr = DateFormat('dd MMM, hh:mm a').format(tx.createdAt);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        showDailyCardEditTxSheet(context, tx: tx);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kCardBorder),
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIncome
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 13),
            // Description + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.description.isNotEmpty
                        ? tx.description
                        : (isIncome ? 'Income' : 'Expense'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                          color: _kTextSub,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (tx.creatorName.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: _kTextSub,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            tx.creatorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kTextSub,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Amount
            Text(
              '$sign₹${CurrencyFormatter.format(tx.amount)}',
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Entry bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddEntrySheet extends ConsumerStatefulWidget {
  final DailyCardEntity card;
  const _AddEntrySheet({required this.card});

  @override
  ConsumerState<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends ConsumerState<_AddEntrySheet> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'expense';
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final user = ref.read(authProvider).value;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final tx = DailyCardTransactionEntity(
        txId: '',
        cashbookId: widget.card.cashbookId,
        cardId: widget.card.cardId,
        createdBy: user.uid,
        creatorName:
            user.displayName.isEmpty ? 'Partner' : user.displayName,
        createdAt: DateTime.now(),
        amount: amount,
        type: _type,
        description: _descCtrl.text.trim(),
      );
      await ref.read(dailyCardRepositoryProvider).addTransaction(tx);
      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction added')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = _type == 'income';
    final accentColor = isIncome ? _kIncome : _kExpense;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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

            // Title
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: _kAccent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Entry',
                        style: TextStyle(
                          color: _kText,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        widget.card.name,
                        style: const TextStyle(
                          color: _kTextSub,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Expense / Income toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kCardBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TypeSegment(
                      label: 'Expense',
                      selected: _type == 'expense',
                      color: _kExpense,
                      onTap: () => setState(() => _type = 'expense'),
                    ),
                  ),
                  Expanded(
                    child: _TypeSegment(
                      label: 'Income',
                      selected: _type == 'income',
                      color: _kIncome,
                      onTap: () => setState(() => _type = 'income'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Amount field
            Container(
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kCardBorder),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  color: accentColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                    color: accentColor.withValues(alpha: 0.45),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                  hintText: '0',
                  hintStyle: TextStyle(
                    color: accentColor.withValues(alpha: 0.25),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Description field
            Container(
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kCardBorder),
              ),
              child: TextField(
                controller: _descCtrl,
                maxLines: 2,
                minLines: 1,
                style: const TextStyle(color: _kText, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: "What's this for? (optional)",
                  hintStyle:
                      TextStyle(color: _kTextSub.withValues(alpha: 0.6)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kAccent.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Save Entry',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat card
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _kTextSub,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${CurrencyFormatter.format(value.abs())}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type segment (Expense / Income toggle button)
// ─────────────────────────────────────────────────────────────────────────────

class _TypeSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _TypeSegment({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.30)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : _kTextSub,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
