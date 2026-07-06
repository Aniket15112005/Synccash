// lib/features/purchases/presentation/screens/purchases_screen.dart
//
// Mirrors lib/features/sales/presentation/screens/sales_screen.dart
// Entry point reached from Settings → Purchase. Shows a searchable list of
// purchase clients; tapping a client opens PurchaseClientDetailScreen. The
// "+" FAB opens _AddPurchaseClientBillSheet to create a new client + its
// first bill in one step (client name, bill no, bill amount, description).

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../providers/purchase_client_provider.dart';
import '../providers/purchase_bill_provider.dart';
import 'purchase_client_detail_screen.dart';
import '../purchase_routes.dart';

class _T {
  static const bg      = Color(0xFF0F1011);
  static const card    = Color(0xFF1A1B1E);
  static const card2   = Color(0xFF1E1F22);
  static const border  = Color(0xFF2C2D32);
  static const muted   = Color(0xFF8C8E9A);
  static const text    = Color(0xFFF1F2F5);
  static const accent  = Color(0xFFF59E0B); // amber — purchase feature accent
  static const red     = Color(0xFFFC8181);
}

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  // Live-computed payment totals — mirrors sales_screen.dart. A client's
  // pending amount is NEVER read from a stored "billStatus" field; it's the
  // bill total minus every expense transaction linked to it, recomputed on
  // every Firestore update so partial payments show up instantly.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  Map<String, double> _paidPerBill = {};
  Map<String, double> _obPaidByClient = {};

  @override
  void initState() {
    super.initState();
    _startTxStream();
  }

  void _startTxStream() {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'expense')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final perBill = <String, double>{};
      final obByClient = <String, double>{};
      for (final d in snap.docs) {
        final raw = d.data();
        final linkedId = raw['linkedPurchaseBillId'] as String?;
        final amount = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        if (linkedId != null && linkedId.isNotEmpty) {
          perBill[linkedId] = (perBill[linkedId] ?? 0.0) + amount;
        } else if (raw['isObPayment'] == true) {
          final obClient =
              (raw['obPartyName'] as String? ?? '').trim().toLowerCase();
          if (obClient.isNotEmpty) {
            obByClient[obClient] = (obByClient[obClient] ?? 0.0) + amount;
          }
        }
      }
      setState(() {
        _paidPerBill = perBill;
        _obPaidByClient = obByClient;
      });
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    super.dispose();
  }

  void _openAddSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddPurchaseClientBillSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(filteredPurchaseClientsProvider);
    final allBillsAsync = ref.watch(allPurchaseBillsProvider);
    final allBills = allBillsAsync.asData?.value ?? [];

    // Pending total owed per client — bill total minus what's actually been
    // paid against it so far, computed live (never from stored billStatus).
    final pendingByClient = <String, double>{};
    for (final b in allBills) {
      final paid = _paidPerBill[b.purchaseBillId] ?? 0.0;
      final pending = (b.billAmount - paid).clamp(0.0, double.infinity);
      if (pending <= 0) continue;
      pendingByClient[b.clientName] =
          (pendingByClient[b.clientName] ?? 0) + pending;
    }

    return Scaffold(
      backgroundColor: _T.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: _T.text),
                  ),
                  const Expanded(
                    child: Text('Purchases',
                        style: TextStyle(
                            color: _T.text, fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: _openAddSheet,
                    icon: const Icon(Icons.add_circle_rounded, color: _T.accent, size: 28),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SearchBar(
                onChanged: (v) =>
                    ref.read(purchaseClientSearchProvider.notifier).update(v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: clients.isEmpty
                  ? _EmptyState(onAdd: _openAddSheet)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: clients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final client = clients[i];
                        final pending = pendingByClient[client.clientName] ?? 0;
                        final obPaid = _obPaidByClient[
                                client.clientName.trim().toLowerCase()] ??
                            0.0;
                        final obRemaining =
                            (client.openingBalance - obPaid).clamp(0.0, double.infinity);
                        return _ClientCard(
                          clientName: client.clientName,
                          openingBalance: obRemaining,
                          pendingBills: pending,
                          onTap: () => Navigator.push(
                            context,
                            purchaseRoute(PurchaseClientDetailScreen(
                              clientName: client.clientName,
                            )),
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

// ─── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 48, color: _T.border),
          const SizedBox(height: 16),
          const Text('No purchase clients yet',
              style: TextStyle(color: _T.muted, fontSize: 14)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, color: _T.accent),
            label: const Text('Add purchase client', style: TextStyle(color: _T.accent)),
          ),
        ],
      ),
    );
  }
}

// ─── Search bar ─────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: _T.text, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search purchase clients…',
        hintStyle: const TextStyle(color: _T.muted, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: _T.muted, size: 20),
        filled: true,
        fillColor: _T.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _T.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _T.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _T.accent),
        ),
      ),
    );
  }
}

// ─── Client card ────────────────────────────────────────────────────────────

class _ClientCard extends StatelessWidget {
  final String clientName;
  final double openingBalance;
  final double pendingBills;
  final VoidCallback onTap;

  const _ClientCard({
    required this.clientName,
    required this.openingBalance,
    required this.pendingBills,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalDue = openingBalance + pendingBills;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _T.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_shipping_outlined, color: _T.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clientName,
                      style: const TextStyle(
                          color: _T.text, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    totalDue > 0
                        ? 'Due ₹${totalDue.toStringAsFixed(0)}'
                        : totalDue < 0
                            ? 'Advance ₹${totalDue.abs().toStringAsFixed(0)}'
                            : 'Settled',
                    style: TextStyle(
                      color: totalDue > 0 ? _T.red : _T.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _T.muted),
          ],
        ),
      ),
    );
  }
}

// ─── Add client + bill sheet ────────────────────────────────────────────────

class _AddPurchaseClientBillSheet extends ConsumerStatefulWidget {
  const _AddPurchaseClientBillSheet();

  @override
  ConsumerState<_AddPurchaseClientBillSheet> createState() =>
      _AddPurchaseClientBillSheetState();
}

class _AddPurchaseClientBillSheetState
    extends ConsumerState<_AddPurchaseClientBillSheet> {
  final _formKey    = GlobalKey<FormState>();
  final _clientCtrl = TextEditingController();
  final _billNoCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  DateTime _date    = DateTime.now();
  bool _submitting  = false;

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(purchaseBillActionsProvider.notifier).addBill(
            cashbookId: cashbookId,
            clientName: _clientCtrl.text.trim(),
            billNumber: _billNoCtrl.text.trim(),
            billAmount: double.parse(_amountCtrl.text.trim()),
            billDate: _date,
            billNote: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            createdBy: user.uid,
            createdByName: user.displayName ?? '',
          );
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

  InputDecoration _fieldDec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _T.muted, fontSize: 13),
      hintStyle: const TextStyle(color: _T.muted, fontSize: 13),
      prefixIcon: icon != null ? Icon(icon, color: _T.muted, size: 18) : null,
      filled: true,
      fillColor: _T.card2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _T.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _T.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _T.accent),
      ),
    );
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _billNoCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

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
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _T.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _T.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _T.accent.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.local_shipping_outlined, color: _T.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Purchase Bill',
                          style: TextStyle(color: _T.text, fontSize: 18, fontWeight: FontWeight.w700)),
                      Text('Fill in the purchase details below',
                          style: TextStyle(color: _T.muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _clientCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Purchase Client Name *',
                    hint: 'e.g. XYZ Wholesalers', icon: Icons.business_rounded),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _billNoCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Bill No *', hint: 'e.g. INV-2026-001', icon: Icons.confirmation_number_outlined),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amountCtrl,
                style: const TextStyle(color: _T.text),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _fieldDec('Bill Amount (INR) *', hint: 'e.g. 15000', icon: Icons.currency_rupee_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: _T.text),
                maxLines: 2,
                decoration: _fieldDec('Description', hint: 'Type of goods purchased', icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _T.card2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _T.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 16, color: _T.muted),
                      const SizedBox(width: 10),
                      Text(dateFmt.format(_date), style: const TextStyle(color: _T.text, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Save Purchase Bill', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
