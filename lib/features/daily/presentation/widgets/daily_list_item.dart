// lib/features/daily/presentation/widgets/daily_list_item.dart
//
// Simplified row widget for Daily entries — adapted from
// transaction_list_item.dart but with no category tag, no bill number,
// and no party-picker/edit-sheet complexity (Daily entries have no category
// and no bill linking).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';

const _kDailyAccent = Color(0xFF8B5CF6);

final _timeFmt = DateFormat('hh:mm a');
final _dateFmt = DateFormat('dd MMM yyyy');

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

  void _showActions(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _DailyActionSheet(
        entry: entry,
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
          _confirmDelete(context, ref);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF161922),
        title: const Text('Delete this entry?',
            style: TextStyle(
                color: Color(0xFFe5e7eb),
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        content: Text(
          '₹${entry.amount.toStringAsFixed(0)} ${entry.type} entry will be '
          'permanently removed from Daily.',
          style: const TextStyle(
              color: Color(0xFF9ca3af), fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6b7280))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3d1f1f),
              foregroundColor: const Color(0xFFf87171),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(dailyRepositoryProvider).deleteEntry(entry);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = entry.type.toLowerCase() == 'income';
    final isMe = entry.createdBy == currentUserId;
    final title = entry.description.isEmpty ? 'Daily entry' : entry.description;
    final timeStr = _timeFmt.format(entry.createdAt);
    final amountStr =
        '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(entry.amount)}';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _showActions(context, ref),
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
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isIncome
                            ? _kDailyAccent.withValues(alpha: 0.75)
                            : const Color(0x70828FA0),
                        border: Border.all(
                          color: isIncome
                              ? _kDailyAccent.withValues(alpha: 0.35)
                              : const Color(0x3C828FA0),
                          width: 1,
                        ),
                      ),
                    ),
                    if (!isLastInGroup)
                      Expanded(
                        child: Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          color: const Color(0x0DFFFFFF),
                        ),
                      ),
                  ]),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: showTimeline ? 4 : 0,
                    top: 10,
                    bottom: isLastInGroup ? 0 : 2,
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
                                color: isIncome
                                    ? const Color(0xFF5CB87A)
                                    : const Color(0xFFD96C6C),
                              ),
                              const SizedBox(width: 5),
                              _DailyTag(
                                label: entry.creatorName.toUpperCase(),
                                highlight: isMe,
                              ),
                            ]),
                            const SizedBox(height: 5),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                                color: isIncome
                                    ? const Color(0xEDD7E1EE)
                                    : const Color(0xD0A5B0C0),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_dateFmt.format(entry.createdAt)}  ·  $timeStr',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4B5563),
                              ),
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
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            letterSpacing: -0.3,
                            color: isIncome
                                ? const Color(0xF0E1EBF8)
                                : const Color(0xCCA0AEBE),
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
  const _DailyTag({required this.label, this.highlight = false, this.color});
  final String label;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color != null
        ? color!.withValues(alpha: 0.14)
        : (highlight ? const Color(0x2A8B5CF6) : const Color(0x1AFFFFFF));
    final fg = color ?? (highlight ? _kDailyAccent : const Color(0x997A8A9E));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }
}

class _DailyActionSheet extends StatelessWidget {
  const _DailyActionSheet({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });
  final DailyEntryEntity entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type.toLowerCase() == 'income';
    final title = entry.description.isEmpty ? 'Daily entry' : entry.description;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 32,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF374151),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0E12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD1D9E6),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.creatorName}  ·  ${_dateFmt.format(entry.createdAt)}',
                      style:
                          const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
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
                  fontFamily: 'monospace',
                  letterSpacing: -0.5,
                  color: isIncome
                      ? const Color(0xF0E1EBF8)
                      : const Color(0xCCA0AEBE),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onEdit();
          },
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.edit_rounded, size: 18, color: Color(0xFF8B5CF6)),
              SizedBox(width: 12),
              Text('Edit',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8B5CF6))),
            ]),
          ),
        ),
        Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: const Color(0xFF1F2937),
        ),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onDelete();
          },
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFf87171)),
              SizedBox(width: 12),
              Text('Delete',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFf87171))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Edit sheet — pre-filled with existing entry values
// ─────────────────────────────────────────────────────────────────────────────

class _DailyEditSheet extends ConsumerStatefulWidget {
  final DailyEntryEntity entry;
  final String? currentUserId;
  const _DailyEditSheet({required this.entry, this.currentUserId});

  @override
  ConsumerState<_DailyEditSheet> createState() => _DailyEditSheetState();
}

class _DailyEditSheetState extends ConsumerState<_DailyEditSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late String _type;
  late DateTime _selectedDate;
  bool _saving = false;

  static const _accent   = Color(0xFF8B5CF6);
  static const _income   = Color(0xFF5CB87A);
  static const _expense  = Color(0xFFD96C6C);
  static const _bg       = Color(0xFF111113);
  static const _surface  = Color(0xFF161922);
  static const _border   = Color(0xFF1F2937);
  static const _textMain = Color(0xFFD1D9E6);
  static const _textMute = Color(0xFF6B7280);

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
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: Colors.white,
            surface: Color(0xFF161922),
            onSurface: Color(0xFFD1D9E6),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF111316),
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
          _selectedDate.hour, _selectedDate.minute, _selectedDate.second,
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
        amount:      amount,
        type:        _type,
        description: _descCtrl.text.trim(),
        createdAt:   _selectedDate,
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
            backgroundColor: const Color(0xFF991b1b),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome   = _type == 'income';
    final accentColor = isIncome ? _income : _expense;
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final dateLabel = isToday
        ? 'Today'
        : DateFormat('dd MMM yyyy').format(_selectedDate);

    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: _border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Title
            const Text('Edit Entry',
                style: TextStyle(
                    color: _textMain,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // ── Type toggle ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Expanded(
                  child: _EditTypeSegment(
                    label: 'Expense',
                    selected: _type == 'expense',
                    color: _expense,
                    onTap: () => setState(() => _type = 'expense'),
                  ),
                ),
                Expanded(
                  child: _EditTypeSegment(
                    label: 'Income',
                    selected: _type == 'income',
                    color: _income,
                    onTap: () => setState(() => _type = 'income'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Amount ───────────────────────────────────────────────
            Text('AMOUNT',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                  color: accentColor,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace'),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                    color: accentColor.withValues(alpha: 0.6),
                    fontSize: 32,
                    fontWeight: FontWeight.w800),
                hintText: '0',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                border: InputBorder.none,
              ),
            ),
            Container(
                height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 20),

            // ── Description ──────────────────────────────────────────
            Text('DESCRIPTION (OPTIONAL)',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: "What's this for?",
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Date ─────────────────────────────────────────────────
            Text('DATE',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(width: 10),
                  Text(dateLabel,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
                ]),
              ),
            ),
            const SizedBox(height: 28),

            // ── Save button ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes',
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

class _EditTypeSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _EditTypeSegment({
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                color: selected ? color : Colors.white38,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              )),
        ),
      ),
    );
  }
}
