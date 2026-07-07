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

  Future<void> _editClient(String clientName) async {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController(text: clientName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Client',
            style: TextStyle(color: Color(0xFFF1F2F5), fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: Color(0xFFF1F2F5)),
          decoration: InputDecoration(
            hintText: 'Client name',
            hintStyle: const TextStyle(color: Color(0xFF8C8E9A)),
            filled: true,
            fillColor: const Color(0xFF1A1B1E),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2C2D32))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFF59E0B))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF8C8E9A))),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Save',
                style: TextStyle(
                    color: Color(0xFFF59E0B), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (newName == null || newName == clientName) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    try {
      await ref
          .read(purchaseClientActionsProvider.notifier)
          .renameClient(cashbookId, clientName, newName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _T.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _deleteClient(String clientName) async {
    HapticFeedback.mediumImpact();
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Client?',
            style: TextStyle(color: Color(0xFFF1F2F5), fontWeight: FontWeight.w700)),
        content: Text(
          'This will delete "$clientName" from your purchase clients. '
          'Their bills will remain but the client record will be removed.',
          style: const TextStyle(color: Color(0xFF8C8E9A), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF8C8E9A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFFC8181), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(purchaseClientActionsProvider.notifier)
          .deleteClient(cashbookId, clientName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _T.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients    = ref.watch(filteredPurchaseClientsProvider);
    // Use ALL clients (not search-filtered) so summary totals are always global.
    final allClients = ref.watch(purchaseClientsProvider).asData?.value ?? [];
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

    // ── Summary strip computation ───────────────────────────────────────────
    // Per-client bill totals (raw, unpaid).
    final billTotalByKey = <String, double>{};
    for (final b in allBills) {
      final key = b.clientName.trim().toLowerCase();
      billTotalByKey[key] = (billTotalByKey[key] ?? 0) + b.billAmount;
    }
    // Per-client pending bill amount (live: sum of (billAmt - paid).clamp(0)).
    final billPendingByKey = <String, double>{};
    for (final b in allBills) {
      final key  = b.clientName.trim().toLowerCase();
      final paid = _paidPerBill[b.purchaseBillId] ?? 0.0;
      billPendingByKey[key] =
          (billPendingByKey[key] ?? 0) + (b.billAmount - paid).clamp(0.0, double.infinity);
    }
    // Aggregate across every client.
    double _totalBillAmt = 0;
    double _totalClosing = 0;
    for (final client in allClients) {
      final key         = client.clientName.trim().toLowerCase();
      final ob          = client.openingBalance;
      final obPaid      = _obPaidByClient[key] ?? 0.0;
      final obRemaining = (ob - obPaid).clamp(0.0, double.infinity);
      _totalBillAmt += ob + (billTotalByKey[key]   ?? 0);
      _totalClosing += obRemaining + (billPendingByKey[key] ?? 0);
    }
    final _totalPaid =
        (_totalBillAmt - _totalClosing).clamp(0.0, double.infinity);

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
            // ── Summary strip ─────────────────────────────────────────────
            if (allClients.isNotEmpty || allBills.isNotEmpty)
              _PurchaseSummaryStrip(
                totalBillAmt: _totalBillAmt,
                totalPaid:    _totalPaid,
                totalClosing: _totalClosing,
              ),
            const SizedBox(height: 8),
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
                          onEdit:   () => _editClient(client.clientName),
                          onDelete: () => _deleteClient(client.clientName),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientCard({
    required this.clientName,
    required this.openingBalance,
    required this.pendingBills,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final totalDue = openingBalance + pendingBills;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
              child: const Icon(Icons.storefront_outlined, color: _T.accent, size: 20),
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
            // Three-dot menu for edit / delete
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert_rounded, color: _T.muted, size: 20),
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
                      Text('Edit Client',
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
                      Text('Delete Client',
                          style: TextStyle(
                              color: _T.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
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
                    child: const Icon(Icons.storefront_outlined, color: _T.accent, size: 20),
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

// ─── Purchase summary strip ──────────────────────────────────────────────────

class _PurchaseSummaryStrip extends StatelessWidget {
  final double totalBillAmt;
  final double totalPaid;
  final double totalClosing;

  const _PurchaseSummaryStrip({
    required this.totalBillAmt,
    required this.totalPaid,
    required this.totalClosing,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##,##0.##', 'en_IN');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.border),
      ),
      child: Row(
        children: [
          _PurchaseSummaryCell(
            label: 'Bill Amt',
            value: '₹${fmt.format(totalBillAmt)}',
            color: _T.text,
          ),
          _PurchaseSummaryDivider(),
          _PurchaseSummaryCell(
            label: 'Paid',
            value: '₹${fmt.format(totalPaid)}',
            color: const Color(0xFF38D68A),
          ),
          _PurchaseSummaryDivider(),
          _PurchaseSummaryCell(
            label: 'Closing Bal.',
            value: '₹${fmt.format(totalClosing)}',
            color: const Color(0xFFD4580A),
          ),
        ],
      ),
    );
  }
}

class _PurchaseSummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _PurchaseSummaryCell({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _T.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _PurchaseSummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: _T.border,
  );
}
