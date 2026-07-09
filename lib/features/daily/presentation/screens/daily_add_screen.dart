// lib/features/daily/presentation/screens/daily_add_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';

const _kDailyAccent = Color(0xFF8B5CF6);
const _kDailyBg     = Color(0xFFE8E7E4); // warm greige
const _kIncome      = Color(0xFF16A34A);
const _kExpense     = Color(0xFFDC2626);
const _kText        = Color(0xFF1C1C1A); // warm charcoal
const _kTextSub     = Color(0xFF8A8882); // warm muted gray
const _kCard        = Color(0xFFF5F4F1); // frosted off-white
const _kCardBorder  = Color(0xFFF0EFED); // very subtle warm border

class DailyAddScreen extends ConsumerStatefulWidget {
  const DailyAddScreen({super.key});

  @override
  ConsumerState<DailyAddScreen> createState() => _DailyAddScreenState();
}

class _DailyAddScreenState extends ConsumerState<DailyAddScreen> {
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  String   _type         = 'expense';
  DateTime _selectedDate = DateTime.now();
  bool     _saving       = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _kDailyAccent,
            onPrimary: Colors.white,
            surface: Color(0xFFF5F4F1),
            onSurface: _kText,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFFF5F4F1),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20))),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day,
            _selectedDate.hour, _selectedDate.minute, _selectedDate.second);
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

    final user       = ref.read(authProvider).value;
    final cashbookId = user?.currentCashbookId;
    if (user == null || cashbookId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active cashbook found')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final entry = DailyEntryEntity(
        entryId:     '',
        cashbookId:  cashbookId,
        createdBy:   user.uid,
        creatorName: user.displayName.isEmpty ? 'Partner' : user.displayName,
        createdAt:   _selectedDate,
        amount:      amount,
        type:        _type,
        description: _descCtrl.text.trim(),
      );
      await ref.read(dailyRepositoryProvider).addEntry(entry);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: _kExpense,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        _isToday ? 'Today' : DateFormat('dd MMM yyyy').format(_selectedDate);
    final isIncome    = _type == 'income';
    final accentColor = isIncome ? _kIncome : _kExpense;

    return Scaffold(
      backgroundColor: _kDailyBg,
      appBar: AppBar(
        backgroundColor: _kDailyBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kText),
        title: const Text('Add Daily Entry',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: _kText,
                letterSpacing: -0.3)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Type toggle ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kCardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.07),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
              const SizedBox(height: 28),

              // ── Amount ──────────────────────────────────────────────
              const _FieldLabel('AMOUNT'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kCardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: TextStyle(
                      color: accentColor.withValues(alpha: 0.45),
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
                    hintText: '0',
                    hintStyle: TextStyle(
                        color: _kTextSub.withValues(alpha: 0.40),
                        fontSize: 36,
                        fontWeight: FontWeight.w800),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Description ─────────────────────────────────────────
              const _FieldLabel('DESCRIPTION (OPTIONAL)'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kCardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(color: _kText, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: "What's this for?",
                    hintStyle:
                        TextStyle(color: _kTextSub.withValues(alpha: 0.6)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                          color: _kDailyAccent.withValues(alpha: 0.35),
                          width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Date ────────────────────────────────────────────────
              const _FieldLabel('DATE'),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _kCardBorder, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 16,
                        color: _kDailyAccent.withValues(alpha: 0.65)),
                    const SizedBox(width: 12),
                    Text(dateLabel,
                        style: const TextStyle(
                            color: _kText,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        size: 18,
                        color: _kTextSub.withValues(alpha: 0.50)),
                  ]),
                ),
              ),
              const SizedBox(height: 40),

              // ── Save button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kDailyAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Entry',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _kTextSub,
        fontWeight: FontWeight.w700,
        fontSize: 10.5,
        letterSpacing: 0.9,
      ),
    );
  }
}
