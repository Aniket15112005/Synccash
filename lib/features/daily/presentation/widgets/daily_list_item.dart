// lib/features/daily/presentation/widgets/daily_list_item.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kDailyAccent = Color(0xFF8B5CF6);
const _kText        = Color(0xFF1C1C1A); // warm charcoal
const _kTextSub     = Color(0xFF8A8882); // warm muted gray
const _kCard        = Color(0xFFF5F4F1); // frosted off-white
const _kCardBorder  = Color(0xFFF0EFED);
const _kTimelineLine = Color(0xFFD8D6D2); // warm neutral line

// Income
const _kIncomeFg     = Color(0xFF15803D);
const _kIncomeBg     = Color(0xFFD4F5E2); // slightly desaturated green tag
const _kIncomeAmount = Color(0xFF16A34A);

// Expense
const _kExpenseFg     = Color(0xFFB91C1C);
const _kExpenseBg     = Color(0xFFFDE8E8); // slightly desaturated red tag
const _kExpenseAmount = Color(0xFFDC2626);

// Creator tag
const _kCreatorBg = Color(0xFFE8E5FA); // slightly desaturated violet tag
const _kCreatorFg = Color(0xFF5B21B6);

final _timeFmt = DateFormat('hh:mm a');
final _dateFmt = DateFormat('dd MMM yyyy');

/// Shows the edit/delete action sheet for a daily entry.
///
/// Extracted out of [DailyListItem] so other widgets (e.g. the "Recent
/// Entries" row on the Daily home screen) can trigger the exact same
/// tap-to-view-options behaviour without duplicating the sheet UI.
void showDailyEntryActions(
  BuildContext context,
  WidgetRef ref,
  DailyEntryEntity entry, {
  String? currentUserId,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetCtx) => _DailyActionSheet(
      entry: entry,
      onViewDetails: () {
        Navigator.pop(sheetCtx);
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _DailyDetailsSheet(entry: entry),
        );
      },
      onEdit: () {
        Navigator.pop(sheetCtx);
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _DailyEditSheet(
            entry: entry,
            currentUserId: currentUserId,
          ),
        );
      },
      onDelete: () {
        Navigator.pop(sheetCtx);
        confirmDeleteDailyEntry(context, ref, entry);
      },
    ),
  );
}

/// Shows the delete-confirmation dialog for a daily entry.
void confirmDeleteDailyEntry(
  BuildContext context,
  WidgetRef ref,
  DailyEntryEntity entry,
) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      backgroundColor: _kCard,
      title: const Text('Delete this entry?',
          style: TextStyle(
              color: _kText,
              fontWeight: FontWeight.w800,
              fontSize: 17)),
      content: Text(
        '₹${entry.amount.toStringAsFixed(0)} ${entry.type} entry will be '
        'permanently removed from Daily.',
        style: const TextStyle(
            color: _kTextSub, fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: _kTextSub)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _kExpenseBg,
            foregroundColor: _kExpenseFg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          onPressed: () async {
            Navigator.pop(context);
            try {
              await ref
                  .read(dailyRepositoryProvider)
                  .deleteEntry(entry);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete: $e')),
                );
              }
            }
          },
          child: const Text('Delete',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class DailyListItem extends ConsumerWidget {
  final DailyEntryEntity entry;
  final String? currentUserId;
  final bool showTimeline;
  final bool isLastInGroup;

  const DailyListItem({
    super.key,
    required this.entry,
    this.currentUserId,
    this.showTimeline = false,
    this.isLastInGroup = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome  = entry.type.toLowerCase() == 'income';
    final isMe      = entry.createdBy == currentUserId;
    final title     = entry.description.isEmpty ? 'Daily entry' : entry.description;
    final timeStr   = _timeFmt.format(entry.createdAt);
    final amountStr =
        '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(entry.amount)}';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => showDailyEntryActions(context, ref, entry,
            currentUserId: currentUserId),
        behavior: HitTestBehavior.opaque,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTimeline)
                SizedBox(
                  width: 28,
                  child: Column(children: [
                    const SizedBox(height: 18),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isIncome
                            ? _kDailyAccent.withValues(alpha: 0.80)
                            : const Color(0xFFC4C2BE),
                        boxShadow: [
                          if (isIncome)
                            BoxShadow(
                              color: _kDailyAccent.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                        ],
                      ),
                    ),
                    if (!isLastInGroup)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          margin:
                              const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: _kTimelineLine,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ]),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: showTimeline ? 4 : 0,
                    top: 10,
                    bottom: isLastInGroup ? 0 : 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              _DailyTag(
                                label: isIncome ? 'INCOME' : 'EXPENSE',
                                bg: isIncome ? _kIncomeBg : _kExpenseBg,
                                fg: isIncome ? _kIncomeFg : _kExpenseFg,
                              ),
                              const SizedBox(width: 5),
                              _DailyTag(
                                label: entry.creatorName.toUpperCase(),
                                bg: isMe
                                    ? _kCreatorBg
                                    : const Color(0xFFEDECE9),
                                fg: isMe ? _kCreatorFg : _kTextSub,
                              ),
                            ]),
                            const SizedBox(height: 5),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                color: _kText,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_dateFmt.format(entry.createdAt)}  ·  $timeStr',
                              style: const TextStyle(
                                  fontSize: 11.5, color: _kTextSub),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          amountStr,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: isIncome
                                ? _kIncomeAmount
                                : _kExpenseAmount,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyTag extends StatelessWidget {
  const _DailyTag(
      {required this.label, required this.bg, required this.fg});
  final String label;
  final Color  bg;
  final Color  fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DailyActionSheet extends StatelessWidget {
  const _DailyActionSheet({
    required this.entry,
    required this.onViewDetails,
    required this.onEdit,
    required this.onDelete,
  });
  final DailyEntryEntity entry;
  final VoidCallback     onViewDetails;
  final VoidCallback     onEdit;
  final VoidCallback     onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type.toLowerCase() == 'income';
    final title    =
        entry.description.isEmpty ? 'Daily entry' : entry.description;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.10),
            blurRadius: 40,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // handle
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF000000).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // preview card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFECEBE8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kCardBorder),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _kText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.creatorName}  ·  ${_dateFmt.format(entry.createdAt)}',
                      style: const TextStyle(
                          color: _kTextSub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(entry.amount)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: isIncome ? _kIncomeAmount : _kExpenseAmount,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        // view details
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onViewDetails();
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kCardBorder,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    size: 17, color: _kText),
              ),
              const SizedBox(width: 14),
              const Text('View Details',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kText)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: _kTextSub),
            ]),
          ),
        ),
        Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: _kCardBorder),
        // edit
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onEdit();
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kCreatorBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_rounded,
                    size: 17, color: _kCreatorFg),
              ),
              const SizedBox(width: 14),
              const Text('Edit Entry',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kText)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: _kTextSub),
            ]),
          ),
        ),
        Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: _kCardBorder),
        // delete
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onDelete();
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kExpenseBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    size: 17, color: _kExpenseFg),
              ),
              const SizedBox(width: 14),
              const Text('Delete Entry',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kExpenseFg)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  size: 18,
                  color: _kExpenseFg.withValues(alpha: 0.4)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Details sheet (read-only)
// ─────────────────────────────────────────────────────────────────────────────

class _DailyDetailsSheet extends StatelessWidget {
  const _DailyDetailsSheet({required this.entry});
  final DailyEntryEntity entry;

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: _kTextSub,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor ?? _kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIncome  = entry.type.toLowerCase() == 'income';
    final title     =
        entry.description.isEmpty ? 'Daily entry' : entry.description;
    final amountStr =
        '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(entry.amount)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.10),
            blurRadius: 40,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF000000).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Entry Details',
                      style: const TextStyle(
                          color: _kText,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
                _DailyTag(
                  label: isIncome ? 'INCOME' : 'EXPENSE',
                  bg: isIncome ? _kIncomeBg : _kExpenseBg,
                  fg: isIncome ? _kIncomeFg : _kExpenseFg,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 20, color: _kCardBorder),
          ),
          // fields
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              _row('Amount', amountStr,
                  valueColor: isIncome ? _kIncomeAmount : _kExpenseAmount),
              _row('Description', title),
              _row('Added by', entry.creatorName),
              _row('Date',
                  '${_dateFmt.format(entry.createdAt)} · ${_timeFmt.format(entry.createdAt)}'),
              _row('Entry ID', entry.entryId),
              if (entry.lastEditedBy != null)
                _row('Last edited by', entry.lastEditedBy!),
            ]),
          ),
          const SizedBox(height: 8),
          // close button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: _kCardBorder,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Close',
                    style: TextStyle(
                        color: _kText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Edit sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DailyEditSheet extends ConsumerStatefulWidget {
  final DailyEntryEntity entry;
  final String?          currentUserId;
  const _DailyEditSheet({required this.entry, this.currentUserId});

  @override
  ConsumerState<_DailyEditSheet> createState() =>
      _DailyEditSheetState();
}

class _DailyEditSheetState extends ConsumerState<_DailyEditSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late String   _type;
  late DateTime _selectedDate;
  bool _saving = false;

  static const _accent  = Color(0xFF8B5CF6);
  static const _income  = Color(0xFF16A34A);
  static const _expense = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _type         = widget.entry.type;
    _selectedDate = widget.entry.createdAt;
    _amountCtrl   = TextEditingController(
        text: widget.entry.amount.toStringAsFixed(
            widget.entry.amount == widget.entry.amount.truncate()
                ? 0
                : 2));
    _descCtrl = TextEditingController(text: widget.entry.description);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _accent,
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
        _selectedDate = DateTime(
          picked.year, picked.month, picked.day,
          _selectedDate.hour, _selectedDate.minute,
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
    setState(() => _saving = true);
    try {
      final updated = widget.entry.copyWith(
        amount:       amount,
        type:         _type,
        description:  _descCtrl.text.trim(),
        createdAt:    _selectedDate,
        lastEditedBy: widget.currentUserId,
      );
      await ref.read(dailyRepositoryProvider).updateEntry(updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: _expense,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome    = _type == 'income';
    final accentColor = isIncome ? _income : _expense;
    final now         = DateTime.now();
    final isToday     = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final dateLabel   = isToday
        ? 'Today'
        : DateFormat('dd MMM yyyy').format(_selectedDate);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF2F1EE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF000000).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Edit Entry',
                style: TextStyle(
                    color: _kText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4)),
            const SizedBox(height: 22),

            // type toggle
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
                  child: _EditSeg(
                    label: 'Expense',
                    selected: _type == 'expense',
                    color: _expense,
                    onTap: () => setState(() => _type = 'expense'),
                  ),
                ),
                Expanded(
                  child: _EditSeg(
                    label: 'Income',
                    selected: _type == 'income',
                    color: _income,
                    onTap: () => setState(() => _type = 'income'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 22),

            // amount
            const Text('AMOUNT',
                style: TextStyle(
                    color: _kTextSub,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.9)),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              child: TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                    color: accentColor,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                      color: accentColor.withValues(alpha: 0.45),
                      fontSize: 34,
                      fontWeight: FontWeight.w800),
                  hintText: '0',
                  hintStyle: TextStyle(
                      color: _kTextSub.withValues(alpha: 0.40),
                      fontSize: 34,
                      fontWeight: FontWeight.w800),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 22),

            // description
            const Text('DESCRIPTION (OPTIONAL)',
                style: TextStyle(
                    color: _kTextSub,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.9)),
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
                  hintStyle: TextStyle(
                      color: _kTextSub.withValues(alpha: 0.6)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                        color: _accent, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // date
            const Text('DATE',
                style: TextStyle(
                    color: _kTextSub,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.9)),
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
                      color: _accent.withValues(alpha: 0.65)),
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
            const SizedBox(height: 30),

            // save
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
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
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSeg extends StatelessWidget {
  final String label;
  final bool   selected;
  final Color  color;
  final VoidCallback onTap;
  const _EditSeg({
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
          child: Text(label,
              style: TextStyle(
                color: selected ? color : _kTextSub,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              )),
        ),
      ),
    );
  }
}
