import 'dart:async';
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
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

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
  /// Number of bills this party has. When > 1 the description-match
  /// fallback is skipped so unlinked payments don't appear in every bill.
  final int billCount;
  const BillDetailScreen({
    super.key,
    required this.bill,
    this.billCount = 1,
  });

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 310), () {
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
    });
  }

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
              final raw      = doc.data();
              final linkedId = raw['linkedSaleBillId'] as String?;
              if (linkedId != null && linkedId.isNotEmpty) {
                return linkedId == billId;
              }
              // Only fall back to description match when this party has
              // exactly 1 bill; with multiple bills every bill would show
              // the same unlinked transactions, which is incorrect.
              if (widget.billCount > 1) return false;
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

  // ── Share ───────────────────────────────────────────────────────────────
  bool _isGeneratingShare = false;

  Future<void> _generateAndShare() async {
    if (_isGeneratingShare || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _isGeneratingShare = true);

    final overlayKey = GlobalKey();
    OverlayEntry? entry;
    try {
      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: -5000,
          top: 0,
          width: 420,
          child: Material(
            type: MaterialType.transparency,
            child: RepaintBoundary(
              key: overlayKey,
              child: _BillShareCard(
                bill:         widget.bill,
                received:     _received,
                remaining:    _remaining,
                settled:      _settled,
                transactions: List<_TxItem>.from(_transactions),
                generatedAt:  DateTime.now(),
              ),
            ),
          ),
        ),
      );
      if (!mounted) return;
      Overlay.of(context).insert(entry);
      await Future.delayed(const Duration(milliseconds: 150));

      final boundary = overlayKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');

      final image    = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');

      final bytes    = byteData.buffer.asUint8List();
      final safeName = widget.bill.billNumber
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      // XFile.fromData works on web (PWA) + mobile without filesystem access
      await Share.shareXFiles(
        [XFile.fromData(bytes,
            name: 'synccash_bill_$safeName.png',
            mimeType: 'image/png')],
        subject: '${widget.bill.partyName}  ·  ${widget.bill.billNumber}',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('Could not generate image: $e', success: false));
    } finally {
      entry?.remove();
      if (mounted) setState(() => _isGeneratingShare = false);
    }
  }

  void _showPaymentDetail(_TxItem tx) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaymentDetailSheet(
        tx:   tx,
        bill: widget.bill,
      ),
    );
  }

  // ── DELETE PAYMENT ENTRY ──────────────────────────────────────────────────
  Future<void> _deletePayment(_TxItem tx) async {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();

    final fmt = NumberFormat('#,##,##0.00');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Payment?',
          style: TextStyle(
              color: _T.text, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'Payment of ₹${fmt.format(tx.amount)} will be permanently deleted '
          'and the cashbook balance will be updated accordingly.',
          style: const TextStyle(
              color: _T.muted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: _T.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: _T.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final db          = FirebaseFirestore.instance;
      final cashbookRef = db.collection('cashbooks').doc(_cashbookId);
      final txRef       = cashbookRef.collection('transactions').doc(tx.id);

      await db.runTransaction((txn) async {
        final txSnap = await txn.get(txRef);
        if (!txSnap.exists) return;

        final data   = txSnap.data()!;
        final amount = (data['amount'] as num?)?.toDouble() ?? tx.amount;

        // Delete the transaction document
        txn.delete(txRef);

        // Reverse the effect on cashbook balance — income payments add to
        // balance/income, so deleting them subtracts from both.
        txn.update(cashbookRef, {
          'balance': FieldValue.increment(-amount),
          'income':  FieldValue.increment(-amount),
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Payment entry deleted', success: true),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Failed to delete: $e', success: false),
        );
      }
    }
  }

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
        settled ? _T.green : _T.amber;
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
            expandedHeight: 140,
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
              Center(child: _StatusBadge(settled: settled, partial: partial)),
              const SizedBox(width: 4),
              _BillMoreMenu(
                onShare:      _generateAndShare,
                isGenerating: _isGeneratingShare,
              ),
              const SizedBox(width: 8),
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
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0D1122), Color(0xFF080A0E)],
                  ),
                ),
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
                      tx:       tx,
                      timeFmt:  timeFmt,
                      fmt:      fmt,
                      index:    i,
                      onTap:    () => _showPaymentDetail(tx),
                      onDelete: () => _deletePayment(tx),
                    );
                  }),

                // ── Action buttons ────────────────────────────────────────
                if (!settled) ...[
                  const SizedBox(height: 28),
                  _ActionButtons(
                    bill:            widget.bill,
                    cashbookId:      _cashbookId,
                    remaining:       remaining,
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
//  Payment Detail Sheet  (shown when tapping a payment history entry)
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentDetailSheet extends StatelessWidget {
  final _TxItem        tx;
  final SaleBillEntity bill;

  const _PaymentDetailSheet({required this.tx, required this.bill});

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy  ·  hh:mm a');

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: _T.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Amount hero ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _T.green.withValues(alpha: 0.08),
                  _T.green.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _T.green.withValues(alpha: 0.18)),
            ),
            child: Column(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: _T.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _T.green.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.arrow_downward_rounded,
                      color: _T.green, size: 24),
                ),
                const SizedBox(height: 14),
                const Text('Payment Received',
                    style: TextStyle(
                        color: _T.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.3)),
                const SizedBox(height: 8),
                Text(
                  '₹${fmt.format(tx.amount)}',
                  style: const TextStyle(
                      color: _T.green,
                      fontWeight: FontWeight.w800,
                      fontSize: 34,
                      letterSpacing: -1),
                ),
                if (tx.isLinked) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _T.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _T.green.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_rounded,
                            color: _T.green, size: 12),
                        const SizedBox(width: 4),
                        const Text('Linked to bill',
                            style: TextStyle(
                                color: _T.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Details ──────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _T.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _T.border),
            ),
            child: Column(
              children: [
                _DetailRow(
                  icon:  Icons.calendar_today_rounded,
                  label: 'Date & Time',
                  value: dateFmt.format(tx.createdAt),
                ),
                _Divider(),
                _DetailRow(
                  icon:  Icons.receipt_long_rounded,
                  label: 'Bill No.',
                  value: bill.billNumber,
                ),
                _Divider(),
                _DetailRow(
                  icon:  Icons.business_rounded,
                  label: 'Party',
                  value: bill.partyName,
                ),
                if (tx.description.isNotEmpty) ...[
                  _Divider(),
                  _DetailRow(
                    icon:  Icons.notes_rounded,
                    label: 'Description',
                    value: tx.description,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Close button ─────────────────────────────────────────────────
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _T.muted,
                side: BorderSide(color: _T.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Close',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: _T.muted, size: 15),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(color: _T.muted, fontSize: 13)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: _T.border,
      );
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
//  Payment tile  (tappable — opens detail sheet; 3-dot — delete)
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final _TxItem      tx;
  final DateFormat   timeFmt;
  final NumberFormat fmt;
  final int          index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PaymentTile({
    required this.tx,
    required this.timeFmt,
    required this.fmt,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
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
                    Text(
                      tx.description.isNotEmpty
                          ? tx.description
                          : 'Payment received',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _T.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timeFmt.format(tx.createdAt),
                      style: TextStyle(
                          color: _T.muted.withValues(alpha: 0.8),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Amount column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${fmt.format(tx.amount)}',
                    style: const TextStyle(
                        color: _T.green,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.3),
                  ),
                  if (tx.isLinked) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_rounded,
                            color: _T.green.withValues(alpha: 0.6),
                            size: 10),
                        const SizedBox(width: 2),
                        Text('linked',
                            style: TextStyle(
                                color: _T.green.withValues(alpha: 0.6),
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              // 3-dot menu
              _PaymentPopupMenu(onDelete: onDelete),
            ],
          ),
        ),
      );
}

class _PaymentPopupMenu extends StatelessWidget {
  final VoidCallback onDelete;
  const _PaymentPopupMenu({required this.onDelete});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(
          Icons.more_vert_rounded,
          color: _T.muted.withValues(alpha: 0.55),
          size: 18,
        ),
        color: _T.card2,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _T.border)),
        onSelected: (v) {
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'delete',
            height: 44,
            child: Row(
              children: [
                const Icon(Icons.delete_outline_rounded,
                    color: _T.red, size: 16),
                const SizedBox(width: 10),
                const Text('Delete Entry',
                    style: TextStyle(
                        color: _T.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentLoadingShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            height: 64,
            decoration: BoxDecoration(
              color: _T.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _T.border),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty payments placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyPayments extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: const BoxDecoration(
                  color: _T.border, shape: BoxShape.circle),
              child: const Icon(Icons.payments_outlined,
                  color: _T.muted, size: 22),
            ),
            const SizedBox(height: 10),
            const Text('No payments recorded',
                style: TextStyle(
                    color: _T.text, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Use "Record Payment" below to add one.',
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
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _T.green.withValues(alpha: 0.08),
              _T.green.withValues(alpha: 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.green.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _T.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: _T.green, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bill Fully Settled',
                    style: TextStyle(
                        color: _T.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                SizedBox(height: 2),
                Text('All payments have been received.',
                    style: TextStyle(color: _T.muted, fontSize: 11)),
              ],
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action buttons (record payment / settle)
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
    final fmt       = NumberFormat('#,##,##0.00');
    final actState  = ref.watch(saleBillActionsProvider);
    final isLoading = actState.isLoading;
    final enabled   = cashbookId != null && !isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            if (remaining > 0)
              Text(
                '₹${fmt.format(remaining)} is still outstanding. '
                'This will record a final income entry and mark the bill as settled.',
                style: const TextStyle(
                    color: _T.muted, fontSize: 13, height: 1.5),
              )
            else
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
                    cashbookId:    cashbookId!,
                    billId:        bill.saleBillId,
                    billNumber:    bill.billNumber,
                    partyName:     bill.partyName,
                    remaining:     remaining,
                    createdBy:     user.uid,
                    createdByName: user.displayName ?? '',
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

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _amtCtrl  = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

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
            cashbookId:    widget.cashbookId,
            billId:        widget.bill.saleBillId,
            billNumber:    widget.bill.billNumber,
            partyName:     widget.bill.partyName,
            amount:        amount,
            createdBy:     user.uid,
            createdByName: user.displayName ?? '',
            note:          _noteCtrl.text.trim(),
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
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _T.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _T.green.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.add_rounded,
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
                          '${widget.bill.partyName}  ·  ${widget.bill.billNumber}',
                          style: const TextStyle(
                              color: _T.muted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 18),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _T.accent.withValues(alpha: 0.14)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: _T.accent, size: 14),
                    const SizedBox(width: 8),
                    const Text('Remaining balance',
                        style: TextStyle(color: _T.muted, fontSize: 12)),
                    const Spacer(),
                    Text('₹${fmt.format(widget.remaining)}',
                        style: const TextStyle(
                            color: _T.amber,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ],
                ),
              ),
              TextFormField(
                controller: _amtCtrl,
                autofocus: true,
                style: const TextStyle(color: _T.text, fontSize: 16,
                    fontWeight: FontWeight.w500),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _fieldDec(
                    label: 'Amount Received (₹)',
                    hint: '0.00',
                    icon: Icons.currency_rupee_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                style: const TextStyle(color: _T.text, fontSize: 14),
                maxLines: 2,
                decoration: _fieldDec(
                    label: 'Note (optional)',
                    hint: 'e.g. Cheque payment, cash received…',
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
                  fontWeight: FontWeight.w700,
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
    final Color c = settled ? _T.green : _T.amber;
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

// ─────────────────────────────────────────────────────────────────────────────
//  Bill page three-dot menu
// ─────────────────────────────────────────────────────────────────────────────

class _BillMoreMenu extends StatelessWidget {
  final VoidCallback onShare;
  final bool         isGenerating;
  const _BillMoreMenu({required this.onShare, required this.isGenerating});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: isGenerating
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.0, color: _T.muted))
            : const Icon(Icons.more_vert_rounded, color: _T.text, size: 22),
        color: _T.card2,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _T.border),
        ),
        onSelected: (v) { if (v == 'share') onShare(); },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'share',
            height: 46,
            child: Row(children: [
              const Icon(Icons.share_rounded, color: _T.accent, size: 16),
              const SizedBox(width: 10),
              const Text('Share Bill',
                  style: TextStyle(
                      color: _T.text, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      );
}
// ─────────────────────────────────────────────────────────────────────────────
//  Shareable bill card — receipt format (rendered off-screen → HD PNG)
// ─────────────────────────────────────────────────────────────────────────────

class _BillShareCard extends StatelessWidget {
  final SaleBillEntity bill;
  final double         received;
  final double         remaining;
  final bool           settled;
  final List<_TxItem>  transactions;
  final DateTime       generatedAt;

  const _BillShareCard({
    required this.bill,
    required this.received,
    required this.remaining,
    required this.settled,
    required this.transactions,
    required this.generatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy, h:mm a');
    final genFmt  = DateFormat('dd MMM yyyy  ·  hh:mm a');
    final partial = received > 0 && remaining > 0;
    final Color balColor = settled ? const Color(0xFF38D68A)
                         : partial ? const Color(0xFFF5A623)
                         :           const Color(0xFFE85C5C);

    // Card colours — matches screenshot aesthetic
    const cOuter  = Color(0xFF1A1C24);
    const cCard   = Color(0xFF252836);
    const cLine   = Color(0xFF363844);
    const cLabel  = Color(0xFF8A8FA0);
    const cValue  = Color(0xFFF0F2F8);
    const cHeader = Color(0xFFFFFFFF);

    Widget divider() => Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      height: 1, color: cLine,
    );

    return SizedBox(
      width: 420,
      child: Container(
        color: cOuter,
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: cCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [

              // ── Header ───────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Text(
                      bill.partyName.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: cHeader,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'BILL PAYMENT RECEIPT',
                      style: TextStyle(
                          color: cLabel,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5),
                    ),
                  ],
                ),
              ),

              divider(),

              // ── Bill details ─────────────────────────────────────────
              _ReceiptRow(label: 'CLIENT',
                  value: bill.partyName,
                  cLabel: cLabel, cValue: cValue),
              const SizedBox(height: 10),
              _ReceiptRow(label: 'BILL NO.',
                  value: bill.billNumber,
                  cLabel: cLabel, cValue: cValue),
              const SizedBox(height: 10),
              _ReceiptRow(label: 'DATE',
                  value: dateFmt.format(bill.billDate),
                  cLabel: cLabel, cValue: cValue),
              if ((bill.billNote ?? '').isNotEmpty) ...[          
                const SizedBox(height: 10),
                _ReceiptRow(label: 'NOTE',
                    value: bill.billNote!,
                    cLabel: cLabel, cValue: cValue),
              ],

              divider(),

              // ── Financials ───────────────────────────────────────────
              _ReceiptRow(label: 'BILL TOTAL',
                  value: '₹${fmt.format(bill.billTotal)}',
                  cLabel: cLabel, cValue: cValue),
              const SizedBox(height: 10),
              _ReceiptRow(label: 'AMOUNT PAID',
                  value: '₹${fmt.format(received)}',
                  cLabel: cLabel, cValue: cValue),
              const SizedBox(height: 10),
              _ReceiptRow(
                label: 'BALANCE DUE',
                value: settled
                    ? 'FULLY PAID'
                    : '₹${fmt.format(remaining)}',
                cLabel: cLabel,
                cValue: balColor,
                bold: true,
              ),

              divider(),

              // ── Account details ──────────────────────────────────────
              const Text(
                'ACCOUNT DETAILS',
                style: TextStyle(
                    color: cValue,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8),
              ),
              const SizedBox(height: 12),
              _ReceiptRow(label: 'ACCOUNT NAME',
                  value: bill.partyName,
                  cLabel: cLabel, cValue: cValue),
              const SizedBox(height: 10),
              const _ReceiptRow(label: 'CATEGORY',
                  value: 'Party Ledger',
                  cLabel: cLabel, cValue: cValue),

              // ── Footer ───────────────────────────────────────────────
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Generated ${genFmt.format(generatedAt)}',
                  style: const TextStyle(
                      color: Color(0xFF4A4F5C), fontSize: 9.5),
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
//  Receipt row  (label left, value right)
// ─────────────────────────────────────────────────────────────────────────────

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  cLabel;
  final Color  cValue;
  final bool   bold;
  const _ReceiptRow({
    required this.label,
    required this.value,
    required this.cLabel,
    required this.cValue,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label,
                style: TextStyle(
                    color: cLabel,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4)),
          ),
          Expanded(
            flex: 5,
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: cValue,
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ),
        ],
      );
}
