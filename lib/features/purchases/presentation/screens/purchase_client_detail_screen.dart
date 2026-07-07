
// lib/features/purchases/presentation/screens/purchase_client_detail_screen.dart
//
// Mirrors lib/features/sales/presentation/screens/party_detail_screen.dart
// Bills are now tappable — tapping opens PurchaseClientBillDetailScreen.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/purchase_bill_entity.dart';
import '../providers/purchase_client_provider.dart';
import '../providers/purchase_bill_provider.dart';
import 'purchase_client_bill_detail_screen.dart';

class _T {
  static const bg      = Color(0xFF0F1011);
  static const card    = Color(0xFF1A1B1E);
  static const card2   = Color(0xFF1E1F22);
  static const border  = Color(0xFF2C2D32);
  static const muted   = Color(0xFF8C8E9A);
  static const text    = Color(0xFFF1F2F5);
  static const accent  = Color(0xFFF59E0B);
  static const green   = Color(0xFF4ADE80);
  static const amber   = Color(0xFFFBBF24);
  static const red     = Color(0xFFFC8181);
}

class PurchaseClientDetailScreen extends ConsumerStatefulWidget {
  final String clientName;
  const PurchaseClientDetailScreen({super.key, required this.clientName});

  @override
  ConsumerState<PurchaseClientDetailScreen> createState() =>
      _PurchaseClientDetailScreenState();
}

class _PurchaseClientDetailScreenState
    extends ConsumerState<PurchaseClientDetailScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  Map<String, double> _paidPerBill = {};
  double _obPaid = 0.0;

  @override
  void initState() {
    super.initState();
    _startTxStream();
  }

  void _startTxStream() {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    final clientLow = widget.clientName.trim().toLowerCase();

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'expense')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      double obPaid = 0.0;
      final perBill = <String, double>{};
      for (final d in snap.docs) {
        final raw = d.data();
        final linkedId = raw['linkedPurchaseBillId'] as String?;
        final amount = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final desc = (raw['description'] as String? ?? '').toLowerCase();
        final isObForThisClient = raw['isObPayment'] == true &&
            (raw['obPartyName'] as String? ?? '').trim().toLowerCase() ==
                clientLow;
        if (linkedId != null && linkedId.isNotEmpty) {
          perBill[linkedId] = (perBill[linkedId] ?? 0.0) + amount;
        } else if (isObForThisClient || desc.contains(clientLow)) {
          obPaid += amount;
        }
      }
      setState(() {
        _paidPerBill = perBill;
        _obPaid = obPaid;
      });
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    super.dispose();
  }

  Future<void> _editOpeningBalance(double currentOb) async {
    final ctrl = TextEditingController(
        text: currentOb == 0 ? '' : currentOb.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _T.card2,
        title: const Text('Opening Balance', style: TextStyle(color: _T.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: _T.text),
          decoration: const InputDecoration(
            hintText: 'Amount owed to this client',
            hintStyle: TextStyle(color: _T.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _T.muted)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('Save', style: TextStyle(color: _T.accent)),
          ),
        ],
      ),
    );
    if (result == null) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    await ref
        .read(purchaseClientActionsProvider.notifier)
        .setOpeningBalance(cashbookId, widget.clientName, result);
  }

  Future<void> _editBill(PurchaseBillEntity bill) async {
    HapticFeedback.selectionClick();
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditBillSheet(bill: bill, cashbookId: cashbookId),
    );
  }

  Future<void> _deleteBill(PurchaseBillEntity bill) async {
    HapticFeedback.mediumImpact();
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _T.card2,
        title: const Text('Delete Bill?', style: TextStyle(color: _T.text)),
        content: Text('Bill #${bill.billNumber} will be permanently deleted.',
            style: const TextStyle(color: _T.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: _T.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(purchaseBillActionsProvider.notifier)
        .deleteBill(cashbookId, bill.purchaseBillId);
  }

  void _openBillDetail(PurchaseBillEntity bill, List<PurchaseBillEntity> allBills) {
    HapticFeedback.selectionClick();
    final precomputedPaid = _paidPerBill[bill.purchaseBillId] ?? 0.0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseClientBillDetailScreen(
          bill:            bill,
          billCount:       allBills.length,
          precomputedPaid: precomputedPaid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(purchaseClientsProvider);
    final billsAsync   = ref.watch(purchaseBillsForClientProvider(widget.clientName));
    final client = clientsAsync.asData?.value.where(
        (c) => c.clientName.toLowerCase() == widget.clientName.toLowerCase());
    final openingBalance =
        (client != null && client.isNotEmpty) ? client.first.openingBalance : 0.0;
    final bills = billsAsync.asData?.value ?? [];

    final totalBilled = bills.fold<double>(0, (sum, b) => sum + b.billAmount);
    final totalBillsPaid = bills.fold<double>(
        0, (sum, b) => sum + (_paidPerBill[b.purchaseBillId] ?? 0.0));
    final obRemaining = (openingBalance - _obPaid).clamp(0.0, double.infinity);
    final closingBalance =
        (obRemaining + totalBilled - totalBillsPaid).clamp(0.0, double.infinity);
    final totalDue = closingBalance;
    final dateFmt = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: _T.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: _T.text),
                  ),
                  Expanded(
                    child: Text(widget.clientName,
                        style: const TextStyle(
                            color: _T.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _T.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _T.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Due',
                            style: TextStyle(color: _T.muted, fontSize: 12)),
                        InkWell(
                          onTap: () => _editOpeningBalance(openingBalance),
                          child: const Row(
                            children: [
                              Text('Edit opening balance',
                                  style: TextStyle(
                                      color: _T.accent, fontSize: 12)),
                              SizedBox(width: 4),
                              Icon(Icons.edit_rounded,
                                  size: 12, color: _T.accent),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('₹${totalDue.abs().toStringAsFixed(0)}',
                        style: TextStyle(
                            color: totalDue >= 0 ? _T.red : _T.green,
                            fontSize: 28,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                        'Opening balance: ₹${openingBalance.toStringAsFixed(0)}'
                        '${_obPaid > 0 ? ' (₹${obRemaining.toStringAsFixed(0)} remaining)' : ''}',
                        style: const TextStyle(color: _T.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  Icon(Icons.receipt_long_rounded, size: 16, color: _T.muted),
                  SizedBox(width: 6),
                  Text('All Bills',
                      style: TextStyle(
                          color: _T.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  SizedBox(width: 6),
                  Text('(tap to view details)',
                      style: TextStyle(color: _T.muted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: bills.isEmpty
                  ? const Center(
                      child: Text('No bills yet',
                          style: TextStyle(color: _T.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: bills.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final bill = bills[i];
                        final paidOnBill =
                            _paidPerBill[bill.purchaseBillId] ?? 0.0;
                        final pendingOnBill =
                            (bill.billAmount - paidOnBill)
                                .clamp(0.0, double.infinity);
                        final isSettled = pendingOnBill <= 0;
                        final isPartial = !isSettled && paidOnBill > 0;
                        final statusColor = isSettled
                            ? _T.green
                            : isPartial
                                ? _T.amber
                                : _T.red;
                        final statusLabel = isSettled
                            ? 'PAID'
                            : isPartial
                                ? 'PARTIAL'
                                : 'PENDING';

                        // Tappable bill row — opens PurchaseClientBillDetailScreen
                        return InkWell(
                          onTap: () => _openBillDetail(bill, bills),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _T.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _T.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Bill #${bill.billNumber}',
                                          style: const TextStyle(
                                              color: _T.text,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(dateFmt.format(bill.billDate),
                                          style: const TextStyle(
                                              color: _T.muted, fontSize: 12)),
                                      if (bill.billNote != null &&
                                          bill.billNote!.trim().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(bill.billNote!,
                                            style: const TextStyle(
                                                color: _T.muted, fontSize: 12),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        '₹${bill.billAmount.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            color: _T.text,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700)),
                                    if (!isSettled) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                          '₹${pendingOnBill.toStringAsFixed(0)} pending',
                                          style: const TextStyle(
                                              color: _T.amber,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(statusLabel,
                                          style: TextStyle(
                                              color: statusColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                // Chevron indicator (tap hint) + ⋮ menu
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded,
                                    color: _T.muted, size: 18),
                                _BillRowMenu(
                                  onEdit:   () => _editBill(bill),
                                  onDelete: () => _deleteBill(bill),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Three-dot menu for a bill row ──────────────────────────────────────────

class _BillRowMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _BillRowMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert_rounded, color: _T.muted, size: 18),
        color: _T.card2,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _T.border)),
        onSelected: (v) {
          if (v == 'edit') onEdit();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'edit',
            height: 44,
            child: Row(
              children: const [
                Icon(Icons.edit_outlined, color: _T.accent, size: 16),
                SizedBox(width: 10),
                Text('Edit Bill',
                    style: TextStyle(
                        color: _T.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            height: 44,
            child: Row(
              children: const [
                Icon(Icons.delete_outline_rounded, color: _T.red, size: 16),
                SizedBox(width: 10),
                Text('Delete Bill',
                    style: TextStyle(
                        color: _T.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
}

// ─── Edit bill sheet ─────────────────────────────────────────────────────────

class _EditBillSheet extends ConsumerStatefulWidget {
  final PurchaseBillEntity bill;
  final String cashbookId;
  const _EditBillSheet({required this.bill, required this.cashbookId});

  @override
  ConsumerState<_EditBillSheet> createState() => _EditBillSheetState();
}

class _EditBillSheetState extends ConsumerState<_EditBillSheet> {
  final _formKey    = GlobalKey<FormState>();
  late final _billNoCtrl = TextEditingController(text: widget.bill.billNumber);
  late final _amountCtrl = TextEditingController(
      text: widget.bill.billAmount.toStringAsFixed(0));
  late final _noteCtrl   = TextEditingController(
      text: widget.bill.billNote ?? '');
  late DateTime _date    = widget.bill.billDate;
  bool _submitting       = false;

  @override
  void dispose() {
    _billNoCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final updated = PurchaseBillEntity(
        purchaseBillId:    widget.bill.purchaseBillId,
        clientName:        widget.bill.clientName,
        billNumber:        _billNoCtrl.text.trim(),
        billAmount:        double.parse(_amountCtrl.text.trim()),
        billDate:          _date,
        billNote:          _noteCtrl.text.trim().isEmpty
                               ? null
                               : _noteCtrl.text.trim(),
        billCreatedAt:     widget.bill.billCreatedAt,
        billCreatedBy:     widget.bill.billCreatedBy,
        billCreatedByName: widget.bill.billCreatedByName,
        billStatus:        widget.bill.billStatus,
      );
      await ref
          .read(purchaseBillActionsProvider.notifier)
          .updateBill(widget.cashbookId, updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _T.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDec(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _T.muted, fontSize: 13),
        prefixIcon: icon != null ? Icon(icon, color: _T.muted, size: 18) : null,
        filled: true,
        fillColor: _T.card,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _T.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _T.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _T.accent)),
      );

  @override
  Widget build(BuildContext context) {
    final bottom  = MediaQuery.of(context).viewInsets.bottom;
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      decoration: const BoxDecoration(
        color: _T.card2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: _T.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Edit Bill',
                  style: TextStyle(
                      color: _T.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${widget.bill.clientName}',
                  style: const TextStyle(color: _T.muted, fontSize: 13)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _billNoCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Bill No *',
                    icon: Icons.confirmation_number_outlined),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amountCtrl,
                style: const TextStyle(color: _T.text),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    _fieldDec('Bill Amount (INR) *', icon: Icons.currency_rupee_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteCtrl,
                style: const TextStyle(color: _T.text),
                maxLines: 2,
                decoration: _fieldDec('Description', icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                      color: _T.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _T.border)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: _T.muted),
                      const SizedBox(width: 10),
                      Text(dateFmt.format(_date),
                          style: const TextStyle(
                              color: _T.text, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
