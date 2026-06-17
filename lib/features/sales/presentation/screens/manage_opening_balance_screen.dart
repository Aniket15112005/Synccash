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
//  Design tokens — SkyLedger modern light palette
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg       = Color(0xFFF0F4FF);
  static const surface  = Color(0xFFFFFFFF);
  static const card     = Color(0xFFFFFFFF);
  static const card2    = Color(0xFFF8FAFF);
  static const line     = Color(0xFFE5E7EB);
  static const line2    = Color(0xFFD1D5DB);
  static const muted    = Color(0xFF9CA3AF);
  static const muted2   = Color(0xFF6B7280);
  static const gold     = Color(0xFFF59E0B);
  static const gold2    = Color(0xFFD97706);
  static const accent   = Color(0xFF4F46E5);
  static const accent2  = Color(0xFF818CF8);
  static const text     = Color(0xFF111827);
  static const text2    = Color(0xFF374151);
  static const green    = Color(0xFF10B981);
  static const red      = Color(0xFFEF4444);
  static const amber    = Color(0xFFF59E0B);
  static const indigo   = Color(0xFF6366F1);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated background — floating soft orbs
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
      duration: const Duration(seconds: 10),
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
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => RepaintBoundary(
              child: CustomPaint(
                painter: _OrbPainter(t: _ctrl.value),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  const _OrbPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final ease = (math.sin(t * math.pi) * 0.5 + 0.5);

    void drawOrb(Offset center, double radius, Color color, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    drawOrb(
      Offset(size.width * 0.15 + ease * 20, size.height * 0.12 + ease * 10),
      size.width * 0.55,
      _T.accent2,
      0.09,
    );
    drawOrb(
      Offset(size.width * 0.85 - ease * 15, size.height * 0.72 - ease * 12),
      size.width * 0.50,
      _T.indigo,
      0.07,
    );
    drawOrb(
      Offset(size.width * 0.50 + ease * 8, size.height * 0.40),
      size.width * 0.35,
      _T.green,
      0.04,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.t != t;
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
      final nameMap = <String, String>{};
      for (final d in snap.docs) {
        final n = (d['partyName'] as String? ?? '').trim();
        if (n.isEmpty) continue;
        nameMap.putIfAbsent(n.toLowerCase(), () => n);
      }
      final names = nameMap.values.toList()..sort();
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PartyTile(
                        party:    filtered[i],
                        index:    i,
                        onTap:    () => _openEdit(filtered[i]),
                        onEdit:   () => _openEdit(filtered[i]),
                        onDelete: filtered[i].entity != null
                            ? () => _confirmDelete(filtered[i])
                            : null,
                      ),
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
        backgroundColor: _T.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: _T.line)),
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _T.red.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: _T.red, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Remove Client?',
                style: TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ],
        ),
        content: Text(
          'This will remove the opening balance record for '
          '"${party.name}". Bills and transactions are not affected.',
          style: const TextStyle(
              color: _T.muted2, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: _T.muted2, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
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
            style: ElevatedButton.styleFrom(
              backgroundColor: _T.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Remove',
                style: TextStyle(fontWeight: FontWeight.w700)),
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
//  Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onAdd;
  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 14),
      decoration: BoxDecoration(
        color: _T.surface.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: _T.accent.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: _T.bg,
                shape: BoxShape.circle,
                border: Border.all(color: _T.line2),
              ),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: _T.text2, size: 15),
            ),
          ),
          const SizedBox(width: 12),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Opening Balance',
                  style: TextStyle(
                    color: _T.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Manage client ledger balances',
                  style: TextStyle(
                      color: _T.muted, fontSize: 11, letterSpacing: 0.1),
                ),
              ],
            ),
          ),

          // Add button
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _T.accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  color: Colors.white, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Summary strip
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          _StatCard(
            icon: Icons.people_alt_rounded,
            iconColor: _T.accent,
            iconBg: _T.accent.withValues(alpha: 0.10),
            label: 'Clients',
            value: '$clientCount',
            valueColor: _T.text,
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.check_circle_rounded,
            iconColor: _T.green,
            iconBg: _T.green.withValues(alpha: 0.10),
            label: 'With Balance',
            value: '$withOB',
            valueColor: _T.green,
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.account_balance_wallet_rounded,
            iconColor: _T.gold2,
            iconBg: _T.gold2.withValues(alpha: 0.10),
            label: 'Total OB',
            value: '₹${_fmtNum(totalOB)}',
            valueColor: _T.gold2,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final Color    iconBg;
  final String   label;
  final String   value;
  final Color    valueColor;
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: _T.muted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party tile — modern card style
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
        decoration: BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              // Avatar
              _CircleAvatar(name: party.name, size: 44),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      party.name,
                      style: const TextStyle(
                        color: _T.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: _T.muted, size: 11),
                          const SizedBox(width: 2),
                          Text(place,
                              style: const TextStyle(
                                  color: _T.muted2, fontSize: 11)),
                        ],
                      ),
                    ] else if (desc.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _T.muted2, fontSize: 11),
                      ),
                    ],
                    if (!hasSaved) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _T.amber.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _T.amber.withValues(alpha: 0.25)),
                        ),
                        child: const Text(
                          'Tap to set balance',
                          style: TextStyle(
                            color: _T.gold2,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Amount / NIL badge
              if (hasSaved) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hasOB) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _T.green.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _T.green.withValues(alpha: 0.20)),
                        ),
                        child: Text(
                          '₹${_fmtNum(ob)}',
                          style: const TextStyle(
                            color: _T.green,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text('DR',
                          style: TextStyle(
                            color: _T.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          )),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _T.line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('NIL',
                            style: TextStyle(
                              color: _T.muted2,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 4),
              ],

              // Three-dot menu
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert_rounded,
                    color: _T.muted2.withValues(alpha: 0.7), size: 20),
                iconSize: 20,
                color: _T.surface,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: _T.line),
                ),
                onSelected: (v) {
                  HapticFeedback.selectionClick();
                  if (v == 'edit') onEdit();
                  if (v == 'delete' && onDelete != null) onDelete!();
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'edit',
                    height: 44,
                    child: Row(children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: _T.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: _T.accent, size: 14),
                      ),
                      const SizedBox(width: 10),
                      const Text('Edit',
                          style: TextStyle(
                            color: _T.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ]),
                  ),
                  if (onDelete != null)
                    PopupMenuItem<String>(
                      value: 'delete',
                      height: 44,
                      child: Row(children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: _T.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(Icons.delete_outline_rounded,
                              color: _T.red, size: 14),
                        ),
                        const SizedBox(width: 10),
                        const Text('Delete',
                            style: TextStyle(
                              color: _T.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            )),
                      ]),
                    ),
                ],
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
            width: 32, height: 32,
            child: CircularProgressIndicator(
              color: _T.accent.withValues(alpha: 0.7),
              strokeWidth: 2.5,
              backgroundColor: _T.accent.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Loading clients…',
              style: TextStyle(color: _T.muted, fontSize: 12)),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: _T.red.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: _T.red, size: 26),
              ),
              const SizedBox(height: 12),
              Text('Error: $message',
                  style: const TextStyle(
                      color: _T.red, fontSize: 13),
                  textAlign: TextAlign.center),
            ],
          ),
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
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : Icons.balance_rounded,
                  color: _T.accent.withValues(alpha: 0.45),
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                hasSearch
                    ? 'No clients match "$query"'
                    : 'No clients yet',
                style: const TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? 'Try a different search term'
                    : 'Add your first client to start\ntracking opening balances',
                style: const TextStyle(
                    color: _T.muted2, fontSize: 13, height: 1.6),
                textAlign: TextAlign.center,
              ),
              if (!hasSearch) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _T.accent.withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text('Add Client',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
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
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          style: const TextStyle(color: _T.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _T.muted, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded,
                color: _T.muted, size: 18),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _T.muted, size: 16),
                    onPressed: controller.clear,
                  )
                : null,
            filled: true,
            fillColor: Colors.transparent,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: _T.accent, width: 1.5),
            ),
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
        color: _T.surface,
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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _T.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header row
              Row(
                children: [
                  _CircleAvatar(name: widget.party.name, size: 48),
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
                            color: _T.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            e != null
                                ? 'Edit Opening Balance'
                                : 'Set Opening Balance',
                            style: const TextStyle(
                                color: _T.accent,
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
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _T.green.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _T.green.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: _T.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: _T.green, size: 14),
                      ),
                      const SizedBox(width: 10),
                      const Text('Current Balance',
                          style: TextStyle(
                              color: _T.muted2, fontSize: 12)),
                      const Spacer(),
                      Text('₹${_fmtNum(e.openingBalance)}',
                          style: const TextStyle(
                              color: _T.green,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

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
              const SizedBox(height: 24),

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
        color: _T.surface,
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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _T.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header row
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _T.accent.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Client',
                          style: TextStyle(
                              color: _T.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.3)),
                      Text('Add with opening balance',
                          style: TextStyle(
                              color: _T.muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

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
              const SizedBox(height: 24),

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
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: submitting
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                  ),
            color: submitting
                ? _T.accent.withValues(alpha: 0.15)
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: submitting
                ? null
                : [
                    BoxShadow(
                      color: _T.accent.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
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
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: submitting
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white))
                : Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
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
          width: 56, height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _T.accent.withValues(alpha: 0.40),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded,
              color: Colors.white, size: 26),
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
          style: const TextStyle(color: Colors.white, fontSize: 13,
              fontWeight: FontWeight.w600)),
      backgroundColor: success
          ? _T.green.withValues(alpha: 0.95)
          : _T.red.withValues(alpha: 0.95),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
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
          icon != null ? Icon(icon, color: _T.muted, size: 17) : null,
      filled: true,
      fillColor: _T.bg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _T.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _T.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _T.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _T.red, width: 1.5),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
//  Circle avatar — coloured initials
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
            color: colors[0].withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w700,
              fontSize: size * 0.36),
        ),
      ),
    );
  }
}
