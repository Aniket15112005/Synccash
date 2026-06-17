import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/sale_bill_entity.dart';
import '../providers/party_provider.dart';
import '../providers/sale_bill_provider.dart';
import 'bill_detail_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens — minimalist grey aesthetic (matches sales_screen)
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg      = Color(0xFF0F1011);
  static const surface = Color(0xFF1A1B1E);
  static const panel   = Color(0xFF1E1F22);
  static const line    = Color(0xFF2C2D32);
  static const line2   = Color(0xFF363840);
  static const muted   = Color(0xFF565860);
  static const muted2  = Color(0xFF8C8E9A);
  static const accent  = Color(0xFF64748B);
  static const accent2 = Color(0xFF94A3B8);
  static const text    = Color(0xFFF1F2F5);
  static const text2   = Color(0xFFB4B6C4);
  static const green   = Color(0xFF4ADE80);
  static const amber   = Color(0xFFFBBF24);
  static const red     = Color(0xFFFC8181);
  static const darkOrange = Color(0xFFD4580A);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Payment record model (individual income transaction for this party)
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentRecord {
  final String?  linkedBillId;
  final double   amount;
  final DateTime createdAt;
  /// True for transactions explicitly stamped with isObPayment=true in
  /// Firestore (written by recordObPaymentWithOverflow). False for all
  /// bill-linked payments and old-style description-matched unlinked payments.
  final bool     isOb;
  const _PaymentRecord({
    required this.linkedBillId,
    required this.amount,
    required this.createdAt,
    this.isOb = false,
  });
}

class _GroupedPayment {
  final DateTime createdAt;
  final double   amount;
  const _GroupedPayment({required this.createdAt, required this.amount});
}

List<_GroupedPayment> _groupPayments(List<_PaymentRecord> payments) {
  final map = <DateTime, double>{};
  for (final p in payments) {
    map[p.createdAt] = (map[p.createdAt] ?? 0.0) + p.amount;
  }
  return map.entries
      .map((e) => _GroupedPayment(createdAt: e.key, amount: e.value))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

// ─────────────────────────────────────────────────────────────────────────────
//  All Bills Screen
// ─────────────────────────────────────────────────────────────────────────────

class AllBillsScreen extends ConsumerStatefulWidget {
  final String               partyName;
  final List<SaleBillEntity> bills;
  final Map<String, double>  received;

  const AllBillsScreen({
    super.key,
    required this.partyName,
    required this.bills,
    required this.received,
  });

  @override
  ConsumerState<AllBillsScreen> createState() => _AllBillsScreenState();
}

class _AllBillsScreenState extends ConsumerState<AllBillsScreen> {
  String _searchQuery = '';

  Future<void> _delete(
    SaleBillEntity bill,
    String? cashbookId,
  ) async {
    if (cashbookId == null) return;
    HapticFeedback.mediumImpact();
    final ok = await _confirmDialog(
      context,
      title:   'Delete Bill?',
      body:    'Bill "${bill.billNumber}" will be permanently deleted. '
               'Payment records in the cashbook are kept.',
      confirm: 'Delete',
      danger:  true,
    );
    if (ok != true) return;
    try {
      await ref
          .read(saleBillActionsProvider.notifier)
          .deleteBill(cashbookId: cashbookId, billId: bill.saleBillId);
    } catch (e) {
      if (mounted) _snack(context, 'Failed: $e', ok: false);
    }
  }

  void _edit(
    SaleBillEntity bill,
    String? cashbookId,
  ) {
    if (cashbookId == null) return;
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _EditBillSheet(bill: bill, cashbookId: cashbookId),
    );
  }

  void _showSearchSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillSearchSheet(
        initialQuery: _searchQuery,
        onChanged: (q) {
          if (mounted) setState(() => _searchQuery = q.trim().toLowerCase());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yy');
    final sorted  = List<SaleBillEntity>.from(widget.bills)
      ..sort((a, b) => b.billCreatedAt.compareTo(a.billCreatedAt));

    final filtered = _searchQuery.isEmpty
        ? sorted
        : sorted.where((b) {
            final q = _searchQuery;
            return b.billNumber.toLowerCase().contains(q) ||
                dateFmt.format(b.billDate).toLowerCase().contains(q) ||
                dateFmt.format(b.billCreatedAt).toLowerCase().contains(q) ||
                fmt.format(b.billTotal).contains(q) ||
                b.billTotal.toStringAsFixed(0).contains(q);
          }).toList();

    double totalBilled   = 0;
    double totalReceived = 0;
    for (final b in sorted) {
      totalBilled   += b.billTotal;
      totalReceived += widget.received[b.saleBillId] ?? 0.0;
    }
    final due = (totalBilled - totalReceived).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: _T.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: _BackBtn(onTap: () => Navigator.pop(context)),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.partyName,
                    style: const TextStyle(
                        color: _T.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2)),
                Text(
                  _searchQuery.isEmpty
                      ? '${widget.bills.length} bills'
                      : '${filtered.length} of ${widget.bills.length} bills',
                  style: const TextStyle(color: _T.muted2, fontSize: 10),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _searchQuery.isEmpty
                      ? Icons.search_rounded
                      : Icons.search_off_rounded,
                  color: _searchQuery.isEmpty ? _T.muted2 : _T.accent2,
                  size: 20,
                ),
                onPressed: () {
                  if (_searchQuery.isNotEmpty) {
                    setState(() => _searchQuery = '');
                  } else {
                    _showSearchSheet();
                  }
                },
                tooltip: _searchQuery.isEmpty ? 'Search' : 'Clear search',
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: _T.line),
            ),
          ),

          // ── Summary row ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: _T.bg,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: _ThreeStats(
                billed:         totalBilled,
                received:       totalReceived,
                closingBalance: due,
                fmt:            fmt,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(height: 1, color: _T.line),
          ),

          // ── Bills ────────────────────────────────────────────────────────
          filtered.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'No bills'
                          : 'No bills match "$_searchQuery"',
                      style: const TextStyle(color: _T.muted2, fontSize: 13),
                    ),
                  ),
                )
              : SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final bill = filtered[i];
                    final rec  = widget.received[bill.saleBillId] ?? 0.0;
                    final rem  =
                        (bill.billTotal - rec).clamp(0.0, double.infinity);
                    return RepaintBoundary(
                      child: _BillRow(
                        bill:      bill,
                        received:  rec,
                        remaining: rem,
                        fmt:       fmt,
                        dateFmt:   dateFmt,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                              ctx,
                              _route(BillDetailScreen(
                                  bill: bill, billCount: widget.bills.length)));
                        },
                        onEdit:   () => _edit(bill, cashbookId),
                        onDelete: () => _delete(bill, cashbookId),
                      ),
                    );
                  },
                ),

          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party Detail Screen
// ─────────────────────────────────────────────────────────────────────────────

class PartyDetailScreen extends ConsumerStatefulWidget {
  final String               partyName;
  final List<SaleBillEntity> initialBills;
  const PartyDetailScreen({
    super.key,
    required this.partyName,
    this.initialBills = const [],
  });

  @override
  ConsumerState<PartyDetailScreen> createState() => _PartyDetailState();
}

class _PartyDetailState extends ConsumerState<PartyDetailScreen> {
  static const int _kPage = 5;

  StreamSubscription<QuerySnapshot>?    _billsSub;
  StreamSubscription<QuerySnapshot>?    _txSub;
  StreamSubscription<DocumentSnapshot>? _partySub;
  ProviderSubscription<String?>?        _idSub;
  String?                               _cashbookId;

  List<SaleBillEntity>       _bills    = [];
  Map<String, double>        _received = {};
  List<_PaymentRecord>       _payments = [];
  PartyEntity?               _party;
  // Raw income-tx snapshots so we can recompute _received/_payments
  // whenever _bills changes (the two streams fire independently).
  List<Map<String, dynamic>> _rawTxs   = [];
  // Amount paid toward opening balance via isObPayment=true transactions.
  // Tracked separately so it never leaks into bill received calculations.
  double                     _obPaid   = 0.0;
  String                     _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _bills = List<SaleBillEntity>.from(widget.initialBills);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Delay past the route-transition duration (260 ms forward / 220 ms reverse)
      // so Firestore local-cache emissions don't call setState mid-animation.
      Future.delayed(const Duration(milliseconds: 310), () {
        if (!mounted) return;
        _idSub = ref.listenManual<String?>(
          currentCashbookIdProvider,
          (_, next) {
            if (next != null && next.isNotEmpty && next != _cashbookId) {
              _cashbookId = next;
              _cancelStreams();
              _start(next);
            }
          },
          fireImmediately: true,
        );
      });
    });
  }

  void _cancelStreams() {
    _billsSub?.cancel();
    _txSub?.cancel();
    _partySub?.cancel();
  }

  void _start(String cashbookId) {
    if (!mounted) return;
    final partyName = widget.partyName.trim();
    final partyLow  = partyName.toLowerCase();

    _billsSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('sale_bills')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs
          .where((doc) =>
              (doc.data()['partyName'] as String? ?? '')
                  .trim()
                  .toLowerCase() ==
              partyLow)
          .map((doc) {
        final d = doc.data();
        return SaleBillEntity(
          saleBillId:        d['saleBillId'] as String? ?? doc.id,
          partyName:         d['partyName'] as String? ?? '',
          billNumber:        d['billNumber'] as String? ?? '',
          billTotal:         (d['billTotal'] as num?)?.toDouble() ?? 0.0,
          billDate:          (d['billDate'] as Timestamp?)?.toDate() ??
              DateTime.now(),
          billNote:          d['billNote'] as String?,
          billCreatedAt:     (d['billCreatedAt'] as Timestamp?)?.toDate() ??
              DateTime.now(),
          billCreatedBy:     d['billCreatedBy'] as String? ?? '',
          billCreatedByName: d['billCreatedByName'] as String? ?? '',
          billStatus:        d['billStatus'] as String? ?? 'pending',
        );
      }).toList()
        ..sort((a, b) => b.billCreatedAt.compareTo(a.billCreatedAt));
      if (mounted) setState(() {
        _bills = list;
        _recomputeReceived();
      });
    }, onError: (_) {});

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      // Store raw data; _recomputeReceived filters to this party's bills.
      _rawTxs = snap.docs.map((d) => d.data()).toList();
      if (mounted) setState(() => _recomputeReceived());
    }, onError: (_) {});

    _partySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .doc(partyLow)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _party = doc.exists ? PartyEntity.fromDoc(doc) : null;
        // Recompute because OB value affects FIFO distribution.
        _recomputeReceived();
      });
    }, onError: (_) {});
  }

  // Recompute received amounts and payment records from stored raw snapshots.
  // Called from both _billsSub and _txSub so whichever stream fires first,
  // the other's data is still incorporated correctly.
  // KEY FIX: only payments whose linkedBillId belongs to THIS party's bills
  // are counted -- preventing other parties' transactions from leaking in.
  void _recomputeReceived() {
    final partyLow = widget.partyName.trim().toLowerCase();
    final billIds  = {for (final b in _bills) b.saleBillId};

    final map      = <String, double>{};
    final payments = <_PaymentRecord>[];
    double obPaid  = 0.0;

    double totalOldUnlinked = 0.0;
    final  oldUnlinkedRecs  = <_PaymentRecord>[];

    for (final raw in _rawTxs) {
      final linkedId    = raw['linkedSaleBillId'] as String?;
      final amount      = (raw['amount'] as num?)?.toDouble() ?? 0.0;
      final desc        = (raw['description'] as String? ?? '').toLowerCase();
      final createdAt   = (raw['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final isObPayment = raw['isObPayment'] as bool? ?? false;
      final obPartyName = (raw['obPartyName'] as String? ?? '').toLowerCase().trim();

      if (linkedId != null && linkedId.isNotEmpty) {
        // Only count this payment if the bill belongs to THIS party.
        if (billIds.contains(linkedId)) {
          // ── Single-bill overflow-to-OB rule ────────────────────────────
          // When the party has exactly 1 bill, cap the linked payment at
          // the bill's remaining balance and automatically route any
          // overflow to the opening balance (if OB is still outstanding).
          if (_bills.length == 1) {
            final alreadyRcvd = map[linkedId] ?? 0.0;
            final billRemain  =
                (_bills.first.billTotal - alreadyRcvd).clamp(0.0, double.infinity);
            final toBill      = amount > billRemain ? billRemain : amount;
            final overflow    = amount - toBill;
            map[linkedId]     = alreadyRcvd + toBill;
            if (overflow > 0) {
              final ob          = _party?.openingBalance ?? 0.0;
              final remainingOb = (ob - obPaid).clamp(0.0, double.infinity);
              obPaid += overflow > remainingOb ? remainingOb : overflow;
            }
          } else {
            map[linkedId] = (map[linkedId] ?? 0.0) + amount;
          }
          payments.add(_PaymentRecord(
              linkedBillId: linkedId, amount: amount, createdAt: createdAt));
        }
      } else if (isObPayment &&
          (obPartyName == partyLow ||
           (obPartyName.isEmpty && desc.contains(partyLow)))) {
        // New-style flagged OB payment — track in obPaid directly.
        obPaid += amount;
        payments.add(_PaymentRecord(
            linkedBillId: null, amount: amount, createdAt: createdAt, isOb: true));
      } else if (desc.contains(partyLow)) {
        // Old-style description-matched unlinked payment (pre-isObPayment era).
        // Accumulated here; distributed FIFO (OB first, then bills oldest→newest)
        // in the pass below so the correct buckets receive the money.
        totalOldUnlinked += amount;
        oldUnlinkedRecs.add(_PaymentRecord(
            linkedBillId: null, amount: amount, createdAt: createdAt));
      }
    }

    // ── FIFO distribution of old-style unlinked payments ─────────────────────
    // Rule: fill bills oldest→newest first; any overflow then goes to OB.
    if (totalOldUnlinked > 0) {
      payments.addAll(oldUnlinkedRecs);

      var overflow = totalOldUnlinked;

      // Step 1: Apply to bills oldest→newest.
      if (_bills.isNotEmpty) {
        final sortedBills = List<SaleBillEntity>.from(_bills)
          ..sort((a, b) => a.billDate.compareTo(b.billDate));
        for (final bill in sortedBills) {
          if (overflow <= 0) break;
          final alreadyRcvd = map[bill.saleBillId] ?? 0.0;
          final billRemain  =
              (bill.billTotal - alreadyRcvd).clamp(0.0, double.infinity);
          final toThisBill  =
              overflow > billRemain ? billRemain : overflow;
          if (toThisBill > 0) {
            map[bill.saleBillId] = alreadyRcvd + toThisBill;
          }
          overflow -= toThisBill;
        }
      }

      // Step 2: Apply remaining overflow to opening balance.
      if (overflow > 0) {
        final ob          = (_party?.openingBalance ?? 0.0);
        final remainingOb = (ob - obPaid).clamp(0.0, double.infinity);
        final toOb        = overflow > remainingOb ? remainingOb : overflow;
        obPaid           += toOb;
      }
    }

    _received = map;
    _payments = payments;
    _obPaid   = obPaid;
  }

  @override
  void dispose() {
    _idSub?.close();
    _cancelStreams();
    super.dispose();
  }

  double _recForBill(SaleBillEntity b) {
    // Bills get their exact share from _recomputeReceived (FIFO-distributed).
    // No _unlinked shortcut needed — amounts go directly into map[billId].
    return _received[b.saleBillId] ?? 0.0;
  }

  double get _totalBilled   => _bills.fold(0.0, (s, b) => s + b.billTotal);
  double get _totalReceived => _bills.fold(0.0, (s, b) => s + _recForBill(b));
  // Includes all bill received amounts + OB payments (closing balance calc).
  double get _totalAllReceived =>
      _bills.fold(0.0, (s, b) => s + (_received[b.saleBillId] ?? 0.0))
      + _obPaid;
  double get _totalDue =>
      (_totalBilled - _totalReceived).clamp(0.0, double.infinity);
  double get _pct =>
      _totalBilled > 0
          ? (_totalReceived / _totalBilled).clamp(0.0, 1.0)
          : 0.0;

  Map<String, double> get _perBillMap =>
      {for (final b in _bills) b.saleBillId: _recForBill(b)};

  // ── Delete Bill ──────────────────────────────────────────────────────────
  Future<void> _deleteBill(SaleBillEntity bill) async {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();
    final ok = await _confirmDialog(
      context,
      title:   'Delete Bill?',
      body:    'Bill "${bill.billNumber}" will be permanently deleted. '
               'Payment records in the cashbook are kept.',
      confirm: 'Delete',
      danger:  true,
    );
    if (ok != true) return;
    try {
      await ref.read(saleBillActionsProvider.notifier).deleteBill(
          cashbookId: _cashbookId!, billId: bill.saleBillId);
      if (mounted) _snack(context, 'Bill deleted', ok: true);
    } catch (e) {
      if (mounted) _snack(context, 'Failed: $e', ok: false);
    }
  }

  // ── Edit Bill ────────────────────────────────────────────────────────────
  void _editBill(SaleBillEntity bill) {
    if (_cashbookId == null) return;
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _EditBillSheet(bill: bill, cashbookId: _cashbookId!),
    );
  }

  // ── Delete OB ────────────────────────────────────────────────────────────
  Future<void> _deleteOB() async {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();
    final ok = await _confirmDialog(
      context,
      title:   'Clear Opening Balance?',
      body:    'The opening balance for this party will be set to zero.',
      confirm: 'Clear',
      danger:  true,
    );
    if (ok != true) return;
    try {
      final partyLow = widget.partyName.trim().toLowerCase();
      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(_cashbookId)
          .collection('parties')
          .doc(partyLow)
          .update({'openingBalance': 0});
      if (mounted) _snack(context, 'Opening balance cleared', ok: true);
    } catch (e) {
      if (mounted) _snack(context, 'Failed: $e', ok: false);
    }
  }

  void _showBillsDetail() {
    HapticFeedback.selectionClick();
    final ob = _party?.openingBalance ?? 0.0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillsDetailSheet(
        partyName: widget.partyName,
        bills:     _bills,
        ob:        ob,
      ),
    );
  }

  void _showReceivedDetail() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReceivedDetailSheet(
        partyName: widget.partyName,
        payments:  _payments,
        bills:     _bills,
      ),
    );
  }


  void _showSearchSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillSearchSheet(
        initialQuery: _searchQuery,
        onChanged: (q) {
          if (mounted) setState(() => _searchQuery = q.trim().toLowerCase());
        },
      ),
    );
  }

  // ── Generate & Share PDF ────────────────────────────────────────────────────
  Future<void> _generateAndSharePdf() async {
    if (_bills.isEmpty) {
      _snack(context, 'No bills to share', ok: false);
      return;
    }
    HapticFeedback.mediumImpact();

    // ── TO UPDATE YOUR COMPANY NAME: change the string below ─────────────────
    const companyName = 'NEELKANTH GARMENTS';
    // ─────────────────────────────────────────────────────────────────────────

    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yyyy');
    final now     = dateFmt.format(DateTime.now());

    final ob          = _party?.openingBalance ?? 0.0;
    final totalBilled = ob + _totalBilled;
    final totalRcvd   = _totalAllReceived;
    final closingBal  = ob + _totalBilled - _totalAllReceived;

    // Group payments by bill ID, sorted oldest-first
    final payMap = <String, List<_PaymentRecord>>{};
    for (final p in _payments) {
      if (p.linkedBillId != null) {
        payMap.putIfAbsent(p.linkedBillId!, () => []).add(p);
      }
    }
    for (final list in payMap.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final sorted = List<SaleBillEntity>.from(_bills)
      ..sort((a, b) => a.billDate.compareTo(b.billDate));

    final clearedCount = sorted.where((b) {
      final paid = payMap[b.saleBillId]
              ?.fold(0.0, (s, p) => s + p.amount) ?? 0.0;
      return paid >= b.billTotal;
    }).length;
    final pendingCount = sorted.length - clearedCount;

    // PDF colors
    final cBlue      = PdfColor.fromHex('1e3a5f');
    final cWhite     = PdfColors.white;
    final cGreen     = PdfColor.fromHex('15803d');
    final cRed       = PdfColor.fromHex('b91c1c');
    final cGrey      = PdfColor.fromHex('6b7280');
    final cDarkText  = PdfColor.fromHex('111827');
    final cLightGrey = PdfColor.fromHex('f9fafb');
    final cAmber     = PdfColor.fromHex('f59e0b');
    final cLightBlue = PdfColor.fromHex('eff6ff');
    final cLightGrn  = PdfColor.fromHex('f0fdf4');
    final cLightRed  = PdfColor.fromHex('fff1f2');
    final cSubGrey   = PdfColor.fromHex('9ca3af');
    final cMidDark   = PdfColor.fromHex('374151');
    final cGrnLight  = PdfColor.fromHex('86efac');
    final cRedLight  = PdfColor.fromHex('fca5a5');

    // Local helper — one stats box
    pw.Widget stat(String label, String value,
            PdfColor valueColor, PdfColor bg) =>
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 10, vertical: 9),
            decoration: pw.BoxDecoration(
              color: bg,
              border:
                  pw.Border.all(color: PdfColor.fromHex('e5e7eb')),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label,
                    style: pw.TextStyle(
                        color: cGrey, fontSize: 7)),
                pw.SizedBox(height: 3),
                pw.Text(value,
                    style: pw.TextStyle(
                        color: valueColor,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(
            horizontal: 36, vertical: 36),
        build: (ctx) => [

          // ── Header bar ──────────────────────────────────────────────
          pw.Container(
            decoration: pw.BoxDecoration(color: cBlue),
            padding: const pw.EdgeInsets.fromLTRB(
                20, 16, 20, 16),
            child: pw.Row(
              mainAxisAlignment:
                  pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(companyName,
                    style: pw.TextStyle(
                        color: cWhite,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold)),
                pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('PARTY STATEMENT',
                        style: pw.TextStyle(
                            color:
                                PdfColor.fromHex('7ab3d8'),
                            fontSize: 8)),
                    pw.SizedBox(height: 3),
                    pw.Text('As of $now',
                        style: pw.TextStyle(
                            color: cWhite,
                            fontSize: 10,
                            fontWeight:
                                pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // ── Accent bar ──────────────────────────────────────────────
          pw.Container(
            height: 3,
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                  colors: [cAmber, cBlue]),
            ),
          ),

          pw.SizedBox(height: 10),

          // ── Party + summary row ─────────────────────────────────────
          pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment:
                pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('PARTY',
                      style: pw.TextStyle(
                          color: cGrey, fontSize: 8)),
                  pw.SizedBox(height: 2),
                  pw.Text(widget.partyName,
                      style: pw.TextStyle(
                          color: cDarkText,
                          fontSize: 14,
                          fontWeight:
                              pw.FontWeight.bold)),
                ],
              ),
              pw.Text(
                'Bills: ${sorted.length}   '
                'Cleared: $clearedCount   '
                'Pending: $pendingCount',
                style: pw.TextStyle(
                    color: cGrey, fontSize: 9),
              ),
            ],
          ),

          pw.SizedBox(height: 10),

          // ── Stats boxes ─────────────────────────────────────────────
          pw.Row(
            children: [
              stat('TOTAL BILLED',
                  'Rs. ${fmt.format(totalBilled)}',
                  cBlue, cLightBlue),
              pw.SizedBox(width: 6),
              stat('TOTAL RECEIVED',
                  'Rs. ${fmt.format(totalRcvd)}',
                  cGreen, cLightGrn),
              pw.SizedBox(width: 6),
              stat(
                'BALANCE DUE',
                'Rs. ${fmt.format(closingBal.clamp(0.0, double.infinity))}',
                closingBal > 0 ? cRed : cGreen,
                closingBal > 0 ? cLightRed : cLightGrn,
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          pw.Text('BILL DETAILS',
              style: pw.TextStyle(
                  color: cGrey,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),

          // ── Bills table ─────────────────────────────────────────────
          pw.Table(
            border: pw.TableBorder(
              bottom: pw.BorderSide(
                  color: PdfColor.fromHex('e5e7eb')),
              horizontalInside: pw.BorderSide(
                  color: PdfColor.fromHex('f0f0f0')),
            ),
            columnWidths: const {
              0: pw.FixedColumnWidth(20),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(2.0),
              3: pw.FlexColumnWidth(2.0),
              4: pw.FlexColumnWidth(2.0),
              5: pw.FlexColumnWidth(1.8),
              6: pw.FlexColumnWidth(2.2),
            },
            children: [

              // Header row
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: cBlue),
                children: [
                  '#', 'Bill No.', 'Bill Date',
                  'Bill Amt', 'Pay Date', 'Paid',
                  'Balance / Status',
                ].asMap().entries.map((e) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5, vertical: 7),
                  child: pw.Text(e.value,
                      textAlign: e.key == 0
                          ? pw.TextAlign.center
                          : e.key >= 3
                              ? pw.TextAlign.right
                              : pw.TextAlign.left,
                      style: pw.TextStyle(
                          color: cWhite,
                          fontSize: 8,
                          fontWeight:
                              pw.FontWeight.bold)),
                )).toList(),
              ),

              // Opening Balance row (first entry if ob > 0)
              if (ob > 0) ...[
                () {
                  // Use isOb flag: only explicitly-flagged OB payments count
                  // here. Old-style unlinked are FIFO-distributed at display
                  // time, so the OB portion lives in _obPaid state directly.
                  final obPays = _payments
                      .where((p) => p.isOb)
                      .toList()
                    ..sort((a, b) =>
                        a.createdAt.compareTo(b.createdAt));
                  final obPaid = _obPaid;
                  final obCleared = obPaid >= ob;
                  final obRem =
                      (ob - obPaid).clamp(0.0, double.infinity);
                  final obPayDate = obPays.isNotEmpty
                      ? dateFmt.format(obPays.first.createdAt)
                      : '';

                  pw.Widget obCell(
                    String text, {
                    pw.TextAlign align = pw.TextAlign.left,
                    PdfColor? color,
                    double size = 8,
                    bool bold = false,
                  }) =>
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 5, vertical: 7),
                        child: pw.Text(text,
                            textAlign: align,
                            style: pw.TextStyle(
                                color: color ?? cDarkText,
                                fontSize: size,
                                fontWeight: bold
                                    ? pw.FontWeight.bold
                                    : pw.FontWeight.normal)),
                      );

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: cLightBlue),
                    children: [
                      obCell('1',
                          align: pw.TextAlign.center,
                          color: cSubGrey),
                      obCell('Opening Balance',
                          color: cMidDark,
                          size: 9,
                          bold: true),
                      obCell(''),            // date — leave empty
                      obCell('Rs. ${fmt.format(ob)}',
                          align: pw.TextAlign.right,
                          size: 9,
                          bold: true),
                      obCell(obPayDate,
                          align: pw.TextAlign.right,
                          color: obPayDate.isNotEmpty
                              ? cMidDark : cSubGrey),
                      obCell(
                          obPaid > 0
                              ? 'Rs. ${fmt.format(obPaid)}'
                              : '-',
                          align: pw.TextAlign.right,
                          color: obPaid > 0 ? cGreen : cSubGrey,
                          bold: obPaid > 0),
                      obCleared
                          ? pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 7),
                              child: pw.Text('Cleared',
                                  textAlign: pw.TextAlign.right,
                                  style: pw.TextStyle(
                                      color: cGreen,
                                      fontSize: 8,
                                      fontWeight: pw.FontWeight.bold)),
                            )
                          : obCell('Rs. ${fmt.format(obRem)}',
                              align: pw.TextAlign.right,
                              color: cRed,
                              size: 9,
                              bold: true),
                    ],
                  );
                }(),
              ],

              // Data rows
              ...sorted.asMap().entries.map((entry) {
                final idx  = entry.key;
                final bill = entry.value;
                final pays =
                    payMap[bill.saleBillId] ?? [];
                final paid = pays.fold(
                    0.0, (s, p) => s + p.amount);
                final rem =
                    (bill.billTotal - paid)
                        .clamp(0.0, double.infinity);
                final cleared = rem <= 0;

                String payDateStr = '-';
                if (pays.isNotEmpty) {
                  payDateStr =
                      dateFmt.format(pays.first.createdAt);
                  if (pays.length > 1) {
                    payDateStr +=
                        ' +${pays.length - 1}';
                  }
                }

                final rowBg = idx % 2 == 0
                    ? cLightGrey
                    : PdfColors.white;

                pw.Widget cell(
                  String text, {
                  pw.TextAlign align =
                      pw.TextAlign.left,
                  PdfColor? color,
                  double size = 8,
                  bool bold = false,
                }) =>
                    pw.Padding(
                      padding: const pw.EdgeInsets
                          .symmetric(
                          horizontal: 5, vertical: 7),
                      child: pw.Text(text,
                          textAlign: align,
                          style: pw.TextStyle(
                              color: color ?? cDarkText,
                              fontSize: size,
                              fontWeight: bold
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight
                                      .normal)),
                    );

                return pw.TableRow(
                  decoration:
                      pw.BoxDecoration(color: rowBg),
                  children: [
                    cell('${idx + 1 + (ob > 0 ? 1 : 0)}',
                        align: pw.TextAlign.center,
                        color: cSubGrey),
                    cell(bill.billNumber,
                        color: cBlue,
                        size: 9,
                        bold: true),
                    cell(dateFmt.format(bill.billDate),
                        color: PdfColor.fromHex(
                            '4b5563')),
                    cell(
                        'Rs. ${fmt.format(bill.billTotal)}',
                        align: pw.TextAlign.right,
                        size: 9,
                        bold: true),
                    cell(payDateStr,
                        align: pw.TextAlign.right,
                        color: pays.isNotEmpty
                            ? cMidDark
                            : cSubGrey),
                    cell(
                        paid > 0
                            ? 'Rs. ${fmt.format(paid)}'
                            : '-',
                        align: pw.TextAlign.right,
                        color:
                            paid > 0 ? cGreen : cSubGrey,
                        bold: paid > 0),
                    cleared
                        ? pw.Padding(
                            padding:
                                const pw.EdgeInsets
                                    .symmetric(
                                horizontal: 5,
                                vertical: 7),
                            child: pw.Text(
                              'Bill Cleared',
                              textAlign:
                                  pw.TextAlign.right,
                              style: pw.TextStyle(
                                  color: cGreen,
                                  fontSize: 8,
                                  fontWeight:
                                      pw.FontWeight
                                          .bold),
                            ),
                          )
                        : cell(
                            'Rs. ${fmt.format(rem)}',
                            align: pw.TextAlign.right,
                            color: cRed,
                            size: 9,
                            bold: true),
                  ],
                );
              }),

              // Totals row
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: cBlue),
                children: [
                  for (final t in [
                    ('', pw.TextAlign.left, cWhite, 9.0,
                        false),
                    ('Total', pw.TextAlign.left, cWhite,
                        9.0, true),
                    ('', pw.TextAlign.left, cWhite, 9.0,
                        false),
                    ('Rs. ${fmt.format(totalBilled)}',
                        pw.TextAlign.right, cWhite, 10.0,
                        true),
                    ('', pw.TextAlign.left, cWhite, 9.0,
                        false),
                    ('Rs. ${fmt.format(totalRcvd)}',
                        pw.TextAlign.right, cGrnLight,
                        10.0, true),
                    (closingBal > 0
                        ? 'Rs. ${fmt.format(closingBal)} Due'
                        : 'Settled',
                        pw.TextAlign.right,
                        closingBal > 0
                            ? cRedLight
                            : cGrnLight,
                        9.0, true),
                  ])
                    pw.Padding(
                      padding: const pw.EdgeInsets
                          .symmetric(
                          horizontal: 5, vertical: 8),
                      child: pw.Text(t.$1,
                          textAlign: t.$2,
                          style: pw.TextStyle(
                              color: t.$3,
                              fontSize: t.$4,
                              fontWeight: t.$5
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight
                                      .normal)),
                    ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 14),

          pw.Text('PAYMENT HISTORY',
              style: pw.TextStyle(
                  color: cGrey,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),

          pw.Table(
            border: pw.TableBorder(
              bottom: pw.BorderSide(
                  color: PdfColor.fromHex('e5e7eb')),
              horizontalInside: pw.BorderSide(
                  color: PdfColor.fromHex('f0f0f0')),
            ),
            columnWidths: const {
              0: pw.FixedColumnWidth(20),
              1: pw.FlexColumnWidth(3.5),
              2: pw.FlexColumnWidth(2.5),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: cBlue),
                children: [
                  '#', 'Payment Date', 'Amount',
                ].asMap().entries.map((e) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5, vertical: 7),
                  child: pw.Text(e.value,
                      textAlign: e.key == 2
                          ? pw.TextAlign.right
                          : e.key == 0
                              ? pw.TextAlign.center
                              : pw.TextAlign.left,
                      style: pw.TextStyle(
                          color: cWhite,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold)),
                )).toList(),
              ),
              ..._groupPayments(_payments).asMap().entries.map((entry) {
                final idx = entry.key;
                final g   = entry.value;
                final rowBg = idx % 2 == 0 ? cLightGrey : PdfColors.white;
                pw.Widget pcell(
                  String text, {
                  pw.TextAlign align = pw.TextAlign.left,
                  PdfColor? color,
                  double size = 8,
                  bool bold = false,
                }) =>
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 5, vertical: 7),
                      child: pw.Text(text,
                          textAlign: align,
                          style: pw.TextStyle(
                              color: color ?? cDarkText,
                              fontSize: size,
                              fontWeight: bold
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal)),
                    );
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowBg),
                  children: [
                    pcell('${idx + 1}',
                        align: pw.TextAlign.center,
                        color: cSubGrey),
                    pcell(dateFmt.format(g.createdAt),
                        color: cMidDark),
                    pcell('Rs. ${fmt.format(g.amount)}',
                        align: pw.TextAlign.right,
                        color: cGreen,
                        size: 9,
                        bold: true),
                  ],
                );
              }),
              pw.TableRow(
                decoration: pw.BoxDecoration(color: cBlue),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 8),
                    child: pw.Text('',
                        style: pw.TextStyle(
                            color: cWhite, fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 8),
                    child: pw.Text('Total',
                        style: pw.TextStyle(
                            color: cWhite,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 8),
                    child: pw.Text('Rs. ${fmt.format(totalRcvd)}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            color: cGrnLight,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 16),

          // ── Footer ──────────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment:
                pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Notes:',
                      style: pw.TextStyle(
                          color: cDarkText,
                          fontSize: 8,
                          fontWeight:
                              pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '- Amounts in Indian Rupees (Rs.)',
                    style: pw.TextStyle(
                        color: cGrey, fontSize: 7.5)),
                  pw.Text(
                    '- Multiple payments: earliest date + count',
                    style: pw.TextStyle(
                        color: cGrey, fontSize: 7.5)),
                  pw.Text(
                    '- Computer-generated statement',
                    style: pw.TextStyle(
                        color: cGrey, fontSize: 7.5)),
                ],
              ),
              pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 28),
                  pw.Container(
                    width: 120,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(
                            color: cMidDark),
                      ),
                    ),
                    padding:
                        const pw.EdgeInsets.only(top: 4),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'Authorised Signatory',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              color: cGrey,
                              fontSize: 7.5),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          companyName,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              color: cBlue,
                              fontSize: 8,
                              fontWeight:
                                  pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 10),
          pw.Divider(color: cBlue, thickness: 1.5),
        ],
      ),
    );

    final bytes = await doc.save();
    final safeName = widget.partyName
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(' ', '_');

    if (!mounted) return;
    if (kIsWeb) {
      await Share.shareXFiles(
        [XFile.fromData(bytes,
            name: '${safeName}_statement.pdf',
            mimeType: 'application/pdf')],
        subject: '${widget.partyName} — Party Statement',
      );
    } else {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/${safeName}_statement.pdf');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '${widget.partyName} — Party Statement',
      );
    }
  }


  // ── Show Share Options Sheet ──────────────────────────────────────────────
  void _showShareOptions() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareOptionsSheet(
        onPdf:   _generateAndSharePdf,
        onImage: _showTransactionPicker,
      ),
    );
  }

  // ── Show Transaction Picker for Image ──────────────────────────────────────
  void _showTransactionPicker() {
    final grouped = _groupPayments(_payments);
    if (grouped.isEmpty) {
      _snack(context, 'No payment entries found', ok: false);
      return;
    }
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TransactionPickerSheet(
        grouped:  grouped,
        onSelect: (gp) {
          Navigator.of(ctx).pop();
          _generateAndShareImage(gp);
        },
      ),
    );
  }

  // ── Generate & Share Receipt Image ─────────────────────────────────────────
  Future<void> _generateAndShareImage(_GroupedPayment payment) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();

    const companyName = 'NEELKANTH GARMENTS';
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    final ob        = _party?.openingBalance ?? 0.0;
    // Total original amount this party owed (all bills + opening balance).
    final totalOwed = ob + _totalBilled;
    // Sum every payment that was recorded STRICTLY BEFORE this payment's
    // timestamp. _payments is already filtered to this party by
    // _recomputeReceived, so it is safe to use directly.
    final paidBefore = _payments
        .where((p) => p.createdAt.isBefore(payment.createdAt))
        .fold(0.0, (s, p) => s + p.amount);
    // TOTAL AMOUNT on the receipt = what was owed just BEFORE this payment.
    final totalAmount = (totalOwed - paidBefore).clamp(0.0, double.infinity);
    final amountPaid  = payment.amount;
    // BALANCE DUE on the receipt = what is still owed AFTER this payment.
    final balance     = (totalOwed - paidBefore - payment.amount)
        .clamp(0.0, double.infinity);
    final payDate     = dateFmt.format(payment.createdAt);

    // ── Canvas layout constants ────────────────────────────────────────────
    const double scale    = 3.0;   // 3× resolution — crisp on high-DPI screens
    const double cW       = 900;
    const double padH     = 48.0;   // horizontal padding
    const double headerH  = 110.0;
    const double divH     = 1.0;
    const double rowH     = 52.0;
    const double sectionH = 44.0;
    const double footerH  = 48.0;

    // rows: CLIENT, RECEIPT NUMBER, DATE, divider, TOTAL AMOUNT, AMOUNT PAID,
    //       BALANCE DUE, divider, ACCOUNT DETAILS header, ACCOUNT NAME, CATEGORY
    final double bodyH = headerH
        + divH + 14          // top divider + gap
        + rowH * 3           // CLIENT, RECEIPT NUMBER, DATE
        + 14 + divH + 14     // gap + divider + gap
        + rowH * 3           // TOTAL AMOUNT, AMOUNT PAID, BALANCE DUE
        + 14 + divH + 14     // gap + divider + gap
        + sectionH           // ACCOUNT DETAILS header
        + rowH * 2           // ACCOUNT NAME, CATEGORY
        + footerH;           // bottom padding

    final double cH = bodyH;

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    canvas.scale(scale, scale);            // scale up before any drawing

    // ── Overall background (app-matching dark) ─────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cW, cH),
      Paint()..color = const Color(0xFF0F1011),
    );

    // ── Card ──────────────────────────────────────────────────────────────
    const double cardMargin = 24.0;
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardMargin, cardMargin, cW - cardMargin * 2, cH - cardMargin * 2),
      const Radius.circular(18),
    );
    canvas.drawRRect(cardRect, Paint()..color = const Color(0xFF1A1B1E));
    canvas.drawRRect(
      cardRect,
      Paint()
        ..color = const Color(0xFF2C2D32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );

    // ── Helper: paragraph ─────────────────────────────────────────────────
    void drawPara(
      String text,
      double x,
      double y, {
      double fontSize = 14,
      Color color = const Color(0xFFF1F2F5),
      bool bold = false,
      double maxWidth = 800,
      ui.TextAlign align = ui.TextAlign.left,
    }) {
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign:  align,
        maxLines:   1,
        ellipsis:   '…',
      ))
        ..pushStyle(ui.TextStyle(
          color:      color,
          fontSize:   fontSize,
          fontWeight: ui.FontWeight.w700,
        ))
        ..addText(text);
      final para = pb.build()..layout(ui.ParagraphConstraints(width: maxWidth));
      canvas.drawParagraph(para, Offset(x, y));
    }

    // ── Helper: horizontal divider inside card ─────────────────────────────
    void drawDiv(double y) {
      canvas.drawLine(
        Offset(cardMargin + padH, y),
        Offset(cW - cardMargin - padH, y),
        Paint()
          ..color = const Color(0xFF2C2D32)
          ..strokeWidth = divH,
      );
    }

    // ── Helper: label + right-aligned value row ────────────────────────────
    const double innerLeft  = cardMargin + padH;
    const double innerRight = cW - cardMargin - padH;
    const double innerW     = cW - cardMargin * 2 - padH * 2;

    void drawRow(String label, String value, double y,
        {Color valueColor = const Color(0xFFFFFFFF)}) {
      drawPara(label, innerLeft, y + 16,
          fontSize: 11, color: const Color(0xFFFFFFFF));
      drawPara(value, innerLeft, y + 16,
          fontSize: 15,
          color: valueColor,
          bold: true,
          align: ui.TextAlign.right,
          maxWidth: innerW);
    }

    // ════════════════════════════════════════════════════════════════════════
    // HEADER
    // ════════════════════════════════════════════════════════════════════════
    const double hBase = cardMargin + 28;
    drawPara(
      companyName.toUpperCase(),
      innerLeft,
      hBase,
      fontSize: 22,
      color: const Color(0xFFF1F2F5),
      bold: true,
      align: ui.TextAlign.center,
      maxWidth: innerW,
    );
    drawPara(
      'PAYMENT RECEIPT',
      innerLeft,
      hBase + 34,
      fontSize: 11,
      color: const Color(0xFFFFFFFF),
      align: ui.TextAlign.center,
      maxWidth: innerW,
    );

    // ── Divider after header ───────────────────────────────────────────────
    double curY = cardMargin + headerH;
    drawDiv(curY);
    curY += 14;

    // ════════════════════════════════════════════════════════════════════════
    // META ROWS
    // ════════════════════════════════════════════════════════════════════════
    drawRow('CLIENT', widget.partyName, curY);
    curY += rowH;
    drawRow('RECEIPT NUMBER', '1', curY);
    curY += rowH;
    drawRow('DATE', payDate, curY);
    curY += rowH;

    curY += 14;
    drawDiv(curY);
    curY += 14;

    // ════════════════════════════════════════════════════════════════════════
    // AMOUNT ROWS
    // ════════════════════════════════════════════════════════════════════════
    drawRow('TOTAL AMOUNT', '₹${fmt.format(totalAmount)}', curY);
    curY += rowH;
    drawRow('AMOUNT PAID', '₹${fmt.format(amountPaid)}', curY,
        valueColor: const Color(0xFF4ADE80));
    curY += rowH;
    drawRow(
      'BALANCE DUE',
      balance > 0 ? '₹${fmt.format(balance)}' : 'Settled',
      curY,
      valueColor: const Color(0xFFFBBF24),
    );
    curY += rowH;

    curY += 14;
    drawDiv(curY);
    curY += 14;

    // ════════════════════════════════════════════════════════════════════════
    // ACCOUNT DETAILS SECTION
    // ════════════════════════════════════════════════════════════════════════
    drawPara('ACCOUNT DETAILS', innerLeft, curY + 12,
        fontSize: 13,
        color: const Color(0xFFF1F2F5),
        bold: true,
        maxWidth: innerW);
    curY += sectionH;

    drawRow('ACCOUNT NAME', widget.partyName, curY);
    curY += rowH;
    drawRow('CATEGORY', 'Party Ledger', curY);

    // ── Render to PNG ──────────────────────────────────────────────────────
    final picture  = recorder.endRecording();
    final uiImage  = await picture.toImage((cW * scale).toInt(), (cH * scale).toInt());
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null || !mounted) return;
    final bytes = byteData.buffer.asUint8List();

    final safeName = widget.partyName
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(' ', '_');

    if (kIsWeb) {
      await Share.shareXFiles(
        [XFile.fromData(bytes,
            name: '${safeName}_receipt.png', mimeType: 'image/png')],
        subject: '${widget.partyName} — Payment Receipt',
      );
    } else {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/${safeName}_receipt.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '${widget.partyName} — Payment Receipt',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yy');
    final ob      = _party?.openingBalance ?? 0.0;
    final closingBalance = ob + _totalBilled - _totalAllReceived;
    final filteredBills = _searchQuery.isEmpty
        ? _bills
        : _bills.where((b) {
            final q = _searchQuery;
            return b.billNumber.toLowerCase().contains(q) ||
                dateFmt.format(b.billDate).toLowerCase().contains(q) ||
                dateFmt.format(b.billCreatedAt).toLowerCase().contains(q) ||
                fmt.format(b.billTotal).contains(q) ||
                b.billTotal.toStringAsFixed(0).contains(q);
          }).toList();
    final recent  = _searchQuery.isEmpty
        ? filteredBills.take(_kPage).toList()
        : filteredBills;
    final hasMore = _searchQuery.isEmpty && _bills.length > _kPage;

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [

          // ── Hero header ─────────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeroDelegate(
              partyName:    widget.partyName,
              onShare:      _bills.isNotEmpty ? _showShareOptions : null,
              onSearch:     _showSearchSheet,
              hasBills:     _bills.isNotEmpty,
              searchActive: _searchQuery.isNotEmpty,
            ),
          ),

          // ── Stats ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: _T.bg,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: _ThreeStats(
  billed:         ob + _totalBilled,
  received:       _totalAllReceived,
  closingBalance: closingBalance,
  fmt:            fmt,
  onBilledTap:   _bills.isNotEmpty ? _showBillsDetail : null,
  onReceivedTap: _payments.isNotEmpty ? _showReceivedDetail : null,
),
            ),
          ),

          SliverToBoxAdapter(
            child: Container(height: 1, color: _T.line),
          ),

          // ── OB row ───────────────────────────────────────────────────────
          if (ob > 0)
            SliverToBoxAdapter(
              child: _OBRow(
                ob:       ob,
                obPaid:   _obPaid,
                fmt:      fmt,
                onDelete: _deleteOB,
              ),
            ),

          // ── Bills section header ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(
              label: 'BILLS',
              count: filteredBills.length,
              trailing: hasMore
                  ? GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          _route(AllBillsScreen(
                            partyName: widget.partyName,
                            bills:    _bills,
                            received: _perBillMap,
                          )),
                        );
                      },
                      child: const Text('View All',
                          style: TextStyle(
                              color: _T.accent2,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    )
                  : null,
            ),
          ),

          // ── Bill rows ────────────────────────────────────────────────────
          filteredBills.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _EmptyBills(),
                  ),
                )
              : SliverList.builder(
                  itemCount: recent.length + (hasMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == recent.length) {
                      return _ViewAllTile(
                        count: _bills.length,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            ctx,
                            _route(AllBillsScreen(
                              partyName: widget.partyName,
                              bills:    _bills,
                              received: _perBillMap,
                            )),
                          );
                        },
                      );
                    }
                    final bill = recent[i];
                    final rec  = _recForBill(bill);
                    final rem  =
                        (bill.billTotal - rec).clamp(0.0, double.infinity);
                    return RepaintBoundary(
                      child: _BillRow(
                        bill:      bill,
                        received:  rec,
                        remaining: rem,
                        fmt:       fmt,
                        dateFmt:   dateFmt,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            ctx,
                            _route(BillDetailScreen(
                                bill: bill, billCount: _bills.length)),
                          );
                        },
                        onEdit:   () => _editBill(bill),
                        onDelete: () => _deleteBill(bill),
                      ),
                    );
                  },
                ),

          // ── Party info card ───────────────────────────────────────────────
          if (_party != null)
            SliverToBoxAdapter(
              child: _PartyInfoBlock(party: _party!),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero header delegate
// ─────────────────────────────────────────────────────────────────────────────

class _HeroDelegate extends SliverPersistentHeaderDelegate {
  final String        partyName;
  final VoidCallback? onShare;
  final VoidCallback? onSearch;
  final bool          hasBills;
  final bool          searchActive;
  const _HeroDelegate({
    required this.partyName,
    this.onShare,
    this.onSearch,
    this.hasBills = false,
    this.searchActive = false,
  });

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 180;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final collapsed = progress > 0.7;

    return Stack(
      children: [
        // Clean solid background — no dot painter, no glow
        Container(color: _T.bg),


        // Collapsed: flat bar with name
        if (collapsed)
          Positioned.fill(
            child: Container(
              color: _T.bg,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: _T.text2, size: 17),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  IconButton(
                    icon: Icon(
                      searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      color: searchActive ? _T.accent2 : _T.muted2,
                      size: 20,
                    ),
                    onPressed: onSearch,
                    tooltip: searchActive ? 'Clear search' : 'Search',
                  ),
                  Expanded(
                    child: Text(
                      partyName,
                      style: const TextStyle(
                        color: _T.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (hasBills && onShare != null)
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded,
                          color: _T.muted2, size: 18),
                      onPressed: onShare,
                      tooltip: 'Share',
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          )
        else
          // Expanded: full hero
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button + action icons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_rounded,
                                color: _T.text2, size: 17),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          IconButton(
                            icon: Icon(
                              searchActive
                                  ? Icons.search_off_rounded
                                  : Icons.search_rounded,
                              color: searchActive ? _T.accent2 : _T.muted2,
                              size: 20,
                            ),
                            onPressed: onSearch,
                            tooltip: searchActive ? 'Clear search' : 'Search',
                          ),
                        ],
                      ),
                      if (hasBills && onShare != null)
                        IconButton(
                          icon: const Icon(Icons.ios_share_rounded,
                              color: _T.muted2, size: 18),
                          onPressed: onShare,
                          tooltip: 'Share',
                        ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Big square initial
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              color: _partyColor(partyName)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: _partyColor(partyName)
                                    .withValues(alpha: 0.28),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                partyName.isNotEmpty
                                    ? partyName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: _partyColor(partyName),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  partyName,
                                  style: const TextStyle(
                                    color: _T.text,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Bottom line
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(height: 1, color: _T.line),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _HeroDelegate old) =>
      old.partyName != partyName ||
      old.searchActive != searchActive ||
      old.onSearch != onSearch;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bill Row — ledger style with left status stripe
// ─────────────────────────────────────────────────────────────────────────────

class _BillRow extends StatelessWidget {
  final SaleBillEntity bill;
  final double         received;
  final double         remaining;
  final NumberFormat   fmt;
  final DateFormat     dateFmt;
  final VoidCallback   onTap;
  final VoidCallback?  onEdit;
  final VoidCallback?  onDelete;

  const _BillRow({
    required this.bill,
    required this.received,
    required this.remaining,
    required this.fmt,
    required this.dateFmt,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  @override
  Widget build(BuildContext context) {
    final settled = remaining <= 0;
    final partial = received > 0 && remaining > 0;
    final Color statusColor =
        settled ? _T.green : (partial ? _T.amber : _T.red);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _T.line2),
          ),
          child: IntrinsicHeight(
            child: Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    // Status stripe
    Container(
      width: 3,
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.8),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
      ),
    ),

    // Content
    Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
                        // Bill no + date
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                bill.billNumber,
                                style: const TextStyle(
                                  color: _T.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateFmt.format(bill.billDate),
                                style: const TextStyle(
                                    color: _T.muted2, fontSize: 11),
                              ),
                            ],
                          ),
                        ),

                        // Amount + status pill
                        // Amount + status pill
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₹${fmt.format(bill.billTotal)}',
                              style: const TextStyle(
                                color: _T.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: statusColor.withValues(alpha: 0.25)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Text(
                                settled
                                    ? '✓ Settled'
                                    : '₹${fmt.format(remaining)} due',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Menu / chevron
                        if (onEdit != null || onDelete != null)
                          _BillMenu(onEdit: onEdit, onDelete: onDelete)
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(Icons.chevron_right_rounded,
                                color: _T.muted.withValues(alpha: 0.3), size: 16),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bill 3-dot menu (Edit + Delete)
// ─────────────────────────────────────────────────────────────────────────────

class _BillMenu extends StatelessWidget {
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _BillMenu({this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: '', 
        icon: Icon(Icons.more_vert_rounded,
            color: _T.muted.withValues(alpha: 0.5), size: 18),
        iconSize: 18,
        color: _T.panel,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _T.line2),
        ),
        onSelected: (v) {
          if (v == 'edit' && onEdit != null) onEdit!();
          if (v == 'delete' && onDelete != null) onDelete!();
        },
        itemBuilder: (_) => [
          if (onEdit != null)
            _menuItem('edit', Icons.edit_rounded, 'Edit Bill', _T.accent2),
          if (onDelete != null)
            _menuItem('delete', Icons.delete_outline_rounded,
                'Delete Bill', _T.red),
        ],
      );

  PopupMenuItem<String> _menuItem(
          String value, IconData icon, String label, Color color) =>
      PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Edit Bill Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EditBillSheet extends ConsumerStatefulWidget {
  final SaleBillEntity bill;
  final String         cashbookId;
  const _EditBillSheet({required this.bill, required this.cashbookId});

  @override
  ConsumerState<_EditBillSheet> createState() => _EditBillSheetState();
}

class _EditBillSheetState extends ConsumerState<_EditBillSheet> {
  late final _formKey    = GlobalKey<FormState>();
  late final _billNoCtrl = TextEditingController(text: widget.bill.billNumber);
  late final _totalCtrl  =
      TextEditingController(text: _fmtAmt(widget.bill.billTotal));
  late final _noteCtrl   =
      TextEditingController(text: widget.bill.billNote ?? '');
  late DateTime _date    = widget.bill.billDate;
  bool _saving           = false;

  // Bill number uniqueness
  String? _billNoError;
  Timer?  _billNoDebounce;

  static String _fmtAmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _billNoCtrl.addListener(_onBillNoChanged);
  }

  void _onBillNoChanged() {
    _billNoDebounce?.cancel();
    final value = _billNoCtrl.text.trim();
    if (value.isEmpty || value == widget.bill.billNumber) {
      if (mounted && _billNoError != null) setState(() => _billNoError = null);
      return;
    }
    _billNoDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkBillNoUnique(value),
    );
  }

  Future<void> _checkBillNoUnique(String billNo) async {
    if (billNo == widget.bill.billNumber) {
      if (mounted && _billNoError != null) setState(() => _billNoError = null);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(widget.cashbookId)
          .collection('sale_bills')
          .where('billNumber', isEqualTo: billNo)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        _billNoError =
            snap.docs.isNotEmpty ? 'Bill number already exists' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _billNoError = null);
    }
  }

  @override
  void dispose() {
    _billNoDebounce?.cancel();
    _billNoCtrl.removeListener(_onBillNoChanged);
    _billNoCtrl.dispose();
    _totalCtrl.dispose();
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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _T.accent,
            onPrimary: Colors.white,
            surface: Color(0xFF1E1F22),
            onSurface: _T.text,
          ),
          dialogTheme:
              const DialogThemeData(backgroundColor: Color(0xFF1A1B1E)),
        ),
        child: child!,
      ),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_billNoError != null) return;
    setState(() => _saving = true);
    try {
      await ref.read(saleBillActionsProvider.notifier).editBill(
            cashbookId: widget.cashbookId,
            billId:     widget.bill.saleBillId,
            billNumber: _billNoCtrl.text.trim(),
            billTotal:  double.parse(_totalCtrl.text.trim()),
            billDate:   _date,
            billNote:   _noteCtrl.text.trim().isEmpty
                ? null
                : _noteCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop();
        _snack(context, 'Bill updated', ok: true);
      }
    } catch (e) {
      if (mounted) _snack(context, 'Failed: $e', ok: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom  = MediaQuery.of(context).viewInsets.bottom;
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      decoration: BoxDecoration(
        color: _T.panel,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: _T.line2),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 28 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 32, height: 3,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _T.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _T.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _T.accent.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        color: _T.accent2, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EDIT BILL',
                            style: TextStyle(
                                color: _T.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5)),
                        Text(widget.bill.partyName,
                            style: const TextStyle(
                                color: _T.muted2, fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _SheetField(
                controller: _billNoCtrl,
                label: 'Bill Number',
                icon: Icons.tag_rounded,
                errorText: _billNoError,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              _SheetField(
                controller: _totalCtrl,
                label: 'Bill Total (₹)',
                icon: Icons.currency_rupee_rounded,
                keyboard:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null)
                    return 'Invalid amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Date picker
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: _T.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _T.line2),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: _T.muted, size: 14),
                    const SizedBox(width: 10),
                    Text(dateFmt.format(_date),
                        style: const TextStyle(
                            color: _T.text, fontSize: 13)),
                    const Spacer(),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _T.muted, size: 16),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              _SheetField(
                controller: _noteCtrl,
                label: 'Note (optional)',
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        _T.accent.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('SAVE CHANGES',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController    controller;
  final String                   label;
  final IconData?                icon;
  final TextInputType?           keyboard;
  final FormFieldValidator<String>? validator;
  final int                      maxLines;
  final String?                  errorText;

  const _SheetField({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboard,
    this.validator,
    this.maxLines = 1,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        style: const TextStyle(color: _T.text, fontSize: 13),
        keyboardType: keyboard,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _T.muted, fontSize: 12),
          prefixIcon: icon != null
              ? Icon(icon, color: _T.muted, size: 15)
              : null,
          errorText: errorText,
          filled: true,
          fillColor: _T.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _T.line2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _T.accent2, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _T.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _T.red, width: 1.5),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Three-column stats
// ─────────────────────────────────────────────────────────────────────────────

class _ThreeStats extends StatelessWidget {
  final double       billed;
  final double       received;
  final double       closingBalance;
  final NumberFormat fmt;

  final VoidCallback? onBilledTap;
  final VoidCallback? onReceivedTap;

  const _ThreeStats({
    required this.billed,
    required this.received,
    required this.closingBalance,
    required this.fmt,
    this.onBilledTap,
    this.onReceivedTap,
  });

  @override
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _T.line2),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _StatBlock(
                    label: 'TOTAL AMOUNT',
                    value: '₹${fmt.format(billed)}',
                    color: _T.text2,
                    onTap: onBilledTap)),
              Container(width: 1, color: _T.line2),
              Expanded(
                child: _StatBlock(
                    label: 'RECEIVED',
                    value: '₹${fmt.format(received)}',
                    color: received > 0 ? _T.green : _T.muted2,
                    onTap: onReceivedTap)),
              Container(width: 1, color: _T.line2),
              Expanded(
                child: _StatBlock(
                    label: 'CLOSING BAL.',
                    value: closingBalance > 0 ? '₹${fmt.format(closingBalance)}' : '—',
                    color: closingBalance > 0 ? _T.darkOrange : _T.muted)),
            ],
          ),
        ),
      );
}

class _StatBlock extends StatelessWidget {
  final String       label;
  final String       value;
  final Color        color;
  final VoidCallback? onTap;
  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: _T.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4)),
                  if (onTap != null) ...[const SizedBox(width: 3),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _T.muted, size: 10)],
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full-width progress bar
// ─────────────────────────────────────────────────────────────────────────────

class _FullWidthProgress extends StatelessWidget {
  final double pct;
  final double due;
  const _FullWidthProgress({required this.pct, required this.due});

  @override
  Widget build(BuildContext context) {
    final settled = due <= 0;
    final color   = settled ? _T.green : _T.accent2;
    return Column(
      children: [
        Stack(
          children: [
            Container(height: 3, color: _T.line),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.4)],
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                settled ? '✓  Fully settled' : '${(pct * 100).toStringAsFixed(0)}% received',
                style: TextStyle(
                    color: settled ? _T.green : _T.muted2,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
              if (!settled)
                Text(
                  '${((1 - pct) * 100).toStringAsFixed(0)}% remaining',
                  style:
                      const TextStyle(color: _T.muted, fontSize: 10),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  OB row
// ─────────────────────────────────────────────────────────────────────────────

class _OBRow extends StatelessWidget {
  final double       ob;
  final double       obPaid;
  final NumberFormat fmt;
  final VoidCallback onDelete;
  const _OBRow(
      {required this.ob, required this.obPaid, required this.fmt, required this.onDelete});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  color: _T.accent.withValues(alpha: 0.45),
                ),
                Expanded(
                  child: Container(
                    color: _T.bg,
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: _T.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                                color: _T.accent.withValues(alpha: 0.2)),
                          ),
                          child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: _T.accent2, size: 13),
                        ),
                        const SizedBox(width: 12),
                        const Text('Opening Balance',
                            style: TextStyle(
                                color: _T.text2, fontSize: 13)),
                        const Spacer(),
                        Text('₹${fmt.format(ob)}',
                            style: const TextStyle(
                                color: Color(0xFF7BA8C4),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.more_vert_rounded,
                              color: _T.muted.withValues(alpha: 0.5),
                              size: 18),
                          iconSize: 18,
                          color: _T.panel,
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: _T.line2),
                          ),
                          onSelected: (v) {
                            if (v == 'delete') onDelete();
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem<String>(
                              value: 'delete',
                              height: 42,
                              child: Row(children: [
                                const Icon(Icons.delete_outline_rounded,
                                    color: _T.red, size: 15),
                                const SizedBox(width: 10),
                                const Text('Clear Balance',
                                    style: TextStyle(
                                        color: _T.red,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (obPaid > 0)
            Container(
              color: _T.bg,
              padding: const EdgeInsets.fromLTRB(62, 6, 16, 12),
              child: obPaid >= ob
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Color(0xFF4ADE80), size: 13),
                        SizedBox(width: 6),
                        Text(
                          'Opening Balance Cleared',
                          style: TextStyle(
                              color: Color(0xFF4ADE80),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2),
                        ),
                      ],
                    )
                                    : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${fmt.format(obPaid)} paid',
                          style: const TextStyle(
                              color: Color(0xFF7BA8C4),
                              fontSize: 15,
                              fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '₹${fmt.format((ob - obPaid).clamp(0.0, double.infinity))} remaining',
                          style: const TextStyle(
                              color: Color(0xFF4A5568),
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
            ),
          Container(height: 1, color: _T.line),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String    label;
  final int       count;
  final Widget?   trailing;
  const _SectionHeader({
    required this.label,
    required this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: _T.bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Text(
              count > 0 ? '$label  ($count)' : label,
              style: const TextStyle(
                color: _T.muted2,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party info block
// ─────────────────────────────────────────────────────────────────────────────

class _PartyInfoBlock extends StatelessWidget {
  final PartyEntity party;
  const _PartyInfoBlock({required this.party});

  @override
  Widget build(BuildContext context) {
    final hasPlace = (party.place ?? '').isNotEmpty;
    final hasDesc  = (party.description ?? '').isNotEmpty;
    if (!hasPlace && !hasDesc) return const SizedBox.shrink();

    return Container(
      color: _T.bg,
      child: Column(
        children: [
          const _SectionHeader(label: 'PARTY INFO', count: 0),
          if (hasPlace)
            _InfoLine(
                icon: Icons.location_on_rounded,
                label: 'Location',
                value: party.place!),
          if (hasDesc)
            _InfoLine(
                icon: Icons.notes_rounded,
                label: 'Note',
                value: party.description!),
          Container(height: 1, color: _T.line),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _InfoLine(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _T.muted, size: 14),
                const SizedBox(width: 10),
                Text('$label  ',
                    style: const TextStyle(
                        color: _T.muted, fontSize: 12)),
                Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          color: _T.text2, fontSize: 12)),
                ),
              ],
            ),
          ),
          Container(
              height: 1,
              color: _T.line,
              margin: const EdgeInsets.symmetric(horizontal: 20)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  View-all tile
// ─────────────────────────────────────────────────────────────────────────────

class _ViewAllTile extends StatelessWidget {
  final int          count;
  final VoidCallback onTap;
  const _ViewAllTile({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              color: _T.bg,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('View all $count bills',
                      style: const TextStyle(
                          color: _T.accent2,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded,
                      color: _T.accent2, size: 13),
                ],
              ),
            ),
          ),
          Container(height: 1, color: _T.line),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty bills placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyBills extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _T.line2),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined, color: _T.muted, size: 28),
            SizedBox(height: 10),
            Text('No bills yet',
                style: TextStyle(
                    color: _T.text2,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            SizedBox(height: 4),
            Text('Bills added for this client will appear here.',
                style: TextStyle(color: _T.muted2, fontSize: 11)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bills Detail Sheet — shown when TOTAL AMOUNT is tapped
// ─────────────────────────────────────────────────────────────────────────────

class _BillsDetailSheet extends StatelessWidget {
  final String               partyName;
  final List<SaleBillEntity> bills;
  final double               ob;
  const _BillsDetailSheet({
    required this.partyName,
    required this.bills,
    this.ob = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yyyy');
    final sorted  = List<SaleBillEntity>.from(bills)
      ..sort((a, b) => b.billDate.compareTo(a.billDate));
    final hasOB   = ob > 0;
    final total   = bills.fold(0.0, (s, b) => s + b.billTotal) + ob;
    final count   = bills.length + (hasOB ? 1 : 0);
    final maxH    = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: _T.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 14, bottom: 16),
            decoration: BoxDecoration(
              color: _T.line2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded,
                    color: _T.accent2, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL BILLS',
                          style: TextStyle(
                              color: _T.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4)),
                      Text(partyName,
                          style: const TextStyle(
                              color: _T.muted2, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${fmt.format(total)}',
                        style: const TextStyle(
                            color: _T.text2,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4)),
                    Text('$count items',
                        style: const TextStyle(
                            color: _T.muted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: _T.line2),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              itemCount: count,
              separatorBuilder: (_, __) =>
                  Container(height: 1, color: _T.line),
              itemBuilder: (_, i) {
                // First row = Opening Balance (if any)
                if (i == 0 && hasOB) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: _T.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _T.line2),
                          ),
                          child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: _T.accent2, size: 13),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Opening Balance',
                                  style: TextStyle(
                                      color: _T.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              SizedBox(height: 2),
                              Text('Carry-forward balance',
                                  style: TextStyle(
                                      color: _T.muted2, fontSize: 11)),
                            ],
                          ),
                        ),
                        Text('₹${fmt.format(ob)}',
                            style: const TextStyle(
                                color: _T.text2,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                      ],
                    ),
                  );
                }
                // Remaining rows = bills
                final b = sorted[hasOB ? i - 1 : i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: _T.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _T.line2),
                        ),
                        child: const Icon(Icons.receipt_outlined,
                            color: _T.accent2, size: 13),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.billNumber,
                                style: const TextStyle(
                                    color: _T.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(dateFmt.format(b.billDate),
                                style: const TextStyle(
                                    color: _T.muted2, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text('₹${fmt.format(b.billTotal)}',
                          style: const TextStyle(
                              color: _T.text2,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Received Detail Sheet — shown when RECEIVED is tapped
// ─────────────────────────────────────────────────────────────────────────────

class _ReceivedDetailSheet extends StatefulWidget {
  final String               partyName;
  final List<_PaymentRecord> payments;
  final List<SaleBillEntity> bills;
  const _ReceivedDetailSheet({
    required this.partyName,
    required this.payments,
    required this.bills,
  });

  @override
  State<_ReceivedDetailSheet> createState() => _ReceivedDetailSheetState();
}

class _ReceivedDetailSheetState extends State<_ReceivedDetailSheet> {
  bool _showNonSplitted = false;

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yyyy  hh:mm a');
    final billMap = {for (final b in widget.bills) b.saleBillId: b.billNumber};
    final total   = widget.payments.fold(0.0, (s, p) => s + p.amount);
    final maxH    = MediaQuery.of(context).size.height * 0.75;

    final splitted = List<_PaymentRecord>.from(widget.payments)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final grouped = _groupPayments(widget.payments);

    final itemCount  = _showNonSplitted ? grouped.length : splitted.length;
    final countLabel = _showNonSplitted
        ? '${grouped.length} payment${grouped.length != 1 ? "s" : ""}'
        : '${splitted.length} entr${splitted.length != 1 ? "ies" : "y"}';

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: _T.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 14, bottom: 16),
            decoration: BoxDecoration(
              color: _T.line2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.payments_rounded,
                    color: _T.green, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PAYMENTS RECEIVED',
                          style: TextStyle(
                              color: _T.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4)),
                      Text(widget.partyName,
                          style: const TextStyle(
                              color: _T.muted2, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${fmt.format(total)}',
                        style: const TextStyle(
                            color: _T.green,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4)),
                    Text(countLabel,
                        style: const TextStyle(
                            color: _T.muted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showNonSplitted = false);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: !_showNonSplitted
                          ? _T.accent.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: !_showNonSplitted
                            ? _T.accent2.withValues(alpha: 0.45)
                            : _T.line2,
                      ),
                    ),
                    child: Text(
                      'Splitted',
                      style: TextStyle(
                        color: !_showNonSplitted ? _T.text : _T.muted2,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showNonSplitted = true);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _showNonSplitted
                          ? _T.green.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _showNonSplitted
                            ? _T.green.withValues(alpha: 0.35)
                            : _T.line2,
                      ),
                    ),
                    child: Text(
                      'Non-splitted',
                      style: TextStyle(
                        color: _showNonSplitted ? _T.green : _T.muted2,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _T.line2),
          if (itemCount == 0)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No payments recorded',
                  style: TextStyle(color: _T.muted2, fontSize: 13)),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                itemCount: itemCount,
                separatorBuilder: (_, __) =>
                    Container(height: 1, color: _T.line),
                itemBuilder: (_, i) {
                  if (_showNonSplitted) {
                    final gp = grouped[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: _T.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _T.green.withValues(alpha: 0.18)),
                            ),
                            child: const Icon(Icons.arrow_downward_rounded,
                                color: _T.green, size: 13),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              dateFmt.format(gp.createdAt),
                              style: const TextStyle(
                                  color: _T.muted2, fontSize: 11),
                            ),
                          ),
                          Text('₹${fmt.format(gp.amount)}',
                              style: const TextStyle(
                                  color: _T.green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3)),
                        ],
                      ),
                    );
                  } else {
                    final p      = splitted[i];
                    final billNo = p.linkedBillId != null
                        ? (billMap[p.linkedBillId] ?? p.linkedBillId!)
                        : 'Opening Balance';
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: _T.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _T.green.withValues(alpha: 0.18)),
                            ),
                            child: const Icon(Icons.arrow_downward_rounded,
                                color: _T.green, size: 13),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(billNo,
                                    style: const TextStyle(
                                        color: _T.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(dateFmt.format(p.createdAt),
                                    style: const TextStyle(
                                        color: _T.muted2, fontSize: 11)),
                              ],
                            ),
                          ),
                          Text('₹${fmt.format(p.amount)}',
                              style: const TextStyle(
                                  color: _T.green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3)),
                        ],
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareOptionsSheet extends StatelessWidget {
  final VoidCallback onPdf;
  final VoidCallback onImage;
  const _ShareOptionsSheet({required this.onPdf, required this.onImage});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _T.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32, height: 3,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: _T.line2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Share Statement',
            style: TextStyle(
                color: _T.text, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose how to share this party\'s information',
            style: TextStyle(color: _T.muted2, fontSize: 11),
          ),
          const SizedBox(height: 20),
          _ShareOptionTile(
            icon: Icons.picture_as_pdf_rounded,
            label: 'Share as PDF',
            subtitle: 'Full party statement with all bills',
            color: _T.red,
            onTap: () {
              Navigator.of(context).pop();
              onPdf();
            },
          ),
          const SizedBox(height: 10),
          _ShareOptionTile(
            icon: Icons.image_rounded,
            label: 'Share as Image',
            subtitle: 'Payment receipt for a specific transaction',
            color: _T.green,
            onTap: () {
              Navigator.of(context).pop();
              onImage();
            },
          ),
        ],
      ),
    );
  }
}

class _ShareOptionTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       subtitle;
  final Color        color;
  final VoidCallback onTap;
  const _ShareOptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _T.line2),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: _T.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: _T.muted2, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: _T.muted, size: 18),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Transaction Picker Sheet — select which payment to generate a receipt for
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionPickerSheet extends StatelessWidget {
  final List<_GroupedPayment>          grouped;
  final void Function(_GroupedPayment) onSelect;

  const _TransactionPickerSheet({
    required this.grouped,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yyyy  hh:mm a');
    final maxH    = MediaQuery.of(context).size.height * 0.78;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: _T.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 14, bottom: 16),
            decoration: BoxDecoration(
              color: _T.line2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _T.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _T.green.withValues(alpha: 0.22)),
                  ),
                  child: const Icon(Icons.receipt_rounded,
                      color: _T.green, size: 15),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SELECT PAYMENT',
                          style: TextStyle(
                              color: _T.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4)),
                      Text(
                          '${grouped.length} payment${grouped.length != 1 ? "s" : ""}',
                          style: const TextStyle(
                              color: _T.muted2, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Select a payment to generate a receipt for',
              style: TextStyle(color: _T.muted2, fontSize: 11),
            ),
          ),
          Container(height: 1, color: _T.line2),
          if (grouped.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No payment entries found',
                  style: TextStyle(color: _T.muted2, fontSize: 13)),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
                physics: const BouncingScrollPhysics(),
                itemCount: grouped.length,
                separatorBuilder: (_, __) =>
                    Container(height: 1, color: _T.line),
                itemBuilder: (_, i) {
                  final gp = grouped[i];
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelect(gp);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _T.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _T.green.withValues(alpha: 0.18)),
                            ),
                            child: const Icon(Icons.arrow_downward_rounded,
                                color: _T.green, size: 14),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              dateFmt.format(gp.createdAt),
                              style: const TextStyle(
                                  color: _T.muted2, fontSize: 11),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('₹${fmt.format(gp.amount)}',
                                  style: const TextStyle(
                                      color: _T.green,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3)),
                              const SizedBox(height: 2),
                              const Text('Tap to select',
                                  style: TextStyle(
                                      color: _T.muted, fontSize: 10)),
                            ],
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
    );
  }
}

class _BackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _BackBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: _T.text2, size: 17),
        onPressed: onTap,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dot painter — subtle grid for hero background
// ─────────────────────────────────────────────────────────────────────────────

class _DotPainter extends CustomPainter {
  final double opacity;
  const _DotPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    final p = Paint()
      ..color = _T.line2.withValues(alpha: opacity)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.8, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Route helper — smooth fade + subtle slide
// ─────────────────────────────────────────────────────────────────────────────

Route<void> _route(Widget page) => PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: Tween(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: const Interval(0, 0.5))),
          child: SlideTransition(
            position:
                Tween(begin: const Offset(0.04, 0.0), end: Offset.zero)
                    .animate(c),
            child: child,
          ),
        );
      },
    );

// ─────────────────────────────────────────────────────────────────────────────
//  Party color (deterministic from name) — muted grey-toned palette
// ─────────────────────────────────────────────────────────────────────────────

Color _partyColor(String name) {
  const colors = [
    Color(0xFF7C9CBF),
    Color(0xFF7BA89A),
    Color(0xFFB097C0),
    Color(0xFFBFA97C),
    Color(0xFF8EA8C0),
    Color(0xFFA09EC0),
  ];
  return name.isNotEmpty
      ? colors[name.codeUnitAt(0) % colors.length]
      : colors[0];
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bill Search Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _BillSearchSheet extends StatefulWidget {
  final String               initialQuery;
  final ValueChanged<String> onChanged;
  const _BillSearchSheet({
    required this.initialQuery,
    required this.onChanged,
  });

  @override
  State<_BillSearchSheet> createState() => _BillSearchSheetState();
}

class _BillSearchSheetState extends State<_BillSearchSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: _T.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Search Bills',
              style: TextStyle(
                  color: _T.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Filter by bill number, date (e.g. 12 Jun 25), or amount',
            style: TextStyle(color: _T.muted2, fontSize: 11),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => Navigator.pop(context),
            style: const TextStyle(color: _T.text, fontSize: 14),
            cursorColor: _T.accent2,
            decoration: InputDecoration(
              hintText: 'Type to filter bills...',
              hintStyle: const TextStyle(color: _T.muted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: _T.muted2, size: 18),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _ctrl.clear();
                        widget.onChanged('');
                        setState(() {});
                      },
                      child: const Icon(Icons.close_rounded,
                          color: _T.muted2, size: 16),
                    )
                  : null,
              filled: true,
              fillColor: _T.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _T.line2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _T.line2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _T.accent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            onChanged: (v) {
              widget.onChanged(v);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> _confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  bool danger = false,
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _T.line2),
        ),
        title: Text(title,
            style: const TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 15)),
        content: Text(body,
            style: const TextStyle(
                color: _T.muted2, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: _T.muted2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm,
                style: TextStyle(
                    color: danger ? _T.red : _T.accent2,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

void _snack(BuildContext context, String msg, {required bool ok}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg,
        style: const TextStyle(color: Colors.white, fontSize: 13)),
    backgroundColor:
        ok ? _T.green.withValues(alpha: 0.9) : _T.red.withValues(alpha: 0.9),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  ));
}