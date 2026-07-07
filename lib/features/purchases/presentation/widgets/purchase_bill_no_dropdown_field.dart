
// lib/features/purchases/presentation/widgets/purchase_bill_no_dropdown_field.dart
//
// Mirrors bill_no_dropdown_field.dart (Sales) for the purchase/expense side.
// Starts EXPANDED — directly shows pending bills, matching the sales-bill UX.
// Only streams / updates when type == 'expense' (enforced by the caller in
// add_transaction_screen.dart — no sales data is touched here).

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/purchase_bill_entity.dart';

class PurchaseBillNoDropdownField extends ConsumerStatefulWidget {
  final String               clientName;
  final PurchaseBillEntity?  selectedBill;
  final ValueChanged<PurchaseBillEntity?> onBillSelected;
  final bool                 isObSelected;
  final VoidCallback?        onObSelected;

  const PurchaseBillNoDropdownField({
    super.key,
    required this.clientName,
    required this.onBillSelected,
    this.selectedBill,
    this.isObSelected = false,
    this.onObSelected,
  });

  @override
  ConsumerState<PurchaseBillNoDropdownField> createState() =>
      _PurchaseBillNoDropdownFieldState();
}

class _PurchaseBillNoDropdownFieldState
    extends ConsumerState<PurchaseBillNoDropdownField> {

  // ── colours (amber = purchase feature) ────────────────────────────────────
  static const _bg       = Color(0xFF181B22);
  static const _border   = Color(0xFF252830);
  static const _secondary= Color(0xFF7A8494);
  static const _accent   = Color(0xFFF59E0B); // amber
  static const _orange   = Color(0xFFD4580A);

  // ── streams ───────────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _billSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _clientSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  Timer? _debounce;

  List<PurchaseBillEntity> _bills = [];
  String  _activeQuery   = '';
  double  _ob            = 0.0;
  double  _obPaid        = 0.0;
  Map<String, double> _paidPerBill = {};

  /// Starts EXPANDED — directly shows the bill list, matching the sales-bill UX.
  /// Collapses to the selected-chip view once the user picks a bill.
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    // If a bill or OB is already selected (edit/re-open flow), start in the
    // collapsed-selected chip state so the pre-selection is visible immediately.
    if (widget.selectedBill != null || widget.isObSelected) {
      _isExpanded = false;
    }
    _scheduleDebounce(widget.clientName);
  }

  @override
  void didUpdateWidget(PurchaseBillNoDropdownField old) {
    super.didUpdateWidget(old);
    if (old.clientName != widget.clientName) {
      _scheduleDebounce(widget.clientName);
      // New party → re-expand so bills load immediately for the new client
      if (mounted) setState(() => _isExpanded = true);
    }
    // If selection was cleared externally, re-expand to show the bill list
    final wasSelected = old.selectedBill != null || old.isObSelected;
    final nowSelected = widget.selectedBill != null || widget.isObSelected;
    if (wasSelected && !nowSelected) {
      if (mounted) setState(() => _isExpanded = true);
    }
  }

  void _scheduleDebounce(String raw) {
    _debounce?.cancel();
    final trimmed = raw.trim();
    if (trimmed.length < 2) {
      _cancelStreams();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (trimmed == _activeQuery) return;
      _activeQuery = trimmed;
      _startStreams(trimmed);
    });
  }

  void _startStreams(String query) {
    _cancelStreams();
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || cashbookId.isEmpty) return;

    final db        = FirebaseFirestore.instance;
    final cashRef   = db.collection('cashbooks').doc(cashbookId);
    final clientLow = query.trim().toLowerCase();

    // 1. Stream pending purchase bills for this client
    _billSub = cashRef
        .collection('purchase_bills')
        .where('clientName', isEqualTo: query.trim())
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final bills = snap.docs.map((d) {
        final raw = d.data();
        return PurchaseBillEntity(
          purchaseBillId: raw['purchaseBillId'] as String? ?? d.id,
          clientName:     raw['clientName']     as String? ?? '',
          billNumber:     raw['billNumber']      as String? ?? '',
          billAmount:     (raw['billAmount']     as num?)?.toDouble() ?? 0.0,
          billDate:       (raw['billDate']       as Timestamp?)?.toDate() ?? DateTime.now(),
          billNote:       raw['billNote']        as String?,
          billCreatedAt:  (raw['billCreatedAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
          billCreatedBy:  raw['billCreatedBy']   as String? ?? '',
          billCreatedByName: raw['billCreatedByName'] as String? ?? '',
          billStatus:     raw['billStatus']      as String? ?? 'pending',
        );
      }).toList()
        ..sort((a, b) => a.billCreatedAt.compareTo(b.billCreatedAt));
      setState(() => _bills = bills);
    });

    // 2. Stream purchase client doc to get opening balance
    _clientSub = cashRef
        .collection('purchase_clients')
        .doc(clientLow)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final ob = (doc.data()?['openingBalance'] as num?)?.toDouble() ?? 0.0;
      if (ob != _ob) setState(() => _ob = ob);
    });

    // 3. Stream expense transactions to compute paid amounts
    _txSub = cashRef
        .collection('transactions')
        .where('type', isEqualTo: 'expense')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      double obPaid = 0.0;
      final perBill = <String, double>{};
      for (final d in snap.docs) {
        final raw      = d.data();
        final linkedId = raw['linkedPurchaseBillId'] as String?;
        final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final isObForThis = raw['isObPayment'] == true &&
            (raw['obPartyName'] as String? ?? '').trim().toLowerCase() == clientLow;
        if (linkedId != null && linkedId.isNotEmpty) {
          perBill[linkedId] = (perBill[linkedId] ?? 0.0) + amount;
        } else if (isObForThis) {
          obPaid += amount;
        }
      }
      if (mounted) {
        setState(() {
          _obPaid       = obPaid;
          _paidPerBill  = perBill;
        });
      }
    });
  }

  void _cancelStreams() {
    _billSub?.cancel();   _billSub   = null;
    _clientSub?.cancel(); _clientSub = null;
    _txSub?.cancel();     _txSub     = null;
    _activeQuery = '';
    final needsRebuild = _bills.isNotEmpty || _ob != 0.0;
    if (needsRebuild && mounted) {
      setState(() {
        _bills       = [];
        _ob          = 0.0;
        _obPaid      = 0.0;
        _paidPerBill = {};
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _billSub?.cancel();
    _clientSub?.cancel();
    _txSub?.cancel();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final billFmt   = NumberFormat('#,##,##0', 'en_IN');
    final obFmt     = NumberFormat('#,##,##0', 'en_IN');

    final obRemaining   = (_ob - _obPaid).clamp(0.0, double.infinity);
    final hasOb         = obRemaining > 0;
    final pendingBills  = _bills.where((b) {
      final paid = _paidPerBill[b.purchaseBillId] ?? 0.0;
      return b.billAmount - paid > 0;
    }).toList();
    final hasBills       = pendingBills.isNotEmpty;
    final somethingSelected = widget.selectedBill != null || widget.isObSelected;

    // ── Nothing pending at all — hide widget entirely ─────────────────────
    if (!hasBills && !hasOb && !somethingSelected) return const SizedBox.shrink();

    // ── Collapsed + something selected: show selected chip ────────────────
    if (!_isExpanded && somethingSelected) {
      return GestureDetector(
        onTap: () => setState(() => _isExpanded = true),
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(
                widget.isObSelected
                    ? Icons.account_balance_wallet_rounded
                    : Icons.receipt_long_rounded,
                color: widget.isObSelected ? _orange : _accent,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: widget.isObSelected
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Opening Balance',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text('₹${obFmt.format(obRemaining)} remaining',
                              style: const TextStyle(
                                  color: Color(0xFFE05C5C),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.selectedBill!.billNumber,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text(widget.selectedBill!.clientName,
                              style: const TextStyle(
                                  color: _secondary, fontSize: 11)),
                        ],
                      ),
              ),
              if (widget.selectedBill != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${billFmt.format(widget.selectedBill!.billAmount)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      '₹${billFmt.format(widget.selectedBill!.billAmount - (_paidPerBill[widget.selectedBill!.purchaseBillId] ?? 0.0))} pending',
                      style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontWeight: FontWeight.w600,
                          fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                const Icon(Icons.check_circle_rounded, color: _accent, size: 16),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _secondary, size: 18),
            ],
          ),
        ),
      );
    }

    // ── Collapsed + nothing selected: "Select Bill" tap-target ───────────
    if (!_isExpanded && !somethingSelected) {
      return GestureDetector(
        onTap: () => setState(() => _isExpanded = true),
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: _accent, size: 15),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Select Bill',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
              Text(
                '${[
                  if (hasBills) '${pendingBills.length} bill${pendingBills.length == 1 ? '' : 's'}',
                  if (hasOb) 'OB',
                ].join(' · ')} pending',
                style: TextStyle(
                    color: _secondary.withValues(alpha: 0.8), fontSize: 11),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _secondary, size: 18),
            ],
          ),
        ),
      );
    }

    // ── Expanded: show full list ──────────────────────────────────────────
    final anythingSelected = somethingSelected;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: _accent, size: 16),
                const SizedBox(width: 6),
                const Text('Link Bill No.',
                    style: TextStyle(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const Spacer(),
                if (anythingSelected)
                  GestureDetector(
                    onTap: () {
                      widget.onBillSelected(null);
                      setState(() => _isExpanded = false);
                    },
                    child: const Text('Clear',
                        style: TextStyle(color: _secondary, fontSize: 11)),
                  )
                else
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = false),
                    child: const Text('Close',
                        style: TextStyle(color: _secondary, fontSize: 11)),
                  ),
              ],
            ),
          ),
          const Divider(color: _border, height: 1),

          // Opening Balance row
          if (hasOb) ...[
            GestureDetector(
              onTap: () {
                widget.onObSelected?.call();
                setState(() => _isExpanded = false);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isObSelected
                      ? _orange.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.isObSelected ? _orange : _border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded,
                        size: 14,
                        color: widget.isObSelected ? _orange : _secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Opening Balance',
                          style: TextStyle(
                              color: widget.isObSelected
                                  ? _orange
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                    Text('₹${obFmt.format(obRemaining)} remaining',
                        style: const TextStyle(
                            color: Color(0xFFE05C5C),
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    if (widget.isObSelected) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle_rounded,
                          color: _orange, size: 16),
                    ],
                  ],
                ),
              ),
            ),
            if (hasBills)
              const Divider(color: _border, height: 1, indent: 8, endIndent: 8),
          ],

          // Pending bills list
          if (hasBills)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: pendingBills.length,
                itemBuilder: (_, i) {
                  final bill       = pendingBills[i];
                  final isSelected =
                      widget.selectedBill?.purchaseBillId == bill.purchaseBillId;
                  final paid       = _paidPerBill[bill.purchaseBillId] ?? 0.0;
                  final pendingAmt = (bill.billAmount - paid)
                      .clamp(0.0, double.infinity);

                  return GestureDetector(
                    onTap: () {
                      widget.onBillSelected(isSelected ? null : bill);
                      if (!isSelected) setState(() => _isExpanded = false);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _accent.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? _accent : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(bill.billNumber,
                                    style: TextStyle(
                                        color: isSelected
                                            ? _accent
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                Text(bill.clientName,
                                    style: const TextStyle(
                                        color: _secondary, fontSize: 11)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('₹${billFmt.format(bill.billAmount)}',
                                  style: TextStyle(
                                      color: isSelected
                                          ? _accent
                                          : Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                              const SizedBox(height: 2),
                              Text('₹${billFmt.format(pendingAmt)} pending',
                                  style: const TextStyle(
                                      color: Color(0xFFFBBF24),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11)),
                            ],
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle_rounded,
                                color: _accent, size: 16),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
