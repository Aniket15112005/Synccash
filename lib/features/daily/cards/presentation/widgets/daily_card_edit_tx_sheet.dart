// lib/features/daily/cards/presentation/widgets/daily_card_edit_tx_sheet.dart
//
// Bottom sheet used to edit an existing transaction that belongs to a single
// Daily Card. Saving only ever calls updateTransaction() scoped to
// tx.cashbookId/tx.cardId/tx.txId, so it can never touch another card, the
// main Daily list, or /transactions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';
import 'package:synccash/features/daily/cards/presentation/providers/daily_card_provider.dart';

const _kAccent = Color(0xFF8B5CF6);
const _kText = Color(0xFF1C1C1A);
const _kTextSub = Color(0xFF8A8882);
const _kCard = Color(0xFFF5F4F1);
const _kCardBorder = Color(0xFFF0EFED);
const _kIncome = Color(0xFF16A34A);
const _kExpense = Color(0xFFDC2626);

/// Opens the edit sheet for [tx]. Returns after the sheet is dismissed.
Future<void> showDailyCardEditTxSheet(
  BuildContext context, {
  required DailyCardTransactionEntity tx,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DailyCardEditTxSheet(tx: tx),
  );
}

class _DailyCardEditTxSheet extends ConsumerStatefulWidget {
  final DailyCardTransactionEntity tx;
  const _DailyCardEditTxSheet({required this.tx});

  @override
  ConsumerState<_DailyCardEditTxSheet> createState() =>
      _DailyCardEditTxSheetState();
}

class _DailyCardEditTxSheetState extends ConsumerState<_DailyCardEditTxSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late String _type;
  late DateTime _selectedDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: _formatAmount(widget.tx.amount));
    _descCtrl = TextEditingController(text: widget.tx.description);
    _type = widget.tx.type.toLowerCase() == 'income' ? 'income' : 'expense';
    _selectedDate = widget.tx.createdAt;
  }

  String _formatAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kAccent,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _kText,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        // Preserve the original time, only change the date
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
          _selectedDate.second,
        );
      });
    }
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
    setState(() => _saving = true);
    try {
      final updated = widget.tx.copyWith(
        amount: amount,
        type: _type,
        description: _descCtrl.text.trim(),
        createdAt: _selectedDate,
        lastEditedBy: user?.uid,
      );
      await ref.read(dailyCardRepositoryProvider).updateTransaction(updated);
      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
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
    final dateLabel = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFE8E7E4),
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
            const SizedBox(height: 16),
            const Text('Edit Transaction',
                style: TextStyle(
                    color: _kText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3)),
            const SizedBox(height: 16),
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
            const SizedBox(height: 12),
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
                    fontSize: 26,
                    fontWeight: FontWeight.w900),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                      color: accentColor.withValues(alpha: 0.55),
                      fontSize: 26,
                      fontWeight: FontWeight.w900),
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
            const SizedBox(height: 12),
            // ── Date picker row ───────────────────────────────────────────
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kCardBorder),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: _kAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: const TextStyle(
                          color: _kText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Change',
                      style: TextStyle(
                        color: _kAccent.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ─────────────────────────────────────────────────────────────
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
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
                    : const Text('Save changes',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
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
