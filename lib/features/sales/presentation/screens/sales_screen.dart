import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/sale_bill_entity.dart';
import '../providers/sale_bill_provider.dart';
import 'manage_opening_balance_screen.dart';
import 'party_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens — minimalist grey aesthetic
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
}

// ─────────────────────────────────────────────────────────────────────────────
//  Background animation — slow-drifting translucent orbs
// ─────────────────────────────────────────────────────────────────────────────

class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  static const _orbs = [
    (0.15, 0.20, 240.0, 0.028),
    (0.85, 0.55, 280.0, 0.022),
    (0.50, 0.85, 200.0, 0.025),
    (0.70, 0.12, 180.0, 0.018),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _orbs.length; i++) {
      final (bx, by, r, alpha) = _orbs[i];
      final dx = math.sin(t * 0.45 + i * 1.3) * 28.0;
      final dy = math.cos(t * 0.35 + i * 1.0) * 22.0;
      final center = Offset(size.width * bx + dx, size.height * by + dy);

      for (var ring = 0; ring < 4; ring++) {
        final ringAlpha = (alpha * (1.0 - ring * 0.22)).clamp(0.0, 1.0);
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF64748B).withValues(alpha: ringAlpha);
        canvas.drawCircle(center, r + ring * 45.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t;
}

class _AnimatedBackground extends StatefulWidget {
  final Widget child;
  const _AnimatedBackground({required this.child});

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _BgPainter(_ctrl.value * 2 * math.pi),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Route helper
// ─────────────────────────────────────────────────────────────────────────────

Route _slideRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, a, __) => page,
      transitionsBuilder: (_, anim, __, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0)
              .animate(CurvedAnimation(
                  parent: anim, curve: const Interval(0.0, 0.5))),
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0.04, 0.0), end: Offset.zero)
                    .animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
    );

// ─────────────────────────────────────────────────────────────────────────────
//  Sales Screen
// ─────────────────────────────────────────────────────────────────────────────

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _addBill(BuildContext ctx) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddBillSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(filteredSaleBillsProvider);

    return _AnimatedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [

            // ── Flat App Bar ─────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              floating: false,
              backgroundColor: _T.bg.withValues(alpha: 0.92),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 56,
              leading: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back_ios_rounded,
                    color: _T.text2, size: 18),
              ),
              title: const Text(
                'SALES',
                style: TextStyle(
                  color: _T.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                ),
              ),
              actions: [
                _IconAction(
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: () => Navigator.of(context).push(
                    _slideRoute(const ManageOpeningBalanceScreen()),
                  ),
                ),
                const SizedBox(width: 4),
                _IconAction(
                  icon: Icons.add_rounded,
                  filled: true,
                  onTap: () => _addBill(context),
                ),
                const SizedBox(width: 16),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: _T.line),
              ),
            ),

            // ── Hero outstanding strip ───────────────────────────────────────
            SliverToBoxAdapter(
              child: billsAsync.maybeWhen(
                data: (bills) => _HeroStrip(bills: bills),
                orElse: () => const SizedBox.shrink(),
              ),
            ),

            // ── Search ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: _SearchRow(
                  controller: _searchCtrl,
                  onChanged: (q) =>
                      ref.read(saleBillSearchProvider.notifier).update(q),
                  onAddBill: () => _addBill(context),
                ),
              ),
            ),

            // ── Divider ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(height: 1, color: _T.line,
                  margin: const EdgeInsets.only(top: 10)),
            ),

            // ── Content ─────────────────────────────────────────────────────
            billsAsync.when(
              data: (bills) {
                if (bills.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      hasSearch: _searchCtrl.text.isNotEmpty,
                      onAdd: () => _addBill(context),
                    ),
                  );
                }

                final grouped = <String, List<SaleBillEntity>>{};
                final displayName = <String, String>{};
                for (final b in bills) {
                  final key = b.partyName.trim().toLowerCase();
                  if (!grouped.containsKey(key)) {
                    grouped[key] = [];
                    displayName[key] = b.partyName;
                  }
                  grouped[key]!.add(b);
                }
                final names = grouped.keys.toList();

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                  sliver: SliverList.builder(
                    itemCount: names.length,
                    itemBuilder: (ctx, i) => RepaintBoundary(
                      child: _PartyRow(
                        key:       ValueKey(names[i]),
                        partyName: displayName[names[i]]!,
                        bills:     grouped[names[i]]!,
                        onTap: () => Navigator.of(context).push(
                          _slideRoute(PartyDetailScreen(partyName: displayName[names[i]]!)),
                        ),
                      )
                      .animate(delay: Duration(milliseconds: 30 + i * 30))
                      .fadeIn(duration: 200.ms)
                      .slideX(begin: -0.02, end: 0, curve: Curves.easeOutCubic),
                    ),
                  ),
                );
              },
              loading: () => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(
                          color: _T.accent2,
                          strokeWidth: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Loading…',
                          style: TextStyle(color: _T.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: _T.red, fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: _NewBillFAB(onTap: () => _addBill(context)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero strip — total outstanding as the headline number
// ─────────────────────────────────────────────────────────────────────────────

class _HeroStrip extends StatelessWidget {
  final List<SaleBillEntity> bills;
  const _HeroStrip({required this.bills});

  @override
  Widget build(BuildContext context) {
    final fmt        = NumberFormat('#,##,##0');
    final totalBill  = bills.fold<double>(0, (s, b) => s + b.billTotal);
    final parties    = bills.map((b) => b.partyName).toSet().length;
    final settled    = bills.where((b) => b.billStatus == 'settled').length;
    final pending    = bills.length - settled;

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Big label
          Row(
            children: [
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: 8, top: 1),
                decoration: BoxDecoration(
                  color: pending > 0 ? _T.amber : _T.green,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                pending > 0 ? 'OUTSTANDING' : 'ALL SETTLED',
                style: TextStyle(
                  color: pending > 0 ? _T.amber : _T.green,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Big number
          Text(
            '₹${fmt.format(totalBill)}',
            style: const TextStyle(
              color: _T.text,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              height: 1,
            ),
          ),
          const SizedBox(height: 16),

          // Small stats in a row
          Row(
            children: [
              _MiniStat(value: '$parties',
                  label: parties == 1 ? 'client' : 'clients',
                  color: _T.accent2),
              _StatDot(),
              _MiniStat(value: '${bills.length}',
                  label: bills.length == 1 ? 'bill' : 'bills',
                  color: _T.text2),
              _StatDot(),
              _MiniStat(value: '$pending',
                  label: 'pending',
                  color: pending > 0 ? _T.amber : _T.muted2),
              _StatDot(),
              _MiniStat(value: '$settled',
                  label: 'settled',
                  color: settled > 0 ? _T.green : _T.muted2),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color  color;
  const _MiniStat({
      required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  color: _T.muted2, fontSize: 11)),
        ],
      );
}

class _StatDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(
          width: 3, height: 3,
          decoration: BoxDecoration(
              color: _T.line2, shape: BoxShape.circle),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Search row
// ─────────────────────────────────────────────────────────────────────────────

class _SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>  onChanged;
  final VoidCallback          onAddBill;
  const _SearchRow({
    required this.controller,
    required this.onChanged,
    required this.onAddBill,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: _T.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _T.line2),
                ),
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: const TextStyle(
                      color: _T.text, fontSize: 13, height: 1),
                  decoration: InputDecoration(
                    hintText: 'Search party or bill…',
                    hintStyle:
                        const TextStyle(color: _T.muted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: _T.muted, size: 16),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: _T.muted, size: 14),
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party row — ledger-style with left status stripe
// ─────────────────────────────────────────────────────────────────────────────

class _PartyRow extends ConsumerStatefulWidget {
  final String               partyName;
  final List<SaleBillEntity> bills;
  final VoidCallback         onTap;

  const _PartyRow({
    super.key,
    required this.partyName,
    required this.bills,
    required this.onTap,
  });

  @override
  ConsumerState<_PartyRow> createState() => _PartyRowState();
}

class _PartyRowState extends ConsumerState<_PartyRow> {
  StreamSubscription<QuerySnapshot>?    _txSub;
  StreamSubscription<DocumentSnapshot>? _partySub;
  ProviderSubscription<String?>?        _idSub;
  String?                               _cashbookId;

  Map<String, double> _receivedByBill = {};
  double _ob    = 0.0;
  String _place = '';

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
            _txSub?.cancel();
            _partySub?.cancel();
            _start(next);
          }
        },
        fireImmediately: true,
      );
    });
  }

  void _start(String cashbookId) {
    if (!mounted) return;
    final partyLow = widget.partyName.trim().toLowerCase();
    final billIds  = widget.bills.map((b) => b.saleBillId).toSet();

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
        final desc     = (raw['description'] as String? ?? '').toLowerCase();
        final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;

        if (linkedId != null &&
            linkedId.isNotEmpty &&
            billIds.contains(linkedId)) {
          map[linkedId] = (map[linkedId] ?? 0.0) + amount;
        } else if ((linkedId == null || linkedId.isEmpty) &&
            desc.contains(partyLow)) {
          map['_desc'] = (map['_desc'] ?? 0.0) + amount;
        }
      }
      if (mounted) setState(() => _receivedByBill = map);
    });

    _partySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .doc(partyLow)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists) {
        final d = doc.data() as Map<String, dynamic>;
        setState(() {
          _ob    = (d['openingBalance'] as num?)?.toDouble() ?? 0.0;
          _place = d['place'] as String? ?? '';
        });
      } else {
        setState(() { _ob = 0.0; _place = ''; });
      }
    });
  }

  @override
  void dispose() {
    _idSub?.close();
    _txSub?.cancel();
    _partySub?.cancel();
    super.dispose();
  }

  double get _totalReceived {
    if (widget.bills.length == 1) {
      return _receivedByBill.values.fold(0.0, (s, v) => s + v);
    }
    return _receivedByBill.entries
        .where((e) => e.key != '_desc')
        .fold(0.0, (s, e) => s + e.value);
  }

  @override
  Widget build(BuildContext context) {
    final fmt        = NumberFormat('#,##,##0.##');
    final totalBill  = widget.bills.fold<double>(0.0, (s, b) => s + b.billTotal);
    final outstanding = (totalBill - _totalReceived).clamp(0.0, double.infinity);
    final settled    = outstanding <= 0 && totalBill > 0;
    final partial    = !settled && _totalReceived > 0;

    final Color stripe = settled ? _T.green : (partial ? _T.amber : _T.red);
    final Color amtColor = settled ? _T.green : _T.amber;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left status stripe ───────────────────────────────────
                Container(
                  width: 4,
                  color: stripe.withValues(alpha: 0.8),
                ),

                // ── Content ───────────────────────────────────────────────
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    color: Colors.transparent,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [

                        // Square avatar
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: _partyColor(widget.partyName)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _partyColor(widget.partyName)
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              widget.partyName.isNotEmpty
                                  ? widget.partyName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: _partyColor(widget.partyName),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Name + sub info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.partyName,
                                style: const TextStyle(
                                  color: _T.text,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '${widget.bills.length} bill${widget.bills.length == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                        color: _T.muted2, fontSize: 11),
                                  ),
                                  if (_place.isNotEmpty) ...[
                                    const Text(' · ',
                                        style: TextStyle(
                                            color: _T.muted, fontSize: 11)),
                                    Flexible(
                                      child: Text(
                                        _place,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: _T.muted2, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                  if (_ob > 0) ...[
                                    const Text(' · ',
                                        style: TextStyle(
                                            color: _T.muted, fontSize: 11)),
                                    Text('OB ₹${_shortFmt(_ob)}',
                                        style: const TextStyle(
                                            color: Color(0xFF7BA8C4),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Amount + status on right
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (settled)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded,
                                      color: _T.green, size: 12),
                                  const SizedBox(width: 3),
                                  const Text('Settled',
                                      style: TextStyle(
                                          color: _T.green,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ],
                              )
                            else ...[
                              Text(
                                '₹${fmt.format(outstanding)}',
                                style: TextStyle(
                                  color: amtColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                partial ? 'partial' : 'pending',
                                style: TextStyle(
                                  color: amtColor.withValues(alpha: 0.65),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded,
                            color: _T.muted.withValues(alpha: 0.4),
                            size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _T.line),
        ],
      ),
    );
  }
}

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
//  Add Bill Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddBillSheet extends ConsumerStatefulWidget {
  const _AddBillSheet();

  @override
  ConsumerState<_AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends ConsumerState<_AddBillSheet> {
  final _formKey    = GlobalKey<FormState>();
  final _partyCtrl  = TextEditingController();
  final _billNoCtrl = TextEditingController();
  final _totalCtrl  = TextEditingController();
  final _noteCtrl   = TextEditingController();
  DateTime _date    = DateTime.now();
  bool _submitting  = false;

  Timer?  _obTimer;
  double? _fetchedOB;
  bool    _obFetching = false;

  @override
  void initState() {
    super.initState();
    _partyCtrl.addListener(_onPartyChanged);
  }

  void _onPartyChanged() {
    _obTimer?.cancel();
    final name = _partyCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) setState(() { _fetchedOB = null; _obFetching = false; });
      return;
    }
    if (mounted) setState(() => _obFetching = true);
    _obTimer = Timer(const Duration(milliseconds: 600), () => _fetchOB(name));
  }

  Future<void> _fetchOB(String name) async {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || !mounted) {
      if (mounted) setState(() => _obFetching = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('parties')
          .doc(name.toLowerCase())
          .get();
      if (!mounted) return;
      setState(() {
        _fetchedOB = doc.exists
            ? (doc.data()?['openingBalance'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        _obFetching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _obFetching = false);
    }
  }

  @override
  void dispose() {
    _obTimer?.cancel();
    _partyCtrl.removeListener(_onPartyChanged);
    _partyCtrl.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(saleBillActionsProvider.notifier).addBill(
            cashbookId:    cashbookId,
            partyName:     _partyCtrl.text.trim(),
            billNumber:    _billNoCtrl.text.trim(),
            billTotal:     double.parse(_totalCtrl.text.trim()),
            billDate:      _date,
            billNote:      _noteCtrl.text.trim().isEmpty
                ? null
                : _noteCtrl.text.trim(),
            createdBy:     user.uid,
            createdByName: user.displayName ?? '',
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: _T.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom  = MediaQuery.of(context).viewInsets.bottom;
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      decoration: BoxDecoration(
        color: _T.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                    child: const Icon(Icons.receipt_long_rounded,
                        color: _T.accent2, size: 17),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NEW SALE BILL',
                          style: TextStyle(
                              color: _T.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5)),
                      Text('Fill in the details below',
                          style: TextStyle(
                              color: _T.muted2, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _Field(
                controller: _partyCtrl,
                label: 'Party / Client Name',
                hint: 'ABC Traders',
                icon: Icons.business_rounded,
                capitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),

              // OB hint
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _obFetching
                    ? Padding(
                        key: const ValueKey('loading'),
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _T.accent2),
                          ),
                          const SizedBox(width: 8),
                          const Text('Checking opening balance…',
                              style: TextStyle(
                                  color: _T.muted, fontSize: 11)),
                        ]),
                      )
                    : _fetchedOB != null && _fetchedOB! > 0
                        ? Padding(
                            key: const ValueKey('ob'),
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(children: [
                              const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: Color(0xFF7BA8C4), size: 13),
                              const SizedBox(width: 6),
                              Text(
                                'Opening balance: ₹${_shortFmt(_fetchedOB!)}',
                                style: const TextStyle(
                                    color: Color(0xFF7BA8C4), fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ]),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
              ),
              const SizedBox(height: 12),

              _Field(
                controller: _billNoCtrl,
                label: 'Bill Number',
                hint: 'INV-001',
                icon: Icons.tag_rounded,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              _Field(
                controller: _totalCtrl,
                label: 'Bill Total (₹)',
                hint: '0.00',
                icon: Icons.currency_rupee_rounded,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) return 'Invalid';
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

              _Field(
                controller: _noteCtrl,
                label: 'Note (optional)',
                hint: 'Any details…',
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        _T.accent.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('SAVE BILL',
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

// ─────────────────────────────────────────────────────────────────────────────
//  Shared input field
// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController    controller;
  final String                   label;
  final String?                  hint;
  final IconData?                icon;
  final TextInputType?           keyboard;
  final FormFieldValidator<String>? validator;
  final int                      maxLines;
  final TextCapitalization       capitalization;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboard,
    this.validator,
    this.maxLines = 1,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        style: const TextStyle(color: _T.text, fontSize: 13),
        keyboardType: keyboard,
        maxLines: maxLines,
        textCapitalization: capitalization,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: _T.muted, fontSize: 12),
          hintStyle: const TextStyle(color: _T.muted, fontSize: 12),
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
//  FAB
// ─────────────────────────────────────────────────────────────────────────────

class _NewBillFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _NewBillFAB({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _T.accent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: _T.accent.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('New Bill',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.3)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Icon action (app bar button)
// ─────────────────────────────────────────────────────────────────────────────

class _IconAction extends StatelessWidget {
  final IconData     icon;
  final bool         filled;
  final VoidCallback onTap;
  const _IconAction({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: filled
                ? _T.accent
                : _T.line2.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(7),
            border: filled ? null : Border.all(color: _T.line2),
          ),
          child: Icon(icon,
              color: filled ? Colors.white : _T.text2, size: 17),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool         hasSearch;
  final VoidCallback onAdd;
  const _EmptyState({required this.hasSearch, required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: _T.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _T.line2),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : Icons.receipt_long_outlined,
                  color: _T.muted,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                hasSearch ? 'No results found' : 'No bills yet',
                style: const TextStyle(
                    color: _T.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? 'Try a different search term'
                    : 'Tap New Bill to create your first sale',
                style: const TextStyle(
                    color: _T.muted2, fontSize: 12, height: 1.5),
                textAlign: TextAlign.center,
              ),
              if (!hasSearch) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 11),
                    decoration: BoxDecoration(
                      color: _T.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _T.accent.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            color: _T.accent2, size: 15),
                        SizedBox(width: 6),
                        Text('Create First Bill',
                            style: TextStyle(
                                color: _T.accent2,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _shortFmt(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
  return v == v.truncateToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);
}
