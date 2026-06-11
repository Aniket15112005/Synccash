// lib/features/transactions/presentation/widgets/transaction_list_item.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_details_sheet.dart';

final _timeFmt = DateFormat('hh:mm a');

// ─── Public widget (used by dashboard + history) ──────────────────────────────

class TransactionListItem extends ConsumerWidget {
  final TransactionEntity transaction;
  final String? currentUserId;

  /// Pass [showTimeline] = true when rendering inside the history screen
  /// so the vertical connector line is drawn.
  final bool showTimeline;
  final bool isLastInGroup;

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.currentUserId,
    this.showTimeline = false,
    this.isLastInGroup = false,
  });

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _delete(BuildContext ctx, WidgetRef ref) async {
    try {
      await ref
          .read(transactionRepositoryProvider)
          .deleteTransaction(transaction);
    } catch (e) {
      ref.invalidate(transactionsStreamProvider(transaction.cashbookId));
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: AppColors.expense,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  void _showActions(BuildContext ctx, WidgetRef ref) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _ActionSheet(
        transaction: transaction,
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
        title: const Text('Delete transaction?',
            style: TextStyle(
                color: Color(0xFFe5e7eb),
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        content: Text(
          'This will permanently remove the '
          '₹${transaction.amount.toStringAsFixed(0)} '
          '${transaction.type} entry.',
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
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
            // ── Timeline column ──────────────────────────────────────────
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

            // ── Content ──────────────────────────────────────────────────
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
                    // Left: meta + title
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tags row
                          Row(children: [
                            _MiniTag(
                              label: transaction.category.toUpperCase(),
                            ),
                            const SizedBox(width: 5),
                            _MiniTag(
                              label: transaction.creatorName.toUpperCase(),
                              highlight: isMe,
                            ),
                          ]),
                          const SizedBox(height: 5),
                          // Title
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
                          // Time
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Right: amount
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

// ─── Mini tag chip ─────────────────────────────────────────────────────────────

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, this.highlight = false});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0x284F5E78)
            : const Color(0x1AFFFFFF),
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

// ─── Action sheet ──────────────────────────────────────────────────────────────

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.transaction,
    required this.onViewDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final TransactionEntity transaction;
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
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 32, height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF374151),
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Summary
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
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MiniTag(label: transaction.category.toUpperCase()),
                  const SizedBox(height: 7),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD1D9E6),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      )),
                  const SizedBox(height: 3),
                  Text(transaction.creatorName,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      )),
                ],
              )),
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

        // Actions
        const SizedBox(height: 8),
        _SheetAction(
          icon: Icons.receipt_long_outlined,
          label: 'View Details',
          onTap: onViewDetails,
        ),
        _SheetDivider(),
        _SheetAction(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: onEdit,
        ),
        _SheetDivider(),
        _SheetAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: onDelete,
          destructive: true,
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

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
    final color = destructive
        ? const Color(0xFFf87171)
        : const Color(0xFFD1D9E6);
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 18, color: color.withOpacity(0.7)),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              )),
        ]),
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: const Color(0xFF1F2937),
      );
}

// ─── Edit sheet (keep your existing logic, restyled shell) ───────────────────

class _EditTransactionSheet extends StatefulWidget {
  final TransactionEntity transaction;
  final WidgetRef ref;
  const _EditTransactionSheet(
      {required this.transaction, required this.ref});

  @override
  State<_EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<_EditTransactionSheet> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _descCtrl =
        TextEditingController(text: widget.transaction.description);
    _amountCtrl = TextEditingController(
        text: widget.transaction.amount.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) return;
    setState(() => _loading = true);
    try {
      await widget.ref.read(transactionRepositoryProvider).updateTransaction(
            widget.transaction.copyWith(
              description: _descCtrl.text.trim(),
              amount: amount,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF161922),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            child: Text('Edit Transaction',
                style: TextStyle(
                  color: Color(0xFFD1D9E6),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                )),
          ),
          const SizedBox(height: 20),
          _StyledField(controller: _amountCtrl, label: 'Amount', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _StyledField(controller: _descCtrl, label: 'Description'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1F2937),
                foregroundColor: const Color(0xFFD1D9E6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

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
        labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
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