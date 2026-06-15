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
import 'bill_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg     = Color(0xFF080A0E);
  static const card   = Color(0xFF0F1318);
  static const card2  = Color(0xFF141921);
  static const border = Color(0xFF1C2130);
  static const muted  = Color(0xFF4A5568);
  static const accent = Color(0xFF6C7FE4);
  static const text   = Color(0xFFE8ECF4);
  static const green  = Color(0xFF38D68A);
  static const amber  = Color(0xFFF5A623);
  static const red    = Color(0xFFE85C5C);
}

// ─────────────────────────────────────────────────────────────────────────────
//  All Bills Screen
// ─────────────────────────────────────────────────────────────────────────────

class AllBillsScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy');
    final sorted  = List<SaleBillEntity>.from(bills)
      ..sort((a, b) => b.billCreatedAt.compareTo(a.billCreatedAt));

    return Scaffold(
      backgroundColor: _T.bg,
      appBar: AppBar(
        backgroundColor: _T.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: _T.text, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(partyName,
                style: const TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            Text('All Bills  (${bills.length})',
                style: const TextStyle(color: _T.muted, fontSize: 11)),
          ],
        ),
      ),
      body: sorted.isEmpty
          ? const Center(
              child: Text('No bills found.',
                  style: TextStyle(color: _T.muted, fontSize: 13)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final bill = sorted[i];
                final rec  = received[bill.saleBillId] ?? 0.0;
                final rem  = bill.billTotal - rec;
                final settled = rem <= 0;
                final partial = rec > 0 && rem > 0;
                final Color sc =
                    settled ? _T.green : (partial ? _T.amber : _T.red);
                final String sl = settled
                    ? 'Settled'
                    : '₹${fmt.format(rem)} due';

                return _BillTile(
                  bill: bill,
                  statusColor: sc,
                  statusLabel: sl,
                  fmt: fmt,
                  dateFmt: dateFmt,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(ctx)
                        .push(_slideRoute(BillDetailScreen(bill: bill)));
                  },
                );
              },
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
  ConsumerState<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends ConsumerState<PartyDetailScreen> {
  static const int _pageSize = 5;

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
      _idSub = ref.listenManual<String?>(
        currentCashbookIdProvider,
        (prev, next) {
          if (next != null && next.isNotEmpty && next != _cashbookId) {
            _cashbookId = next;
            _cancelStreams();
            _start(next);
          }
        },
        fireImmediately: true,
      );
    });
  }

  void _cancelStreams() {
    _billsSub?.cancel();
    _txSub?.cancel();
    _partySub?.cancel();
    _billsSub = null;
    _txSub    = null;
    _partySub = null;
  }

  void _start(String cashbookId) {
    if (!mounted) return;
    final partyName = widget.partyName.trim();
    final partyLow  = partyName.toLowerCase();

    // Bills stream
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

    // Transactions stream
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
        // FIX: doc['field'] throws Bad state when field absent; use data() map
        final raw      = doc.data();
        final linkedId = raw['linkedSaleBillId'] as String?;
        final desc     = (raw['description'] as String? ?? '').toLowerCase();
        final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        if (linkedId != null && linkedId.isNotEmpty) {
          map[linkedId] = (map[linkedId] ?? 0.0) + amount;
        } else if (desc.contains(partyLow)) {
          map['_unlinked'] = (map['_unlinked'] ?? 0.0) + amount;
        }
      }
      if (mounted) setState(() => _received = map);
    }, onError: (_) {});

    // Party document stream
    _partySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .doc(partyLow)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() =>
          _party = doc.exists ? PartyEntity.fromDoc(doc) : null);
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
    if (_bills.length == 1) return linked + (_received['_unlinked'] ?? 0.0);
    return linked;
  }

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy');
    final ob      = _party?.openingBalance ?? 0.0;

    final recent  = _bills.take(_pageSize).toList();
    final hasMore = _bills.length > _pageSize;

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [

          // ── Immersive app bar ──────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _T.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: _T.text, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
              title: Text(widget.partyName,
                  style: const TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 17)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0D1020),
                      Color(0xFF080A0E),
                    ],
                  ),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: 0.06,
                    child: Container(
                      width: 200, height: 200,
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          colors: [_T.accent, Colors.transparent],
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Party header card ──────────────────────────────────────
                _PartyHeaderCard(
                  partyName: widget.partyName,
                  party: _party,
                  ob: ob,
                  fmt: fmt,
                ),
                const SizedBox(height: 24),

                // ── Bills section label ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3, height: 14,
                          decoration: BoxDecoration(
                            color: _T.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'RECENT BILLS  (${_bills.length})',
                          style: const TextStyle(
                              color: _T.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2),
                        ),
                      ],
                    ),
                    if (hasMore)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).push(_slideRoute(
                            AllBillsScreen(
                              partyName: widget.partyName,
                              bills: _bills,
                              received: _received,
                            ),
                          ));
                        },
                        child: Row(
                          children: [
                            const Text('View All',
                                style: TextStyle(
                                    color: _T.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_forward_rounded,
                                color: _T.accent, size: 13),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Bills list ─────────────────────────────────────────────
                if (_bills.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    decoration: BoxDecoration(
                      color: _T.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _T.border),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            color: _T.border, size: 36),
                        const SizedBox(height: 10),
                        const Text('No bills yet for this client.',
                            style: TextStyle(
                                color: _T.muted, fontSize: 13)),
                      ],
                    ),
                  )
                else
                  ...recent.map((bill) {
                    final rec     = _recForBill(bill);
                    final rem     = bill.billTotal - rec;
                    final settled = rem <= 0;
                    final partial = rec > 0 && rem > 0;
                    final Color sc =
                        settled ? _T.green : (partial ? _T.amber : _T.red);
                    final String sl =
                        settled ? 'Settled' : '₹${fmt.format(rem)} due';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _BillTile(
                        bill: bill,
                        statusColor: sc,
                        statusLabel: sl,
                        fmt: fmt,
                        dateFmt: dateFmt,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).push(
                              _slideRoute(BillDetailScreen(bill: bill)));
                        },
                      ),
                    );
                  }),

                // ── View All button ────────────────────────────────────────
                if (hasMore) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).push(_slideRoute(
                        AllBillsScreen(
                          partyName: widget.partyName,
                          bills: _bills,
                          received: _received,
                        ),
                      ));
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _T.accent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _T.accent.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'View All ${_bills.length} Bills',
                            style: const TextStyle(
                                color: _T.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded,
                              color: _T.accent, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party header card
// ─────────────────────────────────────────────────────────────────────────────

class _PartyHeaderCard extends StatelessWidget {
  final String       partyName;
  final PartyEntity? party;
  final double       ob;
  final NumberFormat fmt;

  const _PartyHeaderCard({
    required this.partyName,
    required this.party,
    required this.ob,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101420), Color(0xFF0C1018)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _T.border),
        boxShadow: [
          BoxShadow(
            color: _T.accent.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CircleAvatar(name: partyName, size: 50),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(partyName,
                        style: const TextStyle(
                            color: _T.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            letterSpacing: -0.3)),
                    if ((party?.place ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.location_on_rounded,
                                color: _T.muted.withValues(alpha: 0.7),
                                size: 12),
                            const SizedBox(width: 3),
                            Text(party!.place,
                                style: TextStyle(
                                    color: _T.muted.withValues(alpha: 0.8),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          if ((party?.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(party!.description,
                style: TextStyle(
                    color: _T.muted.withValues(alpha: 0.75),
                    fontSize: 12,
                    height: 1.4)),
          ],

          const SizedBox(height: 16),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                _T.border,
                Colors.transparent,
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Opening balance
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _T.accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _T.accent.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _T.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: _T.accent,
                      size: 16),
                ),
                const SizedBox(width: 10),
                const Text('Opening Balance',
                    style: TextStyle(
                        color: _T.muted, fontSize: 13)),
                const Spacer(),
                Text('₹${fmt.format(ob)}',
                    style: const TextStyle(
                        color: _T.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared bill tile
// ─────────────────────────────────────────────────────────────────────────────

class _BillTile extends StatelessWidget {
  final SaleBillEntity bill;
  final Color          statusColor;
  final String         statusLabel;
  final NumberFormat   fmt;
  final DateFormat     dateFmt;
  final VoidCallback   onTap;

  const _BillTile({
    required this.bill,
    required this.statusColor,
    required this.statusLabel,
    required this.fmt,
    required this.dateFmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _T.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.15)),
                ),
                child: Icon(Icons.receipt_long_rounded,
                    color: statusColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bill.billNumber,
                        style: const TextStyle(
                            color: _T.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(dateFmt.format(bill.billDate),
                        style: const TextStyle(
                            color: _T.muted, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${fmt.format(bill.billTotal)}',
                      style: const TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  _Pill(label: statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: _T.muted.withValues(alpha: 0.3), size: 14),
            ],
          ),
        ),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Route _slideRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, a, __) => page,
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 280),
    );

class _CircleAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _CircleAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF4C6EF5),
      const Color(0xFF7950F2),
      const Color(0xFF1C7ED6),
      const Color(0xFF0CA678),
      const Color(0xFFE67700),
    ];
    final idx   = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    final color = colors[idx];
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.85),
            color.withValues(alpha: 0.45),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.38),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color  color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );
}
