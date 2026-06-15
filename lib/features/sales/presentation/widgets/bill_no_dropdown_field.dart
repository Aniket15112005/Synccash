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

  const BillNoDropdownField({
    super.key,
    required this.partyName,
    required this.onBillSelected,
    this.selectedBill,
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

  StreamSubscription<List<SaleBillEntity>>? _sub;
  Timer?  _debounce;
  List<SaleBillEntity> _bills = [];
  String  _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _scheduleDebounce(widget.partyName);
  }

  @override
  void didUpdateWidget(BillNoDropdownField old) {
    super.didUpdateWidget(old);
    if (old.partyName != widget.partyName) {
      _scheduleDebounce(widget.partyName);
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
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || cashbookId.isEmpty) return;

    final repo = SaleBillRepositoryImpl(FirebaseFirestore.instance);
    _sub = repo
        .watchPendingBillsByPartyName(cashbookId, query)
        .listen((bills) {
      if (mounted) setState(() => _bills = bills);
    });
  }

  void _cancelStream() {
    _sub?.cancel();
    _sub = null;
    _activeQuery = '';
    if (_bills.isNotEmpty) setState(() => _bills = []);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show NOTHING if no matching bills — no spinner, no empty state
    if (_bills.isEmpty) return const SizedBox.shrink();

    final fmt = NumberFormat('#,##0.00');

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
          // ── Header ───────────────────────────────────────────────────────
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
                if (widget.selectedBill != null)
                  GestureDetector(
                    onTap: () => widget.onBillSelected(null),
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: _secondary, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: _border, height: 1),

          // ── Bill list ─────────────────────────────────────────────────────
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _bills.length,
              itemBuilder: (context, i) {
                final bill      = _bills[i];
                final isSelected =
                    widget.selectedBill?.saleBillId == bill.saleBillId;

                return GestureDetector(
                  onTap: () =>
                      widget.onBillSelected(isSelected ? null : bill),
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
                                  color: isSelected ? _accent : Colors.white,
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
                        Text(
                          '₹${fmt.format(bill.billTotal)}',
                          style: TextStyle(
                            color: isSelected ? _accent : _green,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
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
