// lib/features/daily/cards/presentation/screens/daily_card_detail_screen.dart
//
// Opens after tapping a card in DailyCardsScreen. Shows the animated card,
// this card's own balance, an inline "Add transaction" form, and a button
// to view this card's full history. Everything here is scoped to
// `card.cardId` only — it can never read or write another card's data.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';
import 'package:synccash/features/daily/cards/presentation/providers/daily_card_provider.dart';
import 'package:synccash/features/daily/cards/presentation/screens/daily_card_history_screen.dart';
import 'package:synccash/features/daily/cards/presentation/widgets/daily_credit_card_widget.dart';

const _kAccent = Color(0xFF8B5CF6);
const _kBg = Color(0xFFE8E7E4);
const _kText = Color(0xFF1C1C1A);
const _kTextSub = Color(0xFF8A8882);
const _kCard = Color(0xFFF5F4F1);
const _kCardBorder = Color(0xFFF0EFED);
const _kIncome = Color(0xFF16A34A);
const _kExpense = Color(0xFFDC2626);

class DailyCardDetailScreen extends ConsumerStatefulWidget {
  final DailyCardEntity card;
  const DailyCardDetailScreen({super.key, required this.card});

  @override
  ConsumerState<DailyCardDetailScreen> createState() =>
      _DailyCardDetailScreenState();
}

class _DailyCardDetailScreenState
    extends ConsumerState<DailyCardDetailScreen> {
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

  Future<void> _addTransaction() async {
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
        creatorName: user.displayName.isEmpty ? 'Partner' : user.displayName,
        createdAt: DateTime.now(),
        amount: amount,
        type: _type,
        description: _descCtrl.text.trim(),
      );
      await ref.read(dailyCardRepositoryProvider).addTransaction(tx);
      if (mounted) {
        _amountCtrl.clear();
        _descCtrl.clear();
        setState(() => _saving = false);
        HapticFeedback.mediumImpact();
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
    final key = DailyCardKey(widget.card.cashbookId, widget.card.cardId);
    final asyncSummary = ref.watch(dailyCardSummaryProvider(key));
    final isIncome = _type == 'income';
    final accentColor = isIncome ? _kIncome : _kExpense;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(widget.card.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: _kText,
                letterSpacing: -0.3)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DailyCardHistoryScreen(card: widget.card),
                  ),
                );
              },
              icon: const Icon(Icons.history_rounded,
                  size: 17, color: _kAccent),
              label: const Text('History',
                  style: TextStyle(
                      color: _kAccent, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DailyCreditCardWidget(
                name: widget.card.name,
                number: widget.card.number,
                bankName: widget.card.bankName,
                colorIndex: widget.card.colorIndex,
                expanded: true,
              ),
              const SizedBox(height: 18),
              asyncSummary.when(
                loading: () => const SizedBox(
                    height: 70,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: _kAccent, strokeWidth: 2))),
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
                          color: _kIncome),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                          label: 'Expense',
                          value: summary.totalExpense,
                          color: _kExpense),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const Text('Add Transaction',
                  style: TextStyle(
                      color: _kText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kCardBorder),
                ),
                child: Row(children: [
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
                ]),
              ),
              const SizedBox(height: 14),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: TextStyle(
                        color: accentColor.withValues(alpha: 0.45),
                        fontSize: 28,
                        fontWeight: FontWeight.w800),
                    hintText: '0',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _addTransaction,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
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
                      : const Text('Add to this card',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
          Text(label,
              style: const TextStyle(
                  color: _kTextSub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('₹${CurrencyFormatter.format(value.abs())}',
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
        ],
      ),
    );
  }
}

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
            color:
                selected ? color.withValues(alpha: 0.30) : Colors.transparent,
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
