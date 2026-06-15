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
//  Theme
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg      = Color(0xFF07080E);
  static const card    = Color(0xFF0C0E18);
  static const card2   = Color(0xFF10121E);
  static const card3   = Color(0xFF141728);
  static const border  = Color(0xFF1A1D2E);
  static const border2 = Color(0xFF23273A);
  static const muted   = Color(0xFF505570);
  static const muted2  = Color(0xFF6B728C);
  static const accent  = Color(0xFF5B72F0);
  static const accent2 = Color(0xFF8299F8);
  static const text    = Color(0xFFECEFF8);
  static const text2   = Color(0xFFB4BCDA);
  static const green   = Color(0xFF2DD98A);
  static const red     = Color(0xFFEC4B6A);
  static const amber   = Color(0xFFF5A623);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated background — drifting gradient orbs + subtle grid
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
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Stack(
          children: [
            Container(color: _T.bg),
            // Orb 1 — top-left, indigo
            Positioned(
              top: -160 + t * 80,
              left: -100 + t * 50,
              child: _GlowOrb(
                size: 380,
                color: const Color(0xFF4A5BE0).withValues(alpha: 0.09),
              ),
            ),
            // Orb 2 — bottom-right, violet
            Positioned(
              bottom: -130 + t * 65,
              right: -90 + t * 30,
              child: _GlowOrb(
                size: 320,
                color: const Color(0xFF7755CC).withValues(alpha: 0.07),
              ),
            ),
            // Orb 3 — mid-right, teal
            Positioned(
              top: 280 - t * 60,
              right: 40 + t * 50,
              child: _GlowOrb(
                size: 220,
                color: const Color(0xFF3A7ACC).withValues(alpha: 0.05),
              ),
            ),
            // Subtle dot-grid overlay
            Positioned.fill(
              child: CustomPaint(painter: _DotGridPainter()),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color  color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      );
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E2240).withValues(alpha: 0.5)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;
    const step = 52.0;
    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter _) => false;
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
                return _SummaryCard(
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
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => _PartyTile(
                      party:    filtered[i],
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
        backgroundColor: _T.card3,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        title: const Text('Remove Client?',
            style: TextStyle(
                color: _T.text,
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        content: Text(
          'This will remove the opening balance record for '
          '"${party.name}". Bills and transactions are not affected.',
          style: const TextStyle(
              color: _T.text2, fontSize: 13, height: 1.5),
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
//  Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onAdd;
  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0B0D1E),
            _T.bg.withValues(alpha: 0.97),
          ],
        ),
        border: Border(
          bottom: BorderSide(
              color: _T.accent.withValues(alpha: 0.07), width: 1),
        ),
      ),
      child: Row(
        children: [
          // ── Back button ─────────────────────────────────────────────────
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: _T.border2.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: _T.border2),
              ),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: _T.muted2, size: 15),
            ),
          ),
          const SizedBox(width: 16),

          // ── Title ────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFFC4CCFF), Color(0xFF8299F8)],
                  ).createShader(b),
                  child: const Text(
                    'Client Balances',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6),
                  ),
                ),
                const SizedBox(height: 1),
                const Text('Manage opening balances',
                    style: TextStyle(
                        color: _T.muted, fontSize: 12)),
              ],
            ),
          ),

          // ── Add button ───────────────────────────────────────────────────
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7D90F5), Color(0xFF4A5ED4)],
                ),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: _T.accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Summary card — revamped with 3 stat columns
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final int    clientCount;
  final int    withOB;
  final double totalOB;
  const _SummaryCard({
    required this.clientCount,
    required this.withOB,
    required this.totalOB,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _T.accent.withValues(alpha: 0.10),
            _T.accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _T.accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: _T.accent.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCol(
              icon:  Icons.people_alt_rounded,
              label: 'Clients',
              value: '$clientCount',
              color: _T.accent2,
            ),
          ),
          _VertDivider(),
          Expanded(
            child: _SummaryCol(
              icon:  Icons.account_balance_wallet_rounded,
              label: 'With Balance',
              value: '$withOB',
              color: _T.green,
            ),
          ),
          _VertDivider(),
          Expanded(
            child: _SummaryCol(
              icon:  Icons.currency_rupee_rounded,
              label: 'Total OB',
              value: _fmtNum(totalOB),
              color: const Color(0xFF2196F3),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCol extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  const _SummaryCol({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(height: 7),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: -0.4)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: _T.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ],
      );
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1, height: 44,
        color: _T.accent.withValues(alpha: 0.10),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party tile  — completely redesigned
// ─────────────────────────────────────────────────────────────────────────────

class _PartyTile extends StatelessWidget {
  final _MergedParty  party;
  final VoidCallback  onTap;
  final VoidCallback  onEdit;
  final VoidCallback? onDelete;

  const _PartyTile({
    required this.party,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasSaved && hasOB
                ? [
                    _T.card2,
                    _T.card,
                  ]
                : [_T.card, _T.card],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasSaved && hasOB
                ? _T.accent.withValues(alpha: 0.20)
                : _T.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: hasSaved && hasOB
                  ? _T.accent.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Avatar ─────────────────────────────────────────────────────
            _CircleAvatar(name: party.name, size: 50),
            const SizedBox(width: 14),

            // ── Info ───────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(party.name,
                      style: const TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.2)),

                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: _T.muted, size: 11),
                        const SizedBox(width: 3),
                        Text(place,
                            style: const TextStyle(
                                color: _T.muted, fontSize: 11)),
                      ],
                    ),
                  ] else if (desc.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _T.muted, fontSize: 11)),
                  ],

                  if (!hasSaved) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _T.accent.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _T.accent.withValues(alpha: 0.14)),
                      ),
                      child: const Text('Tap to set balance',
                          style: TextStyle(
                              color: _T.accent2,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),

            // ── OB amount + actions ────────────────────────────────────────
            if (hasSaved) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasOB) ...[
                    Text(
                      '₹${_fmtNum(ob)}',
                      style: const TextStyle(
                          color: Color(0xFF2196F3),
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 2),
                    const Text('Opening Bal.',
                        style: TextStyle(
                            color: _T.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w500)),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _T.muted.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: _T.border2),
                      ),
                      child: const Text('₹0',
                          style: TextStyle(
                              color: _T.muted2,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionBtn(
                        icon:  Icons.edit_rounded,
                        color: _T.accent,
                        onTap: onEdit,
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 6),
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
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded,
                    color: _T.accent2, size: 14),
              ),
            ],
          ],
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
          width: small ? 26 : 30,
          height: small ? 26 : 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: small ? 0.05 : 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: color.withValues(alpha: small ? 0.12 : 0.22)),
          ),
          child: Icon(icon,
              color: color.withValues(alpha: small ? 0.55 : 1.0),
              size: small ? 12 : 14),
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
            width: 36, height: 36,
            child: CircularProgressIndicator(
              color: _T.accent.withValues(alpha: 0.7),
              strokeWidth: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Loading clients…',
              style:
                  TextStyle(color: _T.muted, fontSize: 12)),
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
                width: 76, height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _T.accent.withValues(alpha: 0.10),
                      _T.accent.withValues(alpha: 0.03),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _T.accent.withValues(alpha: 0.13)),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : Icons.people_alt_outlined,
                  color: _T.accent.withValues(alpha: 0.45),
                  size: 32,
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
              const SizedBox(height: 6),
              Text(
                hasSearch
                    ? 'Try a different search term'
                    : 'Add a client to start tracking\nopening balances',
                style: const TextStyle(
                    color: _T.muted,
                    fontSize: 12,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              if (!hasSearch) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _T.accent.withValues(alpha: 0.15),
                          _T.accent.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _T.accent.withValues(alpha: 0.22)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            color: _T.accent2, size: 16),
                        SizedBox(width: 6),
                        Text('Add First Client',
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
//  FAB
// ─────────────────────────────────────────────────────────────────────────────

class _FAB extends StatelessWidget {
  final VoidCallback onTap;
  const _FAB({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7D90F5), Color(0xFF4A5ED4)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _T.accent.withValues(alpha: 0.40),
                blurRadius: 18,
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
//  Search field
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _SearchField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: const TextStyle(color: _T.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _T.muted, fontSize: 14),
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
          fillColor: _T.card,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _T.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: _T.accent, width: 1.5),
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
        color: _T.card3,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottom),
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
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: _T.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Avatar + name ─────────────────────────────────────────────
              Row(
                children: [
                  _CircleAvatar(name: widget.party.name, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.party.name,
                            style: const TextStyle(
                                color: _T.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                letterSpacing: -0.3)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _T.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: _T.accent.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            e != null
                                ? 'Edit Opening Balance'
                                : 'Set Opening Balance',
                            style: const TextStyle(
                                color: _T.accent2,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Current OB preview ────────────────────────────────────────
              if (e != null && e.openingBalance > 0) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _T.accent.withValues(alpha: 0.08),
                        _T.accent.withValues(alpha: 0.03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _T.accent.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: _T.accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: _T.accent2,
                            size: 15),
                      ),
                      const SizedBox(width: 10),
                      const Text('Current Balance',
                          style: TextStyle(
                              color: _T.muted2, fontSize: 12)),
                      const Spacer(),
                      Text('₹${_fmtNum(e.openingBalance)}',
                          style: const TextStyle(
                              color: Color(0xFF2196F3),
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Form fields ────────────────────────────────────────────────
              TextFormField(
                controller: _obCtrl,
                autofocus: true,
                style: const TextStyle(
                    color: _T.text,
                    fontSize: 16,
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _placeCtrl,
                style: const TextStyle(color: _T.text, fontSize: 14),
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDec(
                    label: 'Place / City (optional)',
                    hint: 'e.g. Mumbai',
                    icon: Icons.location_on_outlined),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: _T.text, fontSize: 14),
                maxLines: 2,
                decoration: _fieldDec(
                    label: 'Description (optional)',
                    hint: 'e.g. Wholesale dealer',
                    icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 24),

              // ── Save button ────────────────────────────────────────────────
              _SaveButton(
                label:       'Save Changes',
                submitting:  _submitting,
                onPressed:   _submitting ? null : _save,
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
        color: _T.card3,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: _T.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header row
              Row(
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF7D90F5), Color(0xFF4A5ED4)],
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
                              fontSize: 18)),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _placeCtrl,
                style: const TextStyle(color: _T.text),
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDec(
                    label: 'Place / City (optional)',
                    hint: 'e.g. Mumbai',
                    icon: Icons.location_on_outlined),
              ),
              const SizedBox(height: 12),
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
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: submitting
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF8299F8), Color(0xFF4A5ED4)],
                  ),
            color: submitting
                ? _T.accent.withValues(alpha: 0.25)
                : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: submitting
                ? null
                : [
                    BoxShadow(
                      color: _T.accent.withValues(alpha: 0.35),
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
                  borderRadius: BorderRadius.circular(16)),
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
          borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );

InputDecoration _fieldDec(
        {required String label, String? hint, IconData? icon}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _T.muted, fontSize: 13),
      hintStyle: const TextStyle(color: _T.muted, fontSize: 13),
      prefixIcon:
          icon != null ? Icon(icon, color: _T.muted, size: 17) : null,
      filled: true,
      fillColor: _T.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _T.border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: _T.accent2, width: 1.5),
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
//  Circle avatar  (shared across both sheets)
// ─────────────────────────────────────────────────────────────────────────────

class _CircleAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _CircleAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final palette = [
      [const Color(0xFF4C6EF5), const Color(0xFF3451D1)],
      [const Color(0xFF7950F2), const Color(0xFF5C3DD8)],
      [const Color(0xFF1C7ED6), const Color(0xFF1465B0)],
      [const Color(0xFF0CA678), const Color(0xFF08845F)],
      [const Color(0xFFE67700), const Color(0xFFC46000)],
      [const Color(0xFFE64980), const Color(0xFFC43468)],
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
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.32),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
