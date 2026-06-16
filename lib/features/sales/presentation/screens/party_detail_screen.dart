import 'dart:async';
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
//  All Bills Screen
// ─────────────────────────────────────────────────────────────────────────────

class AllBillsScreen extends ConsumerWidget {
  final String               partyName;
  final List<SaleBillEntity> bills;
  final Map<String, double>  received;

  const AllBillsScreen({
    super.key,
    required this.partyName,
    required this.bills,
    required this.received,
  });

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
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
      if (context.mounted) _snack(context, 'Failed: $e', ok: false);
    }
  }

  void _edit(
    BuildContext context,
    WidgetRef ref,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yy');
    final sorted  = List<SaleBillEntity>.from(bills)
      ..sort((a, b) => b.billCreatedAt.compareTo(a.billCreatedAt));

    double totalBilled   = 0;
    double totalReceived = 0;
    for (final b in sorted) {
      totalBilled   += b.billTotal;
      totalReceived += received[b.saleBillId] ?? 0.0;
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
                Text(partyName,
                    style: const TextStyle(
                        color: _T.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2)),
                Text('${bills.length} bills',
                    style: const TextStyle(
                        color: _T.muted2, fontSize: 10)),
              ],
            ),
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
          sorted.isEmpty
              ? const SliverFillRemaining(
                  child: Center(
                    child: Text('No bills',
                        style: TextStyle(color: _T.muted2, fontSize: 13)),
                  ),
                )
              : SliverList.builder(
                  itemCount: sorted.length,
                  itemBuilder: (ctx, i) {
                    final bill = sorted[i];
                    final rec  = received[bill.saleBillId] ?? 0.0;
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
                                  bill: bill, billCount: bills.length)));
                        },
                        onEdit:   () => _edit(ctx, ref, bill, cashbookId),
                        onDelete: () => _delete(ctx, ref, bill, cashbookId),
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
  final String partyName;
  const PartyDetailScreen({super.key, required this.partyName});

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

  List<SaleBillEntity> _bills    = [];
  Map<String, double>  _received = {};
  PartyEntity?         _party;

  @override
  void initState() {
    super.initState();
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
        .where('partyName', isEqualTo: partyName)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((doc) {
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
      if (mounted) setState(() => _bills = list);
    }, onError: (_) {});

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final map = <String, double>{};
      for (final doc in snap.docs) {
        final raw      = doc.data();
        final linkedId = raw['linkedSaleBillId'] as String?;
        final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final desc     = (raw['description'] as String? ?? '').toLowerCase();
        if (linkedId != null && linkedId.isNotEmpty) {
          map[linkedId] = (map[linkedId] ?? 0.0) + amount;
        } else if (desc.contains(partyLow)) {
          map['_unlinked'] = (map['_unlinked'] ?? 0.0) + amount;
        }
      }
      if (mounted) setState(() => _received = map);
    }, onError: (_) {});

    _partySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .doc(partyLow)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(
          () => _party = doc.exists ? PartyEntity.fromDoc(doc) : null);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _idSub?.close();
    _cancelStreams();
    super.dispose();
  }

  double _recForBill(SaleBillEntity b) {
    final linked = _received[b.saleBillId] ?? 0.0;
    if (_bills.length == 1) {
      return linked + (_received['_unlinked'] ?? 0.0);
    }
    return linked;
  }

  double get _totalBilled   => _bills.fold(0.0, (s, b) => s + b.billTotal);
  double get _totalReceived => _bills.fold(0.0, (s, b) => s + _recForBill(b));
  // Always includes unlinked (OB / description-matched) payments — used for closing balance
  double get _totalAllReceived =>
      _bills.fold(0.0, (s, b) => s + (_received[b.saleBillId] ?? 0.0))
      + (_received['_unlinked'] ?? 0.0);
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

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yy');
    final ob      = _party?.openingBalance ?? 0.0;
    final closingBalance = ob + _totalBilled - _totalAllReceived;
    final recent  = _bills.take(_kPage).toList();
    final hasMore = _bills.length > _kPage;

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [

          // ── Hero header ─────────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeroDelegate(partyName: widget.partyName),
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
                obPaid:   _received['_unlinked'] ?? 0.0,
                fmt:      fmt,
                onDelete: _deleteOB,
              ),
            ),

          // ── Bills section header ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(
              label: 'BILLS',
              count: _bills.length,
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
          _bills.isEmpty
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
  final String partyName;
  const _HeroDelegate({required this.partyName});

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
                  Text(
                    partyName,
                    style: const TextStyle(
                      color: _T.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
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
                  // Back button
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: _T.text2, size: 17),
                    onPressed: () => Navigator.of(context).pop(),
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
      old.partyName != partyName;
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '₹${fmt.format(bill.billTotal)}',
                              style: const TextStyle(
                                color: _T.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: statusColor.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                settled
                                    ? '✓ Settled'
                                    : '₹${fmt.format(remaining)} due',
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
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

  static String _fmtAmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
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

  const _SheetField({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboard,
    this.validator,
    this.maxLines = 1,
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

  const _ThreeStats({
    required this.billed,
    required this.received,
    required this.closingBalance,
    required this.fmt,
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
                    color: _T.text2)),
              Container(width: 1, color: _T.line2),
              Expanded(
                child: _StatBlock(
                    label: 'RECEIVED',
                    value: '₹${fmt.format(received)}',
                    color: received > 0 ? _T.green : _T.muted2)),
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
  final String label;
  final String value;
  final Color  color;
  const _StatBlock(
      {required this.label, required this.value, required this.color});

  @override
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: _T.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4)),
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
//  Back button
// ─────────────────────────────────────────────────────────────────────────────

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