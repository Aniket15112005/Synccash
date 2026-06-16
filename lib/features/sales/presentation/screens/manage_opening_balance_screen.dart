import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../providers/party_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens — Golden Ledger aesthetic
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg      = Color(0xFF090A0C);
  static const surface = Color(0xFF101318);
  static const card    = Color(0xFF141820);
  static const card2   = Color(0xFF181D26);
  static const line    = Color(0xFF1C2230);
  static const line2   = Color(0xFF242C3A);
  static const muted   = Color(0xFF445060);
  static const muted2  = Color(0xFF6A7888);
  static const gold    = Color(0xFFC4903A);
  static const gold2   = Color(0xFFE2B870);
  static const accent  = Color(0xFF4A70D0);
  static const accent2 = Color(0xFF7AA0F0);
  static const text    = Color(0xFFDCE8F4);
  static const text2   = Color(0xFF8AACCC);
  static const green   = Color(0xFF28C898);
  static const red     = Color(0xFFE04A62);
  static const amber   = Color(0xFFEAA030);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated background — balance scale painter
// ─────────────────────────────────────────────────────────────────────────────

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
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
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
        Container(color: _T.bg),
        // Scale animation — lower portion of screen
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => RepaintBoundary(
              child: CustomPaint(
                painter: _BalanceScalePainter(t: _ctrl.value),
              ),
            ),
          ),
        ),
        // Ledger line grid overlay — static
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _LedgerGridPainter(),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Draws a gently oscillating balance scale with floating coins.
/// Thematically tied to "opening balance" — the art of balancing the books.
class _BalanceScalePainter extends CustomPainter {
  final double t; // 0..1 from animation
  const _BalanceScalePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Rocking angle: ±5° sine wave
    final angle = math.sin(t * math.pi) * 0.09;

    final cx     = size.width * 0.72;
    final poleTop = size.height * 0.28;
    final poleBot = size.height * 0.82;
    final beamY  = poleTop + 20;
    final beamLen = math.min(size.width * 0.28, 110.0);

    final basePaint = Paint()
      ..color = _T.gold.withValues(alpha: 0.06)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final chainPaint = Paint()
      ..color = _T.gold.withValues(alpha: 0.04)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = _T.gold.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    // Vertical pole
    canvas.drawLine(
      Offset(cx, poleTop),
      Offset(cx, poleBot),
      basePaint,
    );

    // Base
    canvas.drawLine(
      Offset(cx - 24, poleBot),
      Offset(cx + 24, poleBot),
      basePaint..strokeWidth = 1.8,
    );
    canvas.drawLine(
      Offset(cx - 16, poleBot + 6),
      Offset(cx + 16, poleBot + 6),
      basePaint..strokeWidth = 1.2,
    );

    // Pivot cap
    canvas.drawCircle(Offset(cx, beamY), 4, basePaint..strokeWidth = 1.2);

    // Beam ends (tilted by angle)
    final dx = beamLen * math.cos(angle);
    final dy = beamLen * math.sin(angle);
    final lx = cx - dx;
    final ly = beamY - dy;
    final rx = cx + dx;
    final ry = beamY + dy;

    canvas.drawLine(Offset(lx, ly), Offset(rx, ry), basePaint..strokeWidth = 1.4);

    // Chain + pan (left)
    const chainLen = 44.0;
    const panR     = 22.0;

    final lChainBot = Offset(lx, ly + chainLen);
    canvas.drawLine(Offset(lx, ly), lChainBot, chainPaint);
    canvas.drawCircle(lChainBot, panR, fillPaint);
    canvas.drawCircle(lChainBot, panR, chainPaint..strokeWidth = 0.8);

    // Coins in left pan
    _drawCoin(canvas, Offset(lx - 7, ly + chainLen - 4), 6, 0.05);
    _drawCoin(canvas, Offset(lx + 5, ly + chainLen - 2), 5, 0.04);

    // Chain + pan (right)
    final rChainBot = Offset(rx, ry + chainLen);
    canvas.drawLine(Offset(rx, ry), rChainBot, chainPaint);
    canvas.drawCircle(rChainBot, panR, fillPaint);
    canvas.drawCircle(rChainBot, panR, chainPaint);

    // Coins in right pan
    _drawCoin(canvas, Offset(rx - 5, ry + chainLen - 3), 7, 0.05);

    // Floating coin particles rising
    final coinPositions = [
      Offset(cx - beamLen * 0.6, poleBot - 30 - t * 60),
      Offset(cx + beamLen * 0.3, poleBot - 50 - t * 40),
      Offset(cx - beamLen * 0.1, poleBot - 15 - t * 80),
    ];
    for (final pos in coinPositions) {
      if (pos.dy > poleTop) {
        final opacity = ((poleBot - pos.dy) / (poleBot - poleTop)).clamp(0.0, 1.0);
        _drawCoin(canvas, pos, 5, 0.035 * opacity);
      }
    }

    // ₹ glyph near scale center (very faint)
    final tp = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: _T.gold.withValues(alpha: 0.04),
          fontSize: 60,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 18, beamY + 20));
  }

  void _drawCoin(Canvas canvas, Offset center, double r, double alpha) {
    final fill = Paint()
      ..color = _T.gold.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = _T.gold.withValues(alpha: alpha * 1.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawCircle(center, r, fill);
    canvas.drawCircle(center, r, stroke);
  }

  @override
  bool shouldRepaint(covariant _BalanceScalePainter old) => old.t != t;
}

/// Static faint horizontal ledger lines — like accounting paper.
class _LedgerGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _T.line.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    const spacing = 40.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Left margin line
    final margin = Paint()
      ..color = _T.gold.withValues(alpha: 0.04)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(28, 0), Offset(28, size.height), margin);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Manage Opening Balance Screen
// ─────────────────────────────────────────────────────────────────────────────

class ManageOpeningBalanceScreen extends ConsumerStatefulWidget {
  const ManageOpeningBalanceScreen({super.key});

  @override
  ConsumerState<ManageOpeningBalanceScreen> createState() =>
      _ManageOpeningBalanceScreenState();
}

class _ManageOpeningBalanceScreenState
    extends ConsumerState<ManageOpeningBalanceScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  List<String>                       _billPartyNames = [];
  StreamSubscription<QuerySnapshot>? _billsSub;
  ProviderSubscription<String?>?     _idSub;
  String?                            _cashbookId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _query = _searchCtrl.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _idSub = ref.listenManual<String?>(
        currentCashbookIdProvider,
        (prev, next) {
          if (next != null && next.isNotEmpty && next != _cashbookId) {
            _cashbookId = next;
            _billsSub?.cancel();
            _startBillsStream(next);
          }
        },
        fireImmediately: true,
      );
    });
  }

  void _startBillsStream(String cashbookId) {
    _billsSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('sale_bills')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final names = snap.docs
          .map((d) => (d['partyName'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      setState(() => _billPartyNames = names);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _idSub?.close();
    _billsSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_MergedParty> _mergeParties(List<PartyEntity> savedParties) {
    final savedByKey = <String, PartyEntity>{};
    for (final p in savedParties) {
      savedByKey[p.partyName.trim().toLowerCase()] = p;
    }
    final result = <_MergedParty>[];
    final seen   = <String>{};
    for (final p in savedParties) {
      final key = p.partyName.trim().toLowerCase();
      seen.add(key);
      result.add(_MergedParty(name: p.partyName, entity: p));
    }
    for (final name in _billPartyNames) {
      final key = name.trim().toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        result.add(_MergedParty(name: name, entity: null));
      }
    }
    result.sort((a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  void _openEdit(_MergedParty party) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditOBSheet(party: party),
    );
  }

  void _openCreate() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewPartySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partiesAsync = ref.watch(partiesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: _AnimatedBackground(
        child: Column(
          children: [
            _Header(onAdd: _openCreate),

            // ── Summary strip ─────────────────────────────────────────────
            partiesAsync.maybeWhen(
              data: (parties) {
                if (parties.isEmpty) return const SizedBox.shrink();
                final totalOB = parties.fold<double>(
                    0.0, (s, p) => s + p.openingBalance);
                final withOB  = parties
                    .where((p) => p.openingBalance > 0)
                    .length;
                return _SummaryStrip(
                  clientCount: parties.length,
                  withOB:      withOB,
                  totalOB:     totalOB,
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),

            // ── Search ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: _SearchField(
                controller: _searchCtrl,
                hint: 'Search clients…',
              ),
            ),

            // ── List ──────────────────────────────────────────────────────
            Expanded(
              child: partiesAsync.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: _LoadingSpinner()),
                error:   (e, _) => _ErrorMsg(message: e.toString()),
                data:    (savedParties) {
                  final merged   = _mergeParties(savedParties);
                  final q        = _query.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? merged
                      : merged
                          .where((p) =>
                              p.name.toLowerCase().contains(q))
                          .toList();

                  if (filtered.isEmpty) {
                    return _EmptyState(
                      hasSearch: q.isNotEmpty,
                      query:     _query,
                      onAdd:     _openCreate,
                    );
                  }

                  return ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        Container(height: 1, color: _T.line),
                    itemBuilder: (_, i) => _PartyTile(
                      party:    filtered[i],
                      index:    i,
                      onTap:    () => _openEdit(filtered[i]),
                      onEdit:   () => _openEdit(filtered[i]),
                      onDelete: filtered[i].entity != null
                          ? () => _confirmDelete(filtered[i])
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _FAB(onTap: _openCreate),
    );
  }

  void _confirmDelete(_MergedParty party) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _T.line2)),
        title: const Text('Remove Client?',
            style: TextStyle(
                color: _T.text,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        content: Text(
          'This will remove the opening balance record for '
          '"${party.name}". Bills and transactions are not affected.',
          style: const TextStyle(
              color: _T.muted2, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: _T.muted2)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final cashbookId = ref.read(currentCashbookIdProvider);
              if (cashbookId == null || party.entity == null) return;
              try {
                await FirebaseFirestore.instance
                    .collection('cashbooks')
                    .doc(cashbookId)
                    .collection('parties')
                    .doc(party.entity!.partyId)
                    .delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    _snackBar('Removed', success: true),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    _snackBar('Error: $e', success: false),
                  );
                }
              }
            },
            child: const Text('Remove',
                style: TextStyle(
                    color: _T.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class _MergedParty {
  final String       name;
  final PartyEntity? entity;
  const _MergedParty({required this.name, required this.entity});
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header — Ledger title bar
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onAdd;
  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 16),
      decoration: BoxDecoration(
        color: _T.bg.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
              color: _T.gold.withValues(alpha: 0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _T.line,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _T.line2),
              ),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: _T.muted2, size: 14),
            ),
          ),
          const SizedBox(width: 14),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'OPENING ',
                        style: TextStyle(
                          color: _T.gold2,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      TextSpan(
                        text: 'BALANCE',
                        style: TextStyle(
                          color: _T.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                const Text('Ledger  ·  Client balances',
                    style: TextStyle(
                        color: _T.muted, fontSize: 10,
                        letterSpacing: 0.2)),
              ],
            ),
          ),

          // Add button
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD4A040), Color(0xFFA07020)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _T.gold.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Summary strip — ledger totals row
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int    clientCount;
  final int    withOB;
  final double totalOB;
  const _SummaryStrip({
    required this.clientCount,
    required this.withOB,
    required this.totalOB,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _T.gold.withValues(alpha: 0.14)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _SummaryCell(
              label: 'CLIENTS',
              value: '$clientCount',
              color: _T.text2,
            ),
            VerticalDivider(
                width: 1, color: _T.line2, indent: 10, endIndent: 10),
            _SummaryCell(
              label: 'WITH BALANCE',
              value: '$withOB',
              color: _T.green,
            ),
            VerticalDivider(
                width: 1, color: _T.line2, indent: 10, endIndent: 10),
            _SummaryCell(
              label: 'TOTAL OB',
              value: '₹${_fmtNum(totalOB)}',
              color: _T.gold2,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  final bool   isLast;
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: _T.muted,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party tile — ledger entry row style
// ─────────────────────────────────────────────────────────────────────────────

class _PartyTile extends StatelessWidget {
  final _MergedParty  party;
  final int           index;
  final VoidCallback  onTap;
  final VoidCallback  onEdit;
  final VoidCallback? onDelete;

  const _PartyTile({
    required this.party,
    required this.index,
    required this.onTap,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasSaved = party.entity != null;
    final ob       = party.entity?.openingBalance ?? 0.0;
    final hasOB    = ob > 0;
    final place    = party.entity?.place ?? '';
    final desc     = party.entity?.description ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: index.isEven
            ? _T.surface.withValues(alpha: 0.5)
            : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left balance indicator stripe
              Container(
                width: 3,
                color: hasOB
                    ? _T.gold.withValues(alpha: 0.55)
                    : _T.line.withValues(alpha: 0.4),
              ),

              // Index number (ledger row number)
              Container(
                width: 32,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: _T.line.withValues(alpha: 0.2),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                      color: _T.muted.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),

              Container(
                width: 1,
                color: _T.line.withValues(alpha: 0.5),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Row(
                    children: [
                      // Avatar
                      _CircleAvatar(name: party.name, size: 40),
                      const SizedBox(width: 12),

                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(party.name,
                                style: const TextStyle(
                                    color: _T.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: -0.1)),

                            if (place.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(children: [
                                const Icon(Icons.location_on_rounded,
                                    color: _T.muted, size: 10),
                                const SizedBox(width: 2),
                                Text(place,
                                    style: const TextStyle(
                                        color: _T.muted, fontSize: 10)),
                              ]),
                            ] else if (desc.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(desc,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: _T.muted, fontSize: 10)),
                            ],

                            if (!hasSaved) ...[
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _T.gold.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: _T.gold.withValues(alpha: 0.14)),
                                ),
                                child: const Text('Tap to set balance',
                                    style: TextStyle(
                                        color: _T.gold,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Amount column (CR / DR style)
                      if (hasSaved) ...[
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (hasOB) ...[
                              Text(
                                '₹${_fmtNum(ob)}',
                                style: const TextStyle(
                                    color: _T.gold2,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    letterSpacing: -0.3),
                              ),
                              const SizedBox(height: 1),
                              const Text('DR',
                                  style: TextStyle(
                                      color: _T.gold,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6)),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _T.muted.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: _T.line2),
                                ),
                                child: const Text('NIL',
                                    style: TextStyle(
                                        color: _T.muted2,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5)),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ActionBtn(
                                  icon:  Icons.edit_rounded,
                                  color: _T.accent,
                                  onTap: onEdit,
                                ),
                                if (onDelete != null) ...[
                                  const SizedBox(width: 5),
                                  _ActionBtn(
                                    icon:  Icons.delete_outline_rounded,
                                    color: _T.muted2,
                                    onTap: onDelete!,
                                    small: true,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ] else ...[
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color: _T.gold.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _T.gold.withValues(alpha: 0.12)),
                          ),
                          child: const Icon(Icons.add_rounded,
                              color: _T.gold, size: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;
  final bool         small;
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: small ? 24 : 28,
          height: small ? 24 : 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: small ? 0.05 : 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: color.withValues(alpha: small ? 0.10 : 0.18)),
          ),
          child: Icon(icon,
              color: color.withValues(alpha: small ? 0.5 : 0.9),
              size: small ? 11 : 13),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading / Error / Empty states
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(
              color: _T.gold.withValues(alpha: 0.6),
              strokeWidth: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Loading ledger…',
              style: TextStyle(color: _T.muted, fontSize: 11)),
        ],
      );
}

class _ErrorMsg extends StatelessWidget {
  final String message;
  const _ErrorMsg({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error: $message',
              style: const TextStyle(
                  color: _T.red, fontSize: 13),
              textAlign: TextAlign.center),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final bool         hasSearch;
  final String       query;
  final VoidCallback onAdd;
  const _EmptyState({
    required this.hasSearch,
    required this.query,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  color: _T.gold.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _T.gold.withValues(alpha: 0.12)),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : Icons.balance_rounded,
                  color: _T.gold.withValues(alpha: 0.40),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasSearch
                    ? 'No clients match "$query"'
                    : 'Ledger is empty',
                style: const TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                hasSearch
                    ? 'Try a different search term'
                    : 'Add a client to start tracking\nopening balances',
                style: const TextStyle(
                    color: _T.muted2, fontSize: 12, height: 1.5),
                textAlign: TextAlign.center,
              ),
              if (!hasSearch) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD4A040), Color(0xFFA07020)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Add Client',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Search field
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _SearchField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: const TextStyle(color: _T.text, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _T.muted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded,
              color: _T.muted, size: 16),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: _T.muted, size: 15),
                  onPressed: controller.clear,
                )
              : null,
          filled: true,
          fillColor: _T.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _T.line2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: _T.gold, width: 1.2),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Edit Opening Balance sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EditOBSheet extends ConsumerStatefulWidget {
  final _MergedParty party;
  const _EditOBSheet({required this.party});

  @override
  ConsumerState<_EditOBSheet> createState() => _EditOBSheetState();
}

class _EditOBSheetState extends ConsumerState<_EditOBSheet> {
  final _formKey   = GlobalKey<FormState>();
  late final TextEditingController _obCtrl;
  late final TextEditingController _placeCtrl;
  late final TextEditingController _descCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e        = widget.party.entity;
    final existing = e?.openingBalance ?? 0.0;
    _obCtrl    = TextEditingController(
        text: existing == 0.0 ? '' : _obText(existing));
    _placeCtrl = TextEditingController(text: e?.place ?? '');
    _descCtrl  = TextEditingController(text: e?.description ?? '');
  }

  String _obText(double v) =>
      v == v.truncateToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(2);

  @override
  void dispose() {
    _obCtrl.dispose();
    _placeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || cashbookId.isEmpty) {
      _showSnack('Session expired. Please restart the app.',
          success: false);
      return;
    }
    setState(() => _submitting = true);
    try {
      final ob = double.tryParse(_obCtrl.text.trim()) ?? 0.0;
      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('parties')
          .doc(widget.party.name.trim().toLowerCase())
          .set({
        'partyName':      widget.party.name.trim(),
        'openingBalance': ob,
        'description':    _descCtrl.text.trim(),
        'place':          _placeCtrl.text.trim(),
        'updatedAt':      FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        final m = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        m.showSnackBar(
            _snackBar('Opening balance updated', success: true));
      }
    } catch (e) {
      if (mounted)
        _showSnack('Failed to save: $e', success: false);
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
    final e      = widget.party.entity;
    return Container(
      decoration: const BoxDecoration(
        color: _T.card2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottom),
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
                    color: _T.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Avatar + name
              Row(
                children: [
                  _CircleAvatar(name: widget.party.name, size: 50),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.party.name,
                            style: const TextStyle(
                                color: _T.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: -0.3)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _T.gold.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: _T.gold.withValues(alpha: 0.14)),
                          ),
                          child: Text(
                            e != null
                                ? 'Edit Opening Balance'
                                : 'Set Opening Balance',
                            style: const TextStyle(
                                color: _T.gold2,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Current OB preview
              if (e != null && e.openingBalance > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _T.gold.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _T.gold.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: _T.gold, size: 13),
                      const SizedBox(width: 8),
                      const Text('Current Balance',
                          style: TextStyle(
                              color: _T.muted2, fontSize: 11)),
                      const Spacer(),
                      Text('₹${_fmtNum(e.openingBalance)}',
                          style: const TextStyle(
                              color: _T.gold2,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              TextFormField(
                controller: _obCtrl,
                autofocus: true,
                style: const TextStyle(
                    color: _T.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: _fieldDec(
                    label: 'Opening Balance (₹)',
                    hint: '0',
                    icon: Icons.currency_rupee_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (double.tryParse(v.trim()) == null) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _placeCtrl,
                style: const TextStyle(color: _T.text, fontSize: 13),
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDec(
                    label: 'Place / City (optional)',
                    hint: 'e.g. Mumbai',
                    icon: Icons.location_on_outlined),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: _T.text, fontSize: 13),
                maxLines: 2,
                decoration: _fieldDec(
                    label: 'Description (optional)',
                    hint: 'e.g. Wholesale dealer',
                    icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 22),

              _SaveButton(
                label:      'Save Changes',
                submitting: _submitting,
                onPressed:  _submitting ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  New Party sheet
// ─────────────────────────────────────────────────────────────────────────────

class _NewPartySheet extends ConsumerStatefulWidget {
  const _NewPartySheet();

  @override
  ConsumerState<_NewPartySheet> createState() => _NewPartySheetState();
}

class _NewPartySheetState extends ConsumerState<_NewPartySheet> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _obCtrl    = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _obCtrl.dispose();
    _placeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || cashbookId.isEmpty) {
      _showSnack('Session expired. Please restart the app.',
          success: false);
      return;
    }
    setState(() => _submitting = true);
    try {
      final name = _nameCtrl.text.trim();
      final ob   = double.tryParse(_obCtrl.text.trim()) ?? 0.0;
      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('parties')
          .doc(name.toLowerCase())
          .set({
        'partyName':      name,
        'openingBalance': ob,
        'description':    _descCtrl.text.trim(),
        'place':          _placeCtrl.text.trim(),
        'updatedAt':      FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        final m = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        m.showSnackBar(
            _snackBar('Client added successfully', success: true));
      }
    } catch (e) {
      if (mounted)
        _showSnack('Failed to save: $e', success: false);
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
    return Container(
      decoration: const BoxDecoration(
        color: _T.card2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottom),
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
                    color: _T.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFD4A040), Color(0xFFA07020)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _T.gold.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Client',
                          style: TextStyle(
                              color: _T.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 17)),
                      Text('Add with opening balance',
                          style: TextStyle(
                              color: _T.muted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),

              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                style: const TextStyle(color: _T.text),
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDec(
                    label: 'Client / Party Name *',
                    hint: 'e.g. ABC Traders',
                    icon: Icons.business_rounded),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Name is required'
                        : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _obCtrl,
                style: const TextStyle(color: _T.text),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: _fieldDec(
                    label: 'Opening Balance (₹)',
                    hint: '0',
                    icon: Icons.currency_rupee_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (double.tryParse(v.trim()) == null) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _placeCtrl,
                style: const TextStyle(color: _T.text),
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDec(
                    label: 'Place / City (optional)',
                    hint: 'e.g. Mumbai',
                    icon: Icons.location_on_outlined),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: _T.text),
                maxLines: 2,
                decoration: _fieldDec(
                    label: 'Description (optional)',
                    hint: 'e.g. Wholesale dealer',
                    icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 22),

              _SaveButton(
                label:      'Add Client',
                submitting: _submitting,
                onPressed:  _submitting ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Save button (shared)
// ─────────────────────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final String       label;
  final bool         submitting;
  final VoidCallback? onPressed;
  const _SaveButton({
    required this.label,
    required this.submitting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 50,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: submitting
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD4A040), Color(0xFF9A6A18)],
                  ),
            color: submitting
                ? _T.gold.withValues(alpha: 0.20)
                : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: submitting
                ? null
                : [
                    BoxShadow(
                      color: _T.gold.withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: submitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white))
                : Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.2)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FAB
// ─────────────────────────────────────────────────────────────────────────────

class _FAB extends StatelessWidget {
  final VoidCallback onTap;
  const _FAB({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD4A040), Color(0xFF9A6A18)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _T.gold.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded,
              color: Colors.white, size: 24),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

String _fmtNum(double v) {
  if (v == 0.0) return '0';
  if (v == v.truncateToDouble()) {
    return v.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
  final s = v.toStringAsFixed(2);
  return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

SnackBar _snackBar(String msg, {required bool success}) => SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: success
          ? _T.green.withValues(alpha: 0.9)
          : _T.red.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );

InputDecoration _fieldDec(
        {required String label, String? hint, IconData? icon}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _T.muted, fontSize: 12),
      hintStyle: const TextStyle(color: _T.muted, fontSize: 12),
      prefixIcon:
          icon != null ? Icon(icon, color: _T.muted, size: 16) : null,
      filled: true,
      fillColor: _T.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _T.line2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _T.gold, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _T.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _T.red, width: 1.5),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
//  Circle avatar — muted ledger palette
// ─────────────────────────────────────────────────────────────────────────────

class _CircleAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _CircleAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    const palette = [
      [Color(0xFF3A5EA0), Color(0xFF2A4880)],
      [Color(0xFF5A4090), Color(0xFF443070)],
      [Color(0xFF206878), Color(0xFF185060)],
      [Color(0xFF3A7850), Color(0xFF286038)],
      [Color(0xFF8A5820), Color(0xFF704010)],
      [Color(0xFF804050), Color(0xFF683040)],
    ];
    final idx    =
        name.isNotEmpty ? name.codeUnitAt(0) % palette.length : 0;
    final colors = palette[idx];
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        shape: BoxShape.circle,
        border: Border.all(
            color: colors[0].withValues(alpha: 0.4), width: 1),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
              fontSize: size * 0.36),
        ),
      ),
    );
  }
}