// lib/features/purchases/presentation/screens/purchase_client_detail_screen.dart
//
// Simplified mirror of lib/features/sales/presentation/screens/party_detail_screen.dart
// Shows: client header, opening balance, and every bill recorded for the
// client (with status + amount). Lets the user add a new bill, edit the
// opening balance, or delete a bill.

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
  // Live-computed payment totals — mirrors party_detail_screen.dart in the
  // Sales feature. Pending/closing balance is NEVER read from a stored
  // "billStatus" field; it's derived from every expense transaction linked
  // to this client's bills (and opening balance), recomputed on every
  // Firestore update.
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(purchaseClientsProvider);
    final billsAsync = ref.watch(purchaseBillsForClientProvider(widget.clientName));
    final client = clientsAsync.asData?.value.where(
        (c) => c.clientName.toLowerCase() == widget.clientName.toLowerCase());
    final openingBalance =
        (client != null && client.isNotEmpty) ? client.first.openingBalance : 0.0;
    final bills = billsAsync.asData?.value ?? [];

    // Closing balance = opening balance + total billed - total paid so far,
    // computed live from linked expense transactions — mirrors
    // sales_screen.dart's closingBalance calc, never a stored field.
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
                            color: _T.text, fontSize: 18, fontWeight: FontWeight.w700),
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
                        const Text('Total Due', style: TextStyle(color: _T.muted, fontSize: 12)),
                        InkWell(
                          onTap: () => _editOpeningBalance(openingBalance),
                          child: const Row(
                            children: [
                              Text('Edit opening balance',
                                  style: TextStyle(color: _T.accent, fontSize: 12)),
                              SizedBox(width: 4),
                              Icon(Icons.edit_rounded, size: 12, color: _T.accent),
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
                  Text('All Bills', style: TextStyle(color: _T.text, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: bills.isEmpty
                  ? const Center(
                      child: Text('No bills yet', style: TextStyle(color: _T.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: bills.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final bill = bills[i];
                        final paidOnBill = _paidPerBill[bill.purchaseBillId] ?? 0.0;
                        final pendingOnBill =
                            (bill.billAmount - paidOnBill).clamp(0.0, double.infinity);
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
                        return Container(
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Bill #${bill.billNumber}',
                                        style: const TextStyle(
                                            color: _T.text, fontSize: 14, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(dateFmt.format(bill.billDate),
                                        style: const TextStyle(color: _T.muted, fontSize: 12)),
                                    if (bill.billNote != null && bill.billNote!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(bill.billNote!,
                                          style: const TextStyle(color: _T.muted, fontSize: 12),
                                          maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('₹${bill.billAmount.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          color: _T.text, fontSize: 15, fontWeight: FontWeight.w700)),
                                  if (!isSettled) ...[
                                    const SizedBox(height: 2),
                                    Text('₹${pendingOnBill.toStringAsFixed(0)} pending',
                                        style: const TextStyle(
                                            color: _T.amber, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(statusLabel,
                                        style: TextStyle(
                                            color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () => _deleteBill(bill),
                                icon: const Icon(Icons.delete_outline_rounded, color: _T.muted, size: 18),
                              ),
                            ],
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
