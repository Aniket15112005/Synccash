// lib/features/transactions/presentation/widgets/transaction_list_item.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_details_sheet.dart';
import 'package:synccash/features/transactions/data/services/recycle_bin_service.dart';

final _timeFmt = DateFormat('hh:mm a');
final _dateFmt = DateFormat('dd MMM yyyy');

// ─── Public widget (used by dashboard + history) ──────────────────────────────

class TransactionListItem extends ConsumerWidget {
  final TransactionEntity transaction;
  final String? currentUserId;
  final bool showTimeline;
  final bool isLastInGroup;

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.currentUserId,
    this.showTimeline = false,
    this.isLastInGroup = false,
  });

  Future<void> _delete(BuildContext ctx, WidgetRef ref) async {
    try {
      await RecycleBinService.softDelete(transaction);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Failed to move to recycle bin: $e'),
          backgroundColor: AppColors.expense,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  void _showActions(BuildContext ctx, WidgetRef ref) {
    HapticFeedback.lightImpact();

    final uid = currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    final isCreator = uid != null && uid == transaction.createdBy;
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    final canEdit = isAndroid ? isCreator : true;
    final canDelete = !isAndroid;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _ActionSheet(
        transaction: transaction,
        canEdit: canEdit,
        canDelete: canDelete,
        onViewDetails: () {
          Navigator.pop(sheetCtx);
          showModalBottomSheet(
            context: ctx,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            backgroundColor: Colors.transparent,
            builder: (_) => TransactionDetailsSheet(transaction: transaction),
          );
        },
        onEdit: () {
          Navigator.pop(sheetCtx);
          showModalBottomSheet(
            context: ctx,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _EditTransactionSheet(
              transaction: transaction,
              ref: ref,
            ),
          );
        },
        onDelete: () {
          Navigator.pop(sheetCtx);
          _confirmDelete(ctx, ref);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, WidgetRef ref) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF161922),
        title: const Text('Move to Recycle Bin?',
            style: TextStyle(
                color: Color(0xFFe5e7eb),
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        content: Text(
          '₹${transaction.amount.toStringAsFixed(0)} ${transaction.type} entry '
          'will be kept for 15 days — restore it anytime from Settings.',
          style: const TextStyle(
              color: Color(0xFF9ca3af), fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6b7280))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3d1f1f),
              foregroundColor: const Color(0xFFf87171),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _delete(ctx, ref);
            },
            child: const Text('Move to Bin',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = transaction.type.toLowerCase() == 'income';
    final isMe = transaction.createdBy == currentUserId;
    final title = transaction.description.isEmpty
        ? transaction.category
        : transaction.description;
    final timeStr = _timeFmt.format(transaction.createdAt);
    final amountStr =
        '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(transaction.amount)}';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _showActions(context, ref),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTimeline)
              SizedBox(
                width: 28,
                child: Column(children: [
                  const SizedBox(height: 18),
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isIncome
                          ? const Color(0xBBD7E1EE)
                          : const Color(0x70828FA0),
                      border: Border.all(
                        color: isIncome
                            ? const Color(0x55D7E1EE)
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
                            _MiniTag(label: transaction.category.toUpperCase()),
                            const SizedBox(width: 5),
                            _MiniTag(
                              label: transaction.creatorName.toUpperCase(),
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
                            '${_dateFmt.format(transaction.createdAt)}  ·  $timeStr',
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
    );
  }
}

// ─── Mini tag chip ────────────────────────────────────────────────────────────

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, this.highlight = false});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: highlight ? const Color(0x284F5E78) : const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: highlight
              ? const Color(0xCCA0B0C8)
              : const Color(0x997A8A9E),
        ),
      ),
    );
  }
}

// ─── Action sheet ─────────────────────────────────────────────────────────────

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.transaction,
    required this.canEdit,
    required this.canDelete,
    required this.onViewDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final TransactionEntity transaction;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onViewDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type.toLowerCase() == 'income';
    final title = transaction.description.isEmpty
        ? transaction.category
        : transaction.description;

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
          width: 32, height: 3,
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
                    _MiniTag(label: transaction.category.toUpperCase()),
                    const SizedBox(height: 7),
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
                      '${transaction.creatorName}  ·  ${_dateFmt.format(transaction.createdAt)}',
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(transaction.amount)}',
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
        _SheetAction(
          icon: Icons.receipt_long_outlined,
          label: 'View Details',
          onTap: onViewDetails,
        ),
        if (canEdit) ...[
          _SheetDivider(),
          _SheetAction(icon: Icons.edit_outlined, label: 'Edit', onTap: onEdit),
        ],
        if (canDelete) ...[
          _SheetDivider(),
          _SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            onTap: onDelete,
            destructive: true,
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ─── Sheet action row ─────────────────────────────────────────────────────────

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? const Color(0xFFf87171) : const Color(0xFFD1D9E6);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: color)),
        ]),
      ),
    );
  }
}

// ─── Sheet divider ────────────────────────────────────────────────────────────

class _SheetDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: const Color(0xFF1F2937),
      );
}

// ─── Edit sheet ───────────────────────────────────────────────────────────────

class _EditTransactionSheet extends StatefulWidget {
  final TransactionEntity transaction;
  final WidgetRef ref;

  const _EditTransactionSheet({required this.transaction, required this.ref});

  @override
  State<_EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<_EditTransactionSheet> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late DateTime _selectedDate;
  late String _category;

  // web / iOS PWA only
  String? _selectedCreatorUid;
  String? _selectedCreatorName;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.transaction.description);
    _amountCtrl = TextEditingController(
        text: widget.transaction.amount.toStringAsFixed(0));
    _selectedDate = widget.transaction.createdAt;

    // Normalise to title-case: 'retail' → 'Retail'
    final raw = widget.transaction.category;
    _category = raw.isEmpty
        ? 'Retail'
        : raw[0].toUpperCase() + raw.substring(1).toLowerCase();

    _selectedCreatorUid = widget.transaction.createdBy;
    _selectedCreatorName = widget.transaction.creatorName;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
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
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3B82F6),
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
    setState(() => _loading = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      await widget.ref.read(transactionRepositoryProvider).updateTransaction(
            widget.transaction.copyWith(
              description:  _descCtrl.text.trim(),
              amount:       amount,
              createdAt:    _selectedDate,
              category:     _category.toLowerCase(),
              createdBy:    _selectedCreatorUid  ?? widget.transaction.createdBy,
              creatorName:  _selectedCreatorName ?? widget.transaction.creatorName,
              lastEditedBy: currentUser?.uid,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: const Color(0xFF991b1b),
          ),
        );
      }
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        _isToday ? 'Today' : DateFormat('dd MMM yyyy').format(_selectedDate);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF161922),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
            width: 32, height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF374151),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Edit Transaction',
              style: TextStyle(
                  color: Color(0xFFD1D9E6),
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 20),

          // Amount
          _StyledField(
            controller: _amountCtrl,
            label: 'Amount',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),

          // Description
          _StyledField(controller: _descCtrl, label: 'Description'),
          const SizedBox(height: 12),

          // Category — visible to ALL users (Android and iOS/web)
          _SheetLabel('Category'),
          const SizedBox(height: 8),
          _SheetCategoryToggle(
            selected: _category,
            onSwitch: (cat) => setState(() => _category = cat),
          ),
          const SizedBox(height: 12),

          // Date
          GestureDetector(
            onTap: _pickDate,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0E12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.calendar_today_rounded,
                      size: 15, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Date',
                          style: TextStyle(
                              color: Color(0xFF6B7280), fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        '$dateLabel  ·  ${DateFormat('EEEE').format(_selectedDate)}',
                        style: const TextStyle(
                            color: Color(0xFFD1D9E6),
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFF4B5563)),
              ]),
            ),
          ),

          // Creator — web / iOS PWA only (kIsWeb = true on both web and iOS PWA)
          if (kIsWeb) ...[
            const SizedBox(height: 12),
            _SheetLabel('Created By'),
            const SizedBox(height: 8),
            _SheetCreatorSelector(
              cashbookId:   widget.transaction.cashbookId,
              selectedUid:  _selectedCreatorUid,
              selectedName: _selectedCreatorName,
              onChanged: (uid, name) => setState(() {
                _selectedCreatorUid  = uid;
                _selectedCreatorName = name;
              }),
            ),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1d4ed8),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1F2937),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ─── Sheet label ──────────────────────────────────────────────────────────────

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2),
        ),
      );
}

// ─── Category toggle — Retail / Wholesale ─────────────────────────────────────

class _SheetCategoryToggle extends StatelessWidget {
  const _SheetCategoryToggle(
      {required this.selected, required this.onSwitch});
  final String selected;
  final void Function(String) onSwitch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: ['Retail', 'Wholesale'].map((cat) {
          final active = selected == cat;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSwitch(cat);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF1F2937)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF374151)
                        : Colors.transparent,
                  ),
                ),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: active
                          ? const Color(0xFFD1D9E6)
                          : const Color(0xFF6B7280),
                      fontSize: 14,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w400,
                    ),
                    child: Text(cat),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Creator selector — web / iOS PWA only ────────────────────────────────────

class _SheetCreatorSelector extends StatefulWidget {
  const _SheetCreatorSelector({
    required this.cashbookId,
    required this.selectedUid,
    required this.selectedName,
    required this.onChanged,
  });
  final String cashbookId;
  final String? selectedUid;
  final String? selectedName;
  final void Function(String uid, String name) onChanged;

  @override
  State<_SheetCreatorSelector> createState() =>
      _SheetCreatorSelectorState();
}

class _SheetCreatorSelectorState extends State<_SheetCreatorSelector> {
  List<Map<String, String>> _members = [];
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(widget.cashbookId)
          .get();
      final raw =
          (doc.data() ?? {})['members'] as Map<String, dynamic>? ?? {};
      final list = raw.entries
          .map((e) => {'uid': e.key, 'name': e.value.toString()})
          .toList();
      if (mounted) setState(() => _members = list);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Could not load members',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
      );
    }
    if (_members.isEmpty) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: Color(0xFF6B7280)),
          ),
        ),
      );
    }

    // Guard: if stored uid is not in the loaded list, fall back to first member
    final validUid =
        _members.any((m) => m['uid'] == widget.selectedUid)
            ? widget.selectedUid
            : _members.first['uid'];

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validUid,
          dropdownColor: const Color(0xFF161922),
          style: const TextStyle(
              color: Color(0xFFD1D9E6), fontSize: 15),
          isExpanded: true,
          icon: const Icon(Icons.unfold_more_rounded,
              size: 18, color: Color(0xFF6B7280)),
          items: _members
              .map((m) => DropdownMenuItem<String>(
                    value: m['uid'],
                    child: Text(m['name']!),
                  ))
              .toList(),
          onChanged: (uid) {
            if (uid == null) return;
            final name =
                _members.firstWhere((m) => m['uid'] == uid)['name']!;
            widget.onChanged(uid, name);
          },
        ),
      ),
    );
  }
}

// ─── Styled text field ────────────────────────────────────────────────────────

class _StyledField extends StatelessWidget {
  const _StyledField({
    required this.controller,
    required this.label,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Color(0xFFD1D9E6), fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0C0E12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1F2937)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1F2937)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF374151)),
        ),
      ),
    );
  }
}