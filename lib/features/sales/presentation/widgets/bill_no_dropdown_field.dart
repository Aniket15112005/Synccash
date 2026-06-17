import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../data/repositories/sale_bill_repository_impl.dart';
import '../../domain/entities/sale_bill_entity.dart';

class BillNoDropdownField extends ConsumerStatefulWidget {
  final String partyName;
  final SaleBillEntity? selectedBill;
  final ValueChanged<SaleBillEntity?> onBillSelected;
  final bool isObSelected;
  final VoidCallback? onObSelected;

  const BillNoDropdownField({
    super.key,
    required this.partyName,
    required this.onBillSelected,
    this.selectedBill,
    this.isObSelected = false,
    this.onObSelected,
  });

  @override
  ConsumerState<BillNoDropdownField> createState() =>
      _BillNoDropdownFieldState();
}

class _BillNoDropdownFieldState extends ConsumerState<BillNoDropdownField> {
  static const _bg        = Color(0xFF181B22);
  static const _border    = Color(0xFF252830);
  static const _secondary = Color(0xFF7A8494);
  static const _accent    = Color(0xFF5B8DEF);
  static const _green     = Color(0xFF4DB87E);
  static const _orange    = Color(0xFFD4580A);

  StreamSubscription<List<SaleBillEntity>>? _sub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partySub;
  Timer?  _debounce;
  List<SaleBillEntity> _bills = [];
  String  _activeQuery = '';
  double  _ob = 0.0;
  double _obReceived = 0.0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  Map<String, double> _receivedPerBill = {};

  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    // If a bill is already selected (edit flow), start collapsed so the
    // pre-selected bill chip renders immediately without waiting for the stream.
    if (widget.selectedBill != null || widget.isObSelected) {
      _isExpanded = false;
    }
    _scheduleDebounce(widget.partyName);
  }

  @override
  void didUpdateWidget(BillNoDropdownField old) {
    super.didUpdateWidget(old);
    if (old.partyName != widget.partyName) {
      _scheduleDebounce(widget.partyName);
      if (mounted) setState(() => _isExpanded = true);
    }
    // If selection was cleared from outside, re-expand
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
      _cancelStream();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (trimmed == _activeQuery) return;
      _activeQuery = trimmed;
      _startStream(trimmed);
    });
  }

  void _startStream(String query) {
    _sub?.cancel();
    _partySub?.cancel();

    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || cashbookId.isEmpty) return;

    final repo = SaleBillRepositoryImpl(FirebaseFirestore.instance);
    _sub = repo
        .watchPendingBillsByPartyName(cashbookId, query)
        .listen((bills) {
      if (mounted) setState(() => _bills = bills);
    });

    _partySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .doc(query.trim().toLowerCase())
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
        .where('type', isEqualTo: 'income')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      double obPaid = 0.0;
      final perBill = <String, double>{};
      final q = query.trim().toLowerCase();
      for (final d in snap.docs) {
        final raw      = d.data();
        final linkedId = raw['linkedSaleBillId'] as String?;
        final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final desc     = (raw['description'] as String? ?? '').toLowerCase();
        if (linkedId != null && linkedId.isNotEmpty) {
          perBill[linkedId] = (perBill[linkedId] ?? 0.0) + amount;
        } else if (desc.contains(q)) {
          obPaid += amount;
        }
      }
      if (mounted) setState(() {
        _obReceived      = obPaid;
        _receivedPerBill = perBill;
      });
    });
  }

  void _cancelStream() {
    _sub?.cancel();
    _sub = null;
    _partySub?.cancel();
    _partySub = null;
    _txSub?.cancel();
    _txSub = null;
    _activeQuery = '';
    final needsRebuild = _bills.isNotEmpty || _ob != 0.0;
    if (needsRebuild) setState(() {
      _bills           = [];
      _ob              = 0.0;
      _obReceived      = 0.0;
      _receivedPerBill = {};
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _partySub?.cancel();
    _txSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final obRemaining = (_ob - _obReceived).clamp(0.0, double.infinity);
    final hasOb = obRemaining > 0;
    final pendingBills = _bills.where((b) {
      final received = _receivedPerBill[b.saleBillId] ?? 0.0;
      return b.billTotal - received > 0;
    }).toList();
    final hasBills = pendingBills.isNotEmpty;

    final billFmt = NumberFormat('#,##,##0', 'en_IN');
    final obFmt   = NumberFormat('#,##,##0', 'en_IN');

    final somethingSelected = widget.selectedBill != null || widget.isObSelected;

    // ── Collapsed: show selected summary (pre-selected bill shows instantly) ──
    // NOTE: this check is BEFORE the empty-state guard so a pre-selected bill
    // (passed in from the edit flow) always renders its chip even while the
    // pending-bills stream is still loading.
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
                          const Text(
                            'Opening Balance',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '₹${obFmt.format(obRemaining)} remaining',
                            style: const TextStyle(
                              color: Color(0xFFE05C5C),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.selectedBill!.billNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            widget.selectedBill!.partyName,
                            style: const TextStyle(
                                color: _secondary, fontSize: 11),
                          ),
                        ],
                      ),
              ),
              if (widget.selectedBill != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${billFmt.format(widget.selectedBill!.billTotal)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${billFmt.format(widget.selectedBill!.billTotal - (_receivedPerBill[widget.selectedBill!.saleBillId] ?? 0.0))} pending',
                      style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                const Icon(Icons.check_circle_rounded,
                    color: _accent, size: 16),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _secondary, size: 18),
            ],
          ),
        ),
      );
    }

    // Nothing to show — no pending bills, no OB, nothing selected
    if (!hasBills && !hasOb) return const SizedBox.shrink();

    // ── Expanded: full dropdown ────────────────────────────────────────────
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
          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded,
                    color: _accent, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Link Bill No.',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (anythingSelected)
                  GestureDetector(
                    onTap: () {
                      widget.onBillSelected(null);
                      setState(() => _isExpanded = true);
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: _secondary, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: _border, height: 1),

          // ── Opening Balance button ────────────────────────────────────
          if (hasOb) ...[
            GestureDetector(
              onTap: () {
                widget.onObSelected?.call();
                setState(() => _isExpanded = false);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isObSelected
                      ? _orange.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.isObSelected ? _orange : _border,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 14,
                      color: widget.isObSelected ? _orange : _secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Opening Balance',
                        style: TextStyle(
                          color: widget.isObSelected
                              ? _orange
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '₹${obFmt.format(obRemaining)} remaining',
                      style: const TextStyle(
                        color: Color(0xFFE05C5C),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
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
              const Divider(
                  color: _border, height: 1, indent: 8, endIndent: 8),
          ],

          // ── Bill list ─────────────────────────────────────────────────
          if (hasBills)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: pendingBills.length,
                itemBuilder: (context, i) {
                  final bill       = pendingBills[i];
                  final isSelected =
                      widget.selectedBill?.saleBillId == bill.saleBillId;
                  final pendingAmt =
                      bill.billTotal - (_receivedPerBill[bill.saleBillId] ?? 0.0);

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
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bill.billNumber,
                                  style: TextStyle(
                                    color: isSelected
                                        ? _accent
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  bill.partyName,
                                  style: const TextStyle(
                                      color: _secondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${billFmt.format(bill.billTotal)}',
                                style: TextStyle(
                                  color: isSelected ? _accent : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹${billFmt.format(pendingAmt)} pending',
                                style: const TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
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
