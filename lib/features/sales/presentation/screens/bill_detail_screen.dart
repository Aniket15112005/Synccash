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
//  Bill Detail Screen
// ─────────────────────────────────────────────────────────────────────────────

class BillDetailScreen extends ConsumerStatefulWidget {
  final SaleBillEntity bill;
  const BillDetailScreen({super.key, required this.bill});

  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen>
    with TickerProviderStateMixin {
  // ── Streams ──────────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _txSub;
  ProviderSubscription<String?>?     _idSub;
  String?                            _cashbookId;

  List<_TxItem> _transactions = [];
  bool          _loading      = true;

  // ── Animation controllers ─────────────────────────────────────────────────
  late final AnimationController _progressCtrl;
  late final Animation<double>   _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _progressAnim = CurvedAnimation(
      parent: _progressCtrl,
      curve: Curves.easeOutCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _idSub = ref.listenManual<String?>(
        currentCashbookIdProvider,
        (prev, next) {
          if (next != null && next.isNotEmpty && next != _cashbookId) {
            _cashbookId = next;
            _txSub?.cancel();
            _startStream(next);
          }
        },
        fireImmediately: true,
      );
    });
  }

  // ── FIX: Stream now matches by linkedSaleBillId (exact) first, then falls
  //         back to description match for any legacy income entries.
  //         No .orderBy() → no composite index required → no stuck loader.
  void _startStream(String cashbookId) {
    if (!mounted) return;
    final billId = widget.bill.saleBillId;
    final partyQ = widget.bill.partyName.trim().toLowerCase();

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final items = snap.docs
            .where((doc) {
              // FIX: doc['field'] throws Bad state when field is absent.
              // Use doc.data() which returns a plain Map — safe null for missing keys.
              final raw      = doc.data();
              final linkedId = raw['linkedSaleBillId'] as String?;
              if (linkedId != null && linkedId.isNotEmpty) {
                return linkedId == billId;
              }
              // Fallback: legacy entries matched by party name in description
              return (raw['description'] as String? ?? '')
                  .toLowerCase()
                  .contains(partyQ);
            })
            .map((doc) {
              final raw = doc.data();
              return _TxItem(
                id:          raw['transactionId'] as String? ?? doc.id,
                amount:      (raw['amount'] as num?)?.toDouble() ?? 0.0,
                createdAt:   (raw['createdAt'] as Timestamp?)?.toDate() ??
                             DateTime.now(),
                description: raw['description'] as String? ?? '',
                isLinked:    (raw['linkedSaleBillId'] as String? ?? '').isNotEmpty,
              );
            })
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        setState(() {
          _transactions = items;
          _loading      = false;
        });

        // Animate progress ring whenever data updates
        final received = items.fold<double>(0.0, (s, t) => s + t.amount);
        final pct = widget.bill.billTotal > 0
            ? (received / widget.bill.billTotal).clamp(0.0, 1.0)
            : 0.0;
        _progressCtrl.animateTo(pct);
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  @override
  void dispose() {
    _idSub?.close();
    _txSub?.cancel();
    _progressCtrl.dispose();
    super.dispose();
  }

  void _recordPayment() {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPaymentSheet(
        bill:        widget.bill,
        cashbookId:  _cashbookId!,
        remaining:   _remaining,
      ),
    );
  }

  double get _received =>
      _transactions.fold<double>(0.0, (s, t) => s + t.amount);
  double get _remaining =>
      (widget.bill.billTotal - _received).clamp(0.0, double.infinity);
  bool get _settled => _remaining <= 0;

  @override
  Widget build(BuildContext context) {
    final fmt      = NumberFormat('#,##,##0.00');
    final dateFmt  = DateFormat('dd MMM yyyy');
    final timeFmt  = DateFormat('dd MMM  ·  hh:mm a');
    final received = _received;
    final remaining = _remaining;
    final settled  = _settled;
    final partial  = received > 0 && remaining > 0;
    final Color remColor =
        settled ? _T.green : (partial ? _T.amber : _T.red);
    final pct = widget.bill.billTotal > 0
        ? (received / widget.bill.billTotal).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [

          // ── Immersive App Bar ──────────────────────────────────────────────
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
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: _StatusBadge(settled: settled, partial: partial)),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 90, 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.bill.partyName,
                      style: const TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.2)),
                  Text(widget.bill.billNumber,
                      style: const TextStyle(
                          color: _T.muted, fontSize: 10)),
                ],
              ),
              background: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF0D1122), Color(0xFF080A0E)],
                      ),
                    ),
                  ),
                  // Ambient glow behind progress ring
                  Positioned(
                    right: -20, top: -20,
                    child: Container(
                      width: 180, height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            remColor.withValues(alpha: 0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Progress ring — top right
                  Positioned(
                    right: 20, top: 28,
                    child: AnimatedBuilder(
                      animation: _progressAnim,
                      builder: (_, __) => _ProgressRing(
                        progress: _loading ? 0.0 : _progressAnim.value,
                        color: remColor,
                        size: 76,
                        label: _loading
                            ? '—'
                            : '${(_progressAnim.value * 100).toStringAsFixed(0)}%',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Financial summary card ────────────────────────────────
                _FinancialCard(
                  bill:       widget.bill,
                  received:   received,
                  remaining:  remaining,
                  settled:    settled,
                  loading:    _loading,
                  remColor:   remColor,
                  fmt:        fmt,
                  pct:        pct,
                ).animate().fadeIn(duration: 300.ms).slideY(
                    begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 12),

                // ── Bill info card ────────────────────────────────────────
                _BillInfoCard(
                  bill:    widget.bill,
                  dateFmt: dateFmt,
                ).animate().fadeIn(delay: 60.ms, duration: 300.ms).slideY(
                    begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 22),

                // ── Payments section label ────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 3, height: 14,
                      decoration: BoxDecoration(
                        color: _T.green,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('PAYMENT HISTORY',
                        style: TextStyle(
                            color: _T.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    const Spacer(),
                    if (!_loading)
                      Text(
                        '${_transactions.length} record${_transactions.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: _T.muted, fontSize: 10),
                      ),
                  ],
                ).animate().fadeIn(delay: 100.ms, duration: 280.ms),
                const SizedBox(height: 10),

                // ── Payment list ──────────────────────────────────────────
                if (_loading)
                  _PaymentLoadingShimmer()
                else if (_transactions.isEmpty)
                  _EmptyPayments().animate().fadeIn(delay: 120.ms)
                else
                  ...List.generate(_transactions.length, (i) {
                    final tx = _transactions[i];
                    return _PaymentTile(
                      tx:     tx,
                      timeFmt: timeFmt,
                      fmt:    fmt,
                      index:  i,
                    );
                  }),

                // ── Action buttons ────────────────────────────────────────
                if (!settled) ...[
                  const SizedBox(height: 28),
                  _ActionButtons(
                    bill:          widget.bill,
                    cashbookId:    _cashbookId,
                    remaining:     remaining,
                    onRecordPayment: _recordPayment,
                  ).animate().fadeIn(
                    delay: Duration(
                        milliseconds: 140 + _transactions.length * 40),
                    duration: 300.ms,
                  ),
                ] else ...[
                  const SizedBox(height: 24),
                  _SettledBanner()
                      .animate()
                      .fadeIn(delay: 120.ms, duration: 400.ms)
                      .scale(begin: const Offset(0.96, 0.96)),
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
//  Progress Ring
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressRing extends StatelessWidget {
  final double progress;
  final Color  color;
  final double size;
  final String label;
  const _ProgressRing({
    required this.progress,
    required this.color,
    required this.size,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size, height: size,
        child: CustomPaint(
          painter: _RingPainter(progress: progress, color: color),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.17)),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color  color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = (size.width - 8) / 2;
    final strokeW = 5.0;

    // Track
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // Arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Financial summary card
// ─────────────────────────────────────────────────────────────────────────────

class _FinancialCard extends StatelessWidget {
  final SaleBillEntity bill;
  final double         received;
  final double         remaining;
  final bool           settled;
  final bool           loading;
  final Color          remColor;
  final NumberFormat   fmt;
  final double         pct;

  const _FinancialCard({
    required this.bill,
    required this.received,
    required this.remaining,
    required this.settled,
    required this.loading,
    required this.remColor,
    required this.fmt,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              remColor.withValues(alpha: 0.04),
              const Color(0xFF0C1018),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: remColor.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: remColor.withValues(alpha: 0.04),
              blurRadius: 24, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            _SummaryRow(
              icon:       Icons.receipt_long_rounded,
              label:      'Bill Total',
              value:      '₹${fmt.format(bill.billTotal)}',
              valueColor: _T.text,
            ),
            const SizedBox(height: 10),
            _SummaryRow(
              icon:       Icons.arrow_downward_rounded,
              label:      'Received',
              value:      loading ? '—' : '₹${fmt.format(received)}',
              valueColor: _T.green,
            ),

            // Progress bar
            if (!loading) ...[
              const SizedBox(height: 14),
              _ProgressBar(pct: pct, color: remColor),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 16),

            Container(height: 1, color: _T.border.withValues(alpha: 0.5)),
            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Remaining',
                    style: TextStyle(
                        color: _T.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                if (loading)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: _T.accent),
                  )
                else
                  Text(
                    settled ? 'Fully Paid ✓' : '₹${fmt.format(remaining)}',
                    style: TextStyle(
                        color: remColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.3),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _ProgressBar extends StatelessWidget {
  final double pct;
  final Color  color;
  const _ProgressBar({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: _T.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% paid',
            style: TextStyle(
                color: _T.muted.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w500),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bill info card
// ─────────────────────────────────────────────────────────────────────────────

class _BillInfoCard extends StatelessWidget {
  final SaleBillEntity bill;
  final DateFormat     dateFmt;
  const _BillInfoCard({required this.bill, required this.dateFmt});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.border),
        ),
        child: Column(
          children: [
            _InfoRow(label: 'Party',    value: bill.partyName),
            _InfoRow(label: 'Bill No.', value: bill.billNumber),
            _InfoRow(label: 'Date',
                value: dateFmt.format(bill.billDate)),
            if ((bill.billNote ?? '').isNotEmpty)
              _InfoRow(label: 'Note', value: bill.billNote!),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Payment tile
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final _TxItem      tx;
  final DateFormat   timeFmt;
  final NumberFormat fmt;
  final int          index;
  const _PaymentTile({
    required this.tx,
    required this.timeFmt,
    required this.fmt,
    required this.index,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tx.isLinked
                ? _T.green.withValues(alpha: 0.15)
                : _T.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _T.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _T.green.withValues(alpha: 0.15)),
              ),
              child: const Icon(Icons.arrow_downward_rounded,
                  color: _T.green, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _T.text, fontSize: 12.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(timeFmt.format(tx.createdAt),
                          style: const TextStyle(
                              color: _T.muted, fontSize: 10)),
                      if (tx.isLinked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _T.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('linked',
                              style: TextStyle(
                                  color: _T.green,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Text('+ ₹${fmt.format(tx.amount)}',
                style: const TextStyle(
                    color: _T.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ],
        ),
      )
      .animate(delay: Duration(milliseconds: 60 + index * 45))
      .fadeIn(duration: 260.ms)
      .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentLoadingShimmer extends StatefulWidget {
  @override
  State<_PaymentLoadingShimmer> createState() => _PaymentLoadingShimmerState();
}

class _PaymentLoadingShimmerState extends State<_PaymentLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Column(
          children: List.generate(
            3,
            (i) => Container(
              margin: const EdgeInsets.only(bottom: 7),
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    _T.card,
                    Color.lerp(_T.card, _T.border, _anim.value)!,
                    _T.card,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty payments state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyPayments extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _T.border),
        ),
        child: Column(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _T.muted.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.payments_outlined,
                  color: _T.muted.withValues(alpha: 0.4), size: 22),
            ),
            const SizedBox(height: 12),
            const Text('No payments recorded yet',
                style: TextStyle(
                    color: _T.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Use "Record Payment" below to add one',
                style: TextStyle(color: _T.muted, fontSize: 11)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Settled banner
// ─────────────────────────────────────────────────────────────────────────────

class _SettledBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _T.green.withValues(alpha: 0.06),
              _T.green.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.green.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _T.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: _T.green, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bill Fully Settled',
                      style: TextStyle(
                          color: _T.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  SizedBox(height: 2),
                  Text('All payments have been received for this bill.',
                      style: TextStyle(
                          color: _T.muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action buttons — Record Payment + Mark Settled
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final SaleBillEntity bill;
  final String?        cashbookId;
  final double         remaining;
  final VoidCallback   onRecordPayment;

  const _ActionButtons({
    required this.bill,
    required this.cashbookId,
    required this.remaining,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(saleBillActionsProvider).isLoading;
    final enabled   = !isLoading && cashbookId != null;
    final fmt       = NumberFormat('#,##,##0.00');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Record Payment — primary CTA
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: enabled ? onRecordPayment : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _T.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _T.accent.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Record Payment',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 10),

        // Mark as Settled — secondary
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: enabled
                ? () => _confirmSettle(context, ref, fmt)
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: _T.green,
              side: BorderSide(
                  color: enabled
                      ? _T.green.withValues(alpha: 0.4)
                      : _T.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _T.green))
                : const Icon(Icons.check_circle_outline_rounded, size: 16),
            label: Text(
              remaining > 0
                  ? 'Settle (write off ₹${fmt.format(remaining)})'
                  : 'Mark as Settled',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmSettle(BuildContext ctx, WidgetRef ref, NumberFormat fmt) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Mark as Settled?',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (remaining > 0) ...[
              Text(
                '₹${fmt.format(remaining)} is still outstanding. '
                'This will record a final income entry of that amount and mark the bill as settled.',
                style: const TextStyle(
                    color: _T.muted, fontSize: 13, height: 1.5),
              ),
            ] else
              const Text(
                'This will mark the bill as fully settled.',
                style: TextStyle(color: _T.muted, fontSize: 13, height: 1.5),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: _T.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final user = FirebaseAuth.instance.currentUser;
              if (cashbookId == null || user == null) return;
              await ref
                  .read(saleBillActionsProvider.notifier)
                  .settleWithPayment(
                    cashbookId:      cashbookId!,
                    billId:          bill.saleBillId,
                    billNumber:      bill.billNumber,
                    partyName:       bill.partyName,
                    remaining:       remaining,
                    createdBy:       user.uid,
                    createdByName:   user.displayName ?? '',
                  );
            },
            child: const Text('Settle',
                style: TextStyle(
                    color: _T.green, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Record Payment sheet
//  Creates a real income transaction in the transactions collection with
//  linkedSaleBillId set so the bill detail can match it exactly.
// ─────────────────────────────────────────────────────────────────────────────

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  final SaleBillEntity bill;
  final String         cashbookId;
  final double         remaining;

  const _RecordPaymentSheet({
    required this.bill,
    required this.cashbookId,
    required this.remaining,
  });

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState
    extends ConsumerState<_RecordPaymentSheet> {
  final _formKey   = GlobalKey<FormState>();
  final _amtCtrl   = TextEditingController();
  final _noteCtrl  = TextEditingController();
  bool  _submitting = false;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Not signed in. Please restart the app.', success: false);
      return;
    }
    setState(() => _submitting = true);
    try {
      final amount = double.parse(_amtCtrl.text.trim());
      await ref.read(saleBillActionsProvider.notifier).recordPayment(
            cashbookId:     widget.cashbookId,
            billId:         widget.bill.saleBillId,
            billNumber:     widget.bill.billNumber,
            partyName:      widget.bill.partyName,
            amount:         amount,
            createdBy:      user.uid,
            createdByName:  user.displayName ?? '',
            note:           _noteCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Payment of ₹${_fmtNum(amount)} recorded', success: true),
        );
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save: $e', success: false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(_snackBar(msg, success: success));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final fmt    = NumberFormat('#,##,##0.00');

    return Container(
      decoration: const BoxDecoration(
        color: _T.card2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: _T.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _T.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _T.green.withValues(alpha: 0.18)),
                    ),
                    child: const Icon(Icons.payments_rounded,
                        color: _T.green, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Record Payment',
                            style: TextStyle(
                                color: _T.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                        Text(
                          '${widget.bill.partyName} · ${widget.bill.billNumber}',
                          style: const TextStyle(
                              color: _T.muted, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Outstanding amount info
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _T.amber.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _T.amber.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: _T.amber, size: 14),
                    const SizedBox(width: 8),
                    const Text('Outstanding: ',
                        style: TextStyle(
                            color: _T.muted, fontSize: 12)),
                    Text('₹${fmt.format(widget.remaining)}',
                        style: const TextStyle(
                            color: _T.amber,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _amtCtrl.text =
                          widget.remaining == widget.remaining.truncateToDouble()
                              ? widget.remaining.toStringAsFixed(0)
                              : widget.remaining.toStringAsFixed(2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _T.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Use full',
                            style: TextStyle(
                                color: _T.amber,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Amount field
              TextFormField(
                controller: _amtCtrl,
                autofocus: true,
                style: const TextStyle(
                    color: _T.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _fieldDec(
                    label: 'Payment Amount (₹)',
                    hint: '0',
                    icon: Icons.currency_rupee_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Amount is required';
                  }
                  final d = double.tryParse(v.trim());
                  if (d == null || d <= 0) {
                    return 'Enter a valid amount greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Note field
              TextFormField(
                controller: _noteCtrl,
                style: const TextStyle(color: _T.text, fontSize: 14),
                maxLines: 2,
                decoration: _fieldDec(
                    label: 'Note (optional)',
                    hint:
                        'e.g. Cheque payment, cash received…',
                    icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 22),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        _T.green.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Save Payment',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'This will appear in your income transactions on the dashboard',
                  style: TextStyle(color: _T.muted, fontSize: 10),
                  textAlign: TextAlign.center,
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
//  Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TxItem {
  final String   id;
  final double   amount;
  final DateTime createdAt;
  final String   description;
  final bool     isLinked;
  const _TxItem({
    required this.id,
    required this.amount,
    required this.createdAt,
    required this.description,
    required this.isLinked,
  });
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    valueColor;
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: _T.muted, size: 14),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(color: _T.muted, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ],
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(
                      color: _T.muted, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _T.text, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final bool settled;
  final bool partial;
  const _StatusBadge({required this.settled, required this.partial});
  @override
  Widget build(BuildContext context) {
    final Color c = settled ? _T.green : (partial ? _T.amber : _T.red);
    final String label =
        settled ? 'SETTLED' : (partial ? 'PARTIAL' : 'PENDING');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Text(label,
          style: TextStyle(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

SnackBar _snackBar(String msg, {required bool success}) => SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: success
          ? _T.green.withValues(alpha: 0.9)
          : _T.red.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );

InputDecoration _fieldDec(
        {required String label, String? hint, IconData? icon}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _T.muted, fontSize: 13),
      hintStyle: const TextStyle(color: _T.muted, fontSize: 13),
      prefixIcon: icon != null
          ? Icon(icon, color: _T.muted, size: 17)
          : null,
      filled: true,
      fillColor: _T.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _T.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _T.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _T.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _T.red, width: 1.5),
      ),
    );
