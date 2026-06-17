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
import 'package:synccash/features/sales/data/models/sale_bill_model.dart';
import 'package:synccash/features/sales/domain/entities/sale_bill_entity.dart';
import 'package:synccash/features/sales/presentation/providers/sale_bill_provider.dart';
import 'package:synccash/features/sales/presentation/widgets/bill_no_dropdown_field.dart';

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
          // Synchronously look up the bill from the already-loaded provider
          // cache so the edit sheet opens with the bill pre-selected instantly,
          // with no visible loading delay. Falls back to a Firestore fetch
          // inside the sheet only if the bill isn't in the cache yet.
          SaleBillEntity? cachedBill;
          final billId = transaction.linkedSaleBillId;
          if (billId != null && billId.isNotEmpty) {
            final bills =
                ref.read(filteredSaleBillsProvider).asData?.value ?? [];
            try {
              cachedBill =
                  bills.firstWhere((b) => b.saleBillId == billId);
            } catch (_) {
              // not in cache — sheet will fall back to Firestore fetch
            }
          }
          showModalBottomSheet(
            context: ctx,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _EditTransactionSheet(
              transaction:  transaction,
              ref:          ref,
              initialBill:  cachedBill,
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
    // Bill number lookup
    final _billMap = ref.watch(saleBillNumberMapProvider).asData?.value ?? {};
    final _linkedId = transaction.linkedSaleBillId;
    final _billNo = (_linkedId != null && _linkedId.isNotEmpty)
        ? _billMap[_linkedId]
        : null;

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
                          if (_billNo != null && _billNo.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'B.no: $_billNo',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
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
  // ADDED: pre-resolved bill from the provider cache — avoids the async
  // Firestore fetch so the dropdown appears instantly when the sheet opens.
  final SaleBillEntity? initialBill;

  const _EditTransactionSheet({
    required this.transaction,
    required this.ref,
    this.initialBill,
  });

  @override
  State<_EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<_EditTransactionSheet> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late DateTime _selectedDate;
  late String _category;

  // ADDED: bill link state
  SaleBillEntity? _selectedBill;
  bool _isObPayment = false;
  bool _loadingBill = false;

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
        : raw.toLowerCase() == 'upi'
            ? 'UPI'
            : raw.toLowerCase() == 'cb'
                ? 'CB'
                : raw[0].toUpperCase() + raw.substring(1).toLowerCase();

    // ADDED: rebuild when description changes so BillNoDropdownField updates
    _descCtrl.addListener(_onDescChanged);

    // ADDED: use the pre-resolved bill from the cache first (instant, no
    // spinner). Only fall back to a Firestore fetch if the caller couldn't
    // find it in the provider cache (e.g. stream not yet loaded).
    final billId = widget.transaction.linkedSaleBillId;
    if (billId != null && billId.isNotEmpty) {
      if (widget.initialBill != null) {
        // Already resolved — set synchronously, no loading state needed.
        _selectedBill = widget.initialBill;
      } else {
        // Cache miss — fetch from Firestore (shows spinner until done).
        _loadExistingBill(widget.transaction.cashbookId, billId);
      }
    }
  }

  // ADDED
  void _onDescChanged() => setState(() {});

  // ADDED: fetch the SaleBillEntity for the existing linkedSaleBillId
  Future<void> _loadExistingBill(String cashbookId, String billId) async {
    if (!mounted) return;
    setState(() => _loadingBill = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('sale_bills')
          .doc(billId)
          .get();
      if (mounted && doc.exists) {
        setState(() => _selectedBill = SaleBillModel.fromFirestore(doc));
      }
    } catch (_) {
      // silently ignore — dropdown will just show unselected
    } finally {
      if (mounted) setState(() => _loadingBill = false);
    }
  }

  @override
  void dispose() {
    _descCtrl.removeListener(_onDescChanged);
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

      // CHANGED: build entity directly (not via copyWith) so that
      // linkedSaleBillId: null is forwarded as-is to the repo, which
      // will call FieldValue.delete() and properly clear any old link.
      final updated = TransactionEntity(
        transactionId:    widget.transaction.transactionId,
        cashbookId:       widget.transaction.cashbookId,
        createdBy:        widget.transaction.createdBy,
        creatorName:      widget.transaction.creatorName,
        createdAt:        _selectedDate,
        amount:           amount,
        type:             widget.transaction.type,
        category:         _category.toLowerCase(),
        description:      _descCtrl.text.trim(),
        lastEditedBy:     currentUser?.uid,
        linkedSaleBillId: _selectedBill?.saleBillId,
        // ^ null when user cleared the bill — repo uses FieldValue.delete()
      );

      await widget.ref
          .read(transactionRepositoryProvider)
          .updateTransaction(updated);

      // Stamp or clear isObPayment / obPartyName.
      // These fields are NOT part of TransactionEntity so updateTransaction
      // never touches them. We write them in a separate update so that
      // party_detail_screen's Strategy-1 detection works correctly:
      //   • editing to OB  → isObPayment:true + obPartyName = description
      //   • editing away   → both fields deleted (FieldValue.delete)
      final txDocRef = FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(widget.transaction.cashbookId)
          .collection('transactions')
          .doc(widget.transaction.transactionId);

      if (_isObPayment) {
        await txDocRef.update({
          'isObPayment': true,
          'obPartyName': _descCtrl.text.trim(),
        });
      } else {
        await txDocRef.update({
          'isObPayment': FieldValue.delete(),
          'obPartyName': FieldValue.delete(),
        });
      }

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
        // CHANGED: constrain max height so the sheet is scrollable when the
        // bill dropdown is visible
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF161922),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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

            // Category
            _SheetLabel('Category'),
            const SizedBox(height: 8),
            _SheetCategoryToggle(
              selected: _category,
              showBank: kIsWeb || defaultTargetPlatform != TargetPlatform.android,
              onSwitch: (cat) => setState(() {
                _category = cat;
                // ADDED: clear bill when switching away from Wholesale
                if (cat != 'Wholesale') {
                  _selectedBill = null;
                  _isObPayment  = false;
                }
              }),
            ),

            // ADDED: bill dropdown — visible only for Wholesale transactions.
            // Shows a spinner while the existing bill is being fetched, then
            // renders the dropdown with the current bill pre-selected so the
            // user can change it or clear it.
            if (_category == 'Wholesale') ...[
              if (_loadingBill)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Loading linked bill…',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                BillNoDropdownField(
                  partyName:    _descCtrl.text,
                  selectedBill: _selectedBill,
                  onBillSelected: (bill) => setState(() {
                    _selectedBill = bill;
                    _isObPayment  = false;
                  }),
                  isObSelected: _isObPayment,
                  onObSelected: () => setState(() {
                    _isObPayment  = true;
                    _selectedBill = null;
                  }),
                ),
            ],

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
      {required this.selected, required this.onSwitch, this.showBank = true});
  final String selected;
  final void Function(String) onSwitch;
  final bool showBank;

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
        children: ['Retail', 'Wholesale', if (showBank) 'Bank', 'UPI', if (showBank) 'CB'].map((cat) {
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
