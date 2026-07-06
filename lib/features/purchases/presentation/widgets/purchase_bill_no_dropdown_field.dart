// lib/features/purchases/presentation/widgets/purchase_bill_no_dropdown_field.dart
//
// Mirrors lib/features/sales/presentation/widgets/bill_no_dropdown_field.dart
// Shown on the Add Transaction screen when Expense + Wholesale/Bank/UPI is
// selected and a purchase client name has been confirmed. Lets the user pick
// either "Opening Balance" or one of the client's pending bill numbers to
// allocate the payment against.
//
// Pending amounts are computed LIVE from Firestore — never from a stored
// "billStatus" field. A ₹50,000 bill with a ₹40,000 expense recorded against
// it will always show ₹10,000 pending here, exactly like the Sales dropdown.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../data/repositories/purchase_bill_repository_impl.dart';
import '../../domain/entities/purchase_bill_entity.dart';

class _C {
  static const bg = Color(0xFF08090B);
  static const surface2 = Color(0xFF18191E);
  static const border = Color(0xFF202228);
  static const border2 = Color(0xFF2A2C33);
  static const textPri = Color(0xFFF0F1F3);
  static const textSec = Color(0xFF6B7280);
  static const textMut = Color(0xFF3D4149);
  static const accent = Color(0xFFF59E0B); // amber — matches the Purchase settings tile
  static const red = Color(0xFFE05C5C);
  static const amber = Color(0xFFFBBF24);
}

class PurchaseBillNoDropdownField extends ConsumerStatefulWidget {
  final String clientName;
  final PurchaseBillEntity? selectedBill;
  final ValueChanged<PurchaseBillEntity?> onBillSelected;
  final bool isObSelected;
  final VoidCallback onObSelected;

  const PurchaseBillNoDropdownField({
    super.key,
    required this.clientName,
    required this.selectedBill,
    required this.onBillSelected,
    required this.isObSelected,
    required this.onObSelected,
  });

  @override
  ConsumerState<PurchaseBillNoDropdownField> createState() =>
      _PurchaseBillNoDropdownFieldState();
}

class _PurchaseBillNoDropdownFieldState
    extends ConsumerState<PurchaseBillNoDropdownField> {
  bool _open = false;

  StreamSubscription<List<PurchaseBillEntity>>? _billsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _clientSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;

  List<PurchaseBillEntity> _bills = [];
  double _ob = 0.0;
  double _obPaid = 0.0;
  Map<String, double> _paidPerBill = {};
  String _activeClient = '';

  @override
  void initState() {
    super.initState();
    _startStreams(widget.clientName);
  }

  @override
  void didUpdateWidget(PurchaseBillNoDropdownField old) {
    super.didUpdateWidget(old);
    if (old.clientName.trim().toLowerCase() !=
        widget.clientName.trim().toLowerCase()) {
      _startStreams(widget.clientName);
    }
  }

  void _startStreams(String rawClientName) {
    final clientName = rawClientName.trim();
    if (clientName.isEmpty || clientName.toLowerCase() == _activeClient) {
      return;
    }
    _activeClient = clientName.toLowerCase();

    _billsSub?.cancel();
    _clientSub?.cancel();
    _txSub?.cancel();

    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || cashbookId.isEmpty) return;

    final repo = PurchaseBillRepositoryImpl(firestore: FirebaseFirestore.instance);
    _billsSub =
        repo.watchPendingBillsByClientName(cashbookId, clientName).listen((bills) {
      if (mounted) setState(() => _bills = bills);
    });

    _clientSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('purchase_clients')
        .doc(clientName.toLowerCase())
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final ob = (doc.data()?['openingBalance'] as num?)?.toDouble() ?? 0.0;
      if (ob != _ob) setState(() => _ob = ob);
    });

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
      final q = clientName.toLowerCase();
      for (final d in snap.docs) {
        final raw = d.data();
        final linkedId = raw['linkedPurchaseBillId'] as String?;
        final amount = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final desc = (raw['description'] as String? ?? '').toLowerCase();
        final isObForThisClient = raw['isObPayment'] == true &&
            (raw['obPartyName'] as String? ?? '').trim().toLowerCase() == q;
        if (linkedId != null && linkedId.isNotEmpty) {
          perBill[linkedId] = (perBill[linkedId] ?? 0.0) + amount;
        } else if (isObForThisClient || desc.contains(q)) {
          obPaid += amount;
        }
      }
      if (mounted) {
        setState(() {
          _obPaid = obPaid;
          _paidPerBill = perBill;
        });
      }
    });
  }

  @override
  void dispose() {
    _billsSub?.cancel();
    _clientSub?.cancel();
    _txSub?.cancel();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final clientName = widget.clientName.trim();
    if (clientName.isEmpty) return const SizedBox.shrink();

    final obRemaining = (_ob - _obPaid).clamp(0.0, double.infinity);
    final pendingBills = _bills.where((b) {
      final paid = _paidPerBill[b.purchaseBillId] ?? 0.0;
      return b.billAmount - paid > 0;
    }).toList();

    final label = widget.isObSelected
        ? 'Opening Balance'
        : widget.selectedBill != null
            ? 'Bill #${widget.selectedBill!.billNumber}'
            : 'Select bill or opening balance';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _C.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (widget.selectedBill != null || widget.isObSelected)
                      ? _C.accent.withValues(alpha: 0.5)
                      : _C.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded, size: 16, color: _C.textSec),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: (widget.selectedBill != null || widget.isObSelected)
                            ? _C.textPri
                            : _C.textMut,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.selectedBill != null) ...[
                    Text(
                      '₹${(widget.selectedBill!.billAmount - (_paidPerBill[widget.selectedBill!.purchaseBillId] ?? 0.0)).toStringAsFixed(0)} pending',
                      style: const TextStyle(
                        color: _C.amber,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (widget.isObSelected) ...[
                    Text(
                      '₹${obRemaining.toStringAsFixed(0)} remaining',
                      style: const TextStyle(
                        color: _C.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    _open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: _C.textSec,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: _C.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _C.border2),
              ),
              constraints: const BoxConstraints(maxHeight: 260),
              child: _buildList(pendingBills, obRemaining),
            ),
        ],
      ),
    );
  }

  Widget _buildList(List<PurchaseBillEntity> bills, double obRemaining) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final amtFmt = NumberFormat('#,##,##0', 'en_IN');

    if (bills.isEmpty && obRemaining <= 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No pending bills for this client',
            style: TextStyle(color: _C.textSec, fontSize: 13)),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        if (obRemaining > 0)
          _OptionTile(
            title: 'Opening Balance',
            subtitle: '₹${amtFmt.format(obRemaining)} remaining',
            selected: widget.isObSelected,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onObSelected();
              setState(() => _open = false);
            },
          ),
        for (final bill in bills)
          _OptionTile(
            title: 'Bill #${bill.billNumber}',
            subtitle:
                '₹${amtFmt.format(bill.billAmount - (_paidPerBill[bill.purchaseBillId] ?? 0.0))} pending of ₹${amtFmt.format(bill.billAmount)} • ${dateFmt.format(bill.billDate)}',
            selected: widget.selectedBill?.purchaseBillId == bill.purchaseBillId,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onBillSelected(bill);
              setState(() => _open = false);
            },
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: selected ? _C.accent.withValues(alpha: 0.08) : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: selected ? _C.accent : _C.textPri,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: _C.amber, fontSize: 12)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: _C.accent),
          ],
        ),
      ),
    );
  }
}
