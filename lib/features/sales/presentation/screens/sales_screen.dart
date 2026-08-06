import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/sale_bill_entity.dart';
import '../providers/sale_bill_provider.dart';
import 'manage_opening_balance_screen.dart';
import 'party_detail_screen.dart';
import '../../../../voice/party_nav_mic_button.dart';
import '../providers/party_provider.dart';
import '../../../transactions/presentation/screens/party_picker_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg     = Color(0xFF161616);
  static const card   = Color(0xFF1E1E1E);
  static const card2  = Color(0xFF1E1E1E);
  static const border = Color(0xFF2A2A2A);
  static const muted  = Color(0xFF8A8A8A);
  static const accent = Color(0xFFF2F2F2);
  static const text   = Color(0xFFF2F2F2);
  static const green  = Color(0xFF38D68A);
  static const amber  = Color(0xFFF5A623);
  static const red        = Color(0xFFE85C5C);
  static const darkOrange = Color(0xFFF2F2F2);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth slide + fade page transition
// ─────────────────────────────────────────────────────────────────────────────

Route _slideRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, a, __) => page,
      transitionsBuilder: (_, anim, __, child) {
        final slide = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeIn);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
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
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(saleBillSearchProvider.notifier).update('');
      }
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _addBill(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AddBillSheet(),
      );

  void _onPartyVoiceMatch(List<SaleBillEntity> allBills, String matchedPartyName) {
    HapticFeedback.selectionClick();
    final bills = allBills
        .where((b) =>
            b.partyName.trim().toLowerCase() == matchedPartyName.trim().toLowerCase())
        .toList();
    Navigator.of(context).push(
      _slideRoute(
          PartyDetailScreen(partyName: matchedPartyName, initialBills: bills)),
    );
  }

  void _onPartyVoiceNoMatch(String spokenName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('No party found matching "$spokenName"'),
      backgroundColor: _T.amber,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(filteredSaleBillsProvider);
    final allBillsAsync = ref.watch(allSaleBillsProvider);
    final allBills = allBillsAsync.asData?.value ?? const <SaleBillEntity>[];
    final partyNames = allBills
        .map((b) => b.partyName.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [

          // ── App bar ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            floating: false,
            backgroundColor: _T.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: _T.text, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                      _slideRoute(const ManageOpeningBalanceScreen()));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _T.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _T.border),
                  ),
                  child: const Text('Opening Bal.',
                      style: TextStyle(
                          color: _T.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              if (PartyNavMicButton.isSupportedPlatform)
                PartyNavMicButton(
                  partyNames: partyNames,
                  onPartyMatched: (matched) =>
                      _onPartyVoiceMatch(allBills, matched),
                  onNoMatch: _onPartyVoiceNoMatch,
                ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _addBill(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _T.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('+ Add Bill',
                      style: TextStyle(
                          color: _T.bg,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 16),
            ],
            flexibleSpace: FlexibleSpaceBar(
  titlePadding: const EdgeInsets.fromLTRB(56, 0, 110, 16),
  title: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Sales',
          style: TextStyle(
              color: _T.text,
              fontWeight: FontWeight.w800,
              fontSize: 20,          // ← changed from 22 to 20
              letterSpacing: -0.5)),
      billsAsync.maybeWhen(
                    data: (bills) {
                      final partyCount = bills
                          .map((b) => b.partyName.toLowerCase())
                          .toSet()
                          .length;
                      return Text(
                        '$partyCount client${partyCount == 1 ? '' : 's'}  ·  ${bills.length} bill${bills.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: _T.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w500),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
              background: Container(color: _T.bg),
            ),
          ),

          // ── Search bar ─────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: _SearchBar(
                controller: _searchCtrl,
                onChanged: (q) =>
                    ref.read(saleBillSearchProvider.notifier).update(q),
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────────
          // ── Summary strip ──────────────────────────────────────────────
          if (defaultTargetPlatform == TargetPlatform.iOS)
            const SliverToBoxAdapter(child: _SalesSummaryStrip()),

          billsAsync.when(
            data: (bills) {
              if (bills.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                      hasSearch: _searchCtrl.text.isNotEmpty),
                );
              }

              // Group bills by party name (case-insensitive)
              final grouped  = <String, List<SaleBillEntity>>{};
              final dispName = <String, String>{};
              for (final b in bills) {
                final key = b.partyName.trim().toLowerCase();
                grouped.putIfAbsent(key, () => []).add(b);
                dispName.putIfAbsent(key, () => b.partyName.trim());
              }
              final names = grouped.keys.toList()..sort();

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                sliver: SliverList.separated(
                  itemCount: names.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _PartyCard(
                    key:       ValueKey(names[i]),
                    partyName: dispName[names[i]]!,
                    bills:     grouped[names[i]]!,
                    onTap: () => Navigator.of(context).push(
                      _slideRoute(
                          PartyDetailScreen(
                            partyName:    dispName[names[i]]!,
                            initialBills: grouped[names[i]]!,
                          )),
                    ),
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                    color: _T.accent, strokeWidth: 1.5),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: $e',
                      style:
                          const TextStyle(color: _T.red, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ],
      ),

    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party Card — shows Bill Amt label + bigger highlighted amounts + OB tag
// ─────────────────────────────────────────────────────────────────────────────

class _PartyCard extends ConsumerStatefulWidget {
  final String               partyName;
  final List<SaleBillEntity> bills;
  final VoidCallback         onTap;

  const _PartyCard({
    super.key,
    required this.partyName,
    required this.bills,
    required this.onTap,
  });

  @override
  ConsumerState<_PartyCard> createState() => _PartyCardState();
}

class _PartyCardState extends ConsumerState<_PartyCard> {
  StreamSubscription<QuerySnapshot>?    _txSub;
  StreamSubscription<DocumentSnapshot>? _partySub;
  ProviderSubscription<String?>?        _idSub;
  String?                               _cashbookId;

  double _billReceived = 0.0;
  double _obReceived   = 0.0;
  double _ob           = 0.0;
  String _place    = '';
  String _description = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 80), () {
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
    });
  }

  void _start(String cashbookId) {
    if (!mounted) return;
    final q = widget.partyName.trim().toLowerCase();
    final billIds = widget.bills.map((b) => b.saleBillId).toSet();

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      double billTotal = 0.0;
      double obTotal   = 0.0;
      for (final d in snap.docs) {
        final raw      = d.data();
        final linkedId = raw['linkedSaleBillId'] as String?;
        final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final desc     = (raw['description'] as String? ?? '').toLowerCase();
        if (linkedId != null && linkedId.isNotEmpty) {
          if (billIds.contains(linkedId)) billTotal += amount;
        } else if (desc.contains(q)) {
          obTotal += amount;
        }
      }
      setState(() { _billReceived = billTotal; _obReceived = obTotal; });
    });

    _partySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .doc(q)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists) {
        final d = doc.data() as Map<String, dynamic>;
        setState(() {
          _ob    = (d['openingBalance'] as num?)?.toDouble() ?? 0.0;
          _place = d['place'] as String? ?? '';
          _description = d['description'] as String? ?? '';
        });
      } else {
        setState(() { _ob = 0.0; _place = ''; _description = ''; });
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

  void _showEditSheet(BuildContext context) {
    if (_cashbookId == null) return;
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPartySheet(
        partyName:          widget.partyName,
        cashbookId:         _cashbookId!,
        currentPlace:       _place,
        currentDescription: _description,
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final fmt       = NumberFormat('#,##,##0.##');
    final totalBill = widget.bills
        .fold<double>(0.0, (s, b) => s + b.billTotal);
    final outstanding =
        (totalBill - _billReceived - _obReceived).clamp(0.0, double.infinity);
    final closingBalance = (_ob + totalBill - _billReceived - _obReceived).clamp(0.0, double.infinity);
    final settled = closingBalance <= 0;
    final partial = (_billReceived + _obReceived) > 0 && !settled;
    final statusColor =
        settled ? _T.green : (partial ? _T.amber : _T.red);
    final lastBill = widget.bills.isNotEmpty
        ? widget.bills.reduce(
            (a, b) => a.billCreatedAt.isAfter(b.billCreatedAt) ? a : b)
        : null;
    final dateFmt = DateFormat('dd MMM');

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left status stripe
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),

              // Main content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: avatar + name/tags + closing balance
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GradientAvatar(
                              name: widget.partyName, size: 42),
                          const SizedBox(width: 12),
                          // Name + OB badge + sub-tags
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.partyName,
                                        style: const TextStyle(
                                          color: _T.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          letterSpacing: -0.3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_ob > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _T.bg,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: _T.border),
                                        ),
                                        child: Text(
                                          'OB ₹${fmt.format(_ob)}',
                                          style: const TextStyle(
                                            color: _T.muted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${widget.bills.length} bill'
                                      '${widget.bills.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        color: _T.muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_place.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      const Text('·',
                                          style: TextStyle(
                                              color: _T.muted,
                                              fontSize: 10)),
                                      const SizedBox(width: 6),
                                      Text(_place,
                                          style: const TextStyle(
                                              color: _T.muted,
                                              fontSize: 11)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Right: closing balance + bills/due
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Closing Bal.',
                                style: TextStyle(
                                  color: _T.muted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹${fmt.format(closingBalance)}',
                                style: const TextStyle(
                                  color: _T.darkOrange,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              if (!settled && outstanding > 0) ...[
  const SizedBox(height: 4),
  Text(
    '₹${fmt.format(outstanding)} due',
    style: const TextStyle(
      color: _T.muted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
    textAlign: TextAlign.right,
  ),
],
                            ],
                          ),
                        ],
                      ),
                      // Divider
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 11),
                        color: _T.border.withValues(alpha: 0.8),
                      ),
                      // Bottom row: status pill + date
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5, height: 5,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  settled
                                      ? 'Settled'
                                      : (partial ? 'Partial' : 'Due'),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            tooltip: '',
                            iconSize: 18,
                            icon: Icon(Icons.more_vert_rounded,
                                color: _T.muted.withValues(alpha: 0.5), size: 18),
                            color: _T.card2,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: _T.border),
                            ),
                            onSelected: (v) {
                              if (v == 'edit') _showEditSheet(context);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem<String>(
                                value: 'edit',
                                height: 42,
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit_rounded,
                                        color: _T.text, size: 15),
                                    const SizedBox(width: 10),
                                    const Text('Edit Party',
                                        style: TextStyle(
                                            color: _T.text,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
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
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  Edit Party Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EditPartySheet extends StatefulWidget {
  final String partyName;
  final String cashbookId;
  final String currentPlace;
  final String currentDescription;

  const _EditPartySheet({
    required this.partyName,
    required this.cashbookId,
    required this.currentPlace,
    required this.currentDescription,
  });

  @override
  State<_EditPartySheet> createState() => _EditPartySheetState();
}

class _EditPartySheetState extends State<_EditPartySheet> {
  late final _nameCtrl  = TextEditingController(text: widget.partyName);
  late final _placeCtrl = TextEditingController(text: widget.currentPlace);
  late final _descCtrl  = TextEditingController(text: widget.currentDescription);
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _placeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName  = _nameCtrl.text.trim();
    final newPlace = _placeCtrl.text.trim();
    final newDesc  = _descCtrl.text.trim();
    if (newName.isEmpty) return;
    setState(() => _saving = true);
    try {
      final db     = FirebaseFirestore.instance;
      final oldKey = widget.partyName.trim().toLowerCase();
      final newKey = newName.toLowerCase();
      final batch  = db.batch();

      if (newKey != oldKey) {
        // Party renamed — copy doc to new key, delete old, update all bills
        final oldSnap = await db
            .collection('cashbooks').doc(widget.cashbookId)
            .collection('parties').doc(oldKey).get();
        final data = Map<String, dynamic>.from(
            oldSnap.exists ? (oldSnap.data() ?? {}) : {});
        data['place']       = newPlace;
        data['description'] = newDesc;
        batch.set(
          db.collection('cashbooks').doc(widget.cashbookId)
              .collection('parties').doc(newKey),
          data,
        );
        batch.delete(
          db.collection('cashbooks').doc(widget.cashbookId)
              .collection('parties').doc(oldKey),
        );
        final billsSnap = await db
            .collection('cashbooks').doc(widget.cashbookId)
            .collection('sale_bills')
            .where('partyName', isEqualTo: widget.partyName)
            .get();
        for (final doc in billsSnap.docs) {
          batch.update(doc.reference, {'partyName': newName});
        }
      } else {
        batch.set(
          db.collection('cashbooks').doc(widget.cashbookId)
              .collection('parties').doc(oldKey),
          {'place': newPlace, 'description': newDesc},
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Party updated',
              style: TextStyle(color: Colors.white)),
          backgroundColor: _T.green.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: _T.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141921),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
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
                    color: _T.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _T.border),
                  ),
                  child: const Icon(Icons.business_rounded,
                      color: _T.text, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Edit Party',
                        style: TextStyle(
                            color: _T.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    Text('Update party details',
                        style: TextStyle(
                            color: _T.muted, fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: _T.text),
              textCapitalization: TextCapitalization.words,
              decoration: _fieldDec('Party / Client Name *',
                  icon: Icons.business_rounded),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _placeCtrl,
              style: const TextStyle(color: _T.text),
              textCapitalization: TextCapitalization.words,
              decoration: _fieldDec('Location / Place',
                  hint: 'e.g. Mumbai',
                  icon: Icons.location_on_rounded),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              style: const TextStyle(color: _T.text),
              maxLines: 2,
              decoration: _fieldDec('Note / Description',
                  hint: 'Any details…',
                  icon: Icons.notes_rounded),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _T.accent,
                  foregroundColor: _T.bg,
                  disabledBackgroundColor:
                      _T.accent.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: _T.bg))
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tag chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String    label;
  final Color     color;
  final IconData? icon;
  final bool      filled;
  const _Tag({
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: filled
              ? color.withValues(alpha: 0.10)
              : _T.border.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(5),
          border: filled
              ? Border.all(color: color.withValues(alpha: 0.22))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 9),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

String _shortFmt(double v) {
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
  return v == v.truncateToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Add bill sheet — shows client's opening balance as read-only detail
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

  // Party picker state
  bool _openingPartyPicker = false;
  bool _partyError         = false;

  // Opening balance fetch
  Timer?  _obTimer;
  double? _fetchedOB;
  bool    _obFetching = false;

  // Bill number uniqueness
  String? _billNoError;
  Timer?  _billNoDebounce;

  @override
  void initState() {
    super.initState();
    _partyCtrl.addListener(_onPartyChanged);
    _billNoCtrl.addListener(_onBillNoChanged);
  }

  void _onBillNoChanged() {
    _billNoDebounce?.cancel();
    final value = _billNoCtrl.text.trim();
    if (value.isEmpty) {
      if (mounted && _billNoError != null) setState(() => _billNoError = null);
      return;
    }
    _billNoDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkBillNoUnique(value),
    );
  }

  Future<void> _checkBillNoUnique(String billNo) async {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null || !mounted) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
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

  void _onPartyChanged() {
    _obTimer?.cancel();
    final name = _partyCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) setState(() { _fetchedOB = null; _obFetching = false; _partyError = false; });
      return;
    }
    if (mounted) setState(() { _obFetching = true; _partyError = false; });
    _obTimer = Timer(
      const Duration(milliseconds: 600),
      () => _fetchOB(name),
    );
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

  // Opens the same full-screen party picker used in Add Transaction.
  // The user can search existing parties or type a brand-new name — if new,
  // clicking "Done" confirms it and the bill creation registers them.
  Future<void> _openPartyPicker() async {
    if (_openingPartyPicker) return;
    setState(() { _openingPartyPicker = true; _partyError = false; });

    final namesFuture = _resolvePartyNames();

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyPickerScreen(
          initialValue:        _partyCtrl.text,
          allPartyNamesFuture: namesFuture,
          canSuggest:          true,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _openingPartyPicker = false);

    if (result != null) {
      _partyCtrl.removeListener(_onPartyChanged);
      _partyCtrl.text = result;
      _partyCtrl.addListener(_onPartyChanged);
      if (result.trim().isNotEmpty) _onPartyChanged();
      setState(() {});
    }
  }

  // Collects known party names from the saved parties collection and from
  // existing sale bills so the picker can suggest them as the user types.
  Future<List<String>> _resolvePartyNames() async {
    List<PartyEntity> savedParties =
        ref.read(partiesProvider).asData?.value ?? [];
    List<SaleBillEntity> allBills =
        ref.read(allSaleBillsProvider).asData?.value ?? [];

    if (savedParties.isEmpty) {
      try {
        savedParties = await ref
            .read(partiesProvider.future)
            .timeout(const Duration(seconds: 3));
      } catch (_) { savedParties = []; }
    }
    if (allBills.isEmpty) {
      try {
        allBills = await ref
            .read(allSaleBillsProvider.future)
            .timeout(const Duration(seconds: 3));
      } catch (_) { allBills = []; }
    }

    return <String>{
      ...savedParties.map((p) => p.partyName),
      ...allBills.map((b) => b.partyName.trim()),
    }.toList()..sort();
  }

  @override
  void dispose() {
    _obTimer?.cancel();
    _billNoDebounce?.cancel();
    _partyCtrl.removeListener(_onPartyChanged);
    _billNoCtrl.removeListener(_onBillNoChanged);
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
            onPrimary: _T.bg,
            surface: _T.card2,
            onSurface: _T.text,
          ),
          dialogTheme: const DialogThemeData(
              backgroundColor: _T.bg),
        ),
        child: child!,
      ),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _submit() async {
    // Validate party name separately since it uses a custom tappable widget.
    if (_partyCtrl.text.trim().isEmpty) {
      setState(() => _partyError = true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_billNoError != null) return;
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmtOB(double v) => v == v.truncateToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final bottom  = MediaQuery.of(context).viewInsets.bottom;
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      decoration: const BoxDecoration(
        color: _T.card2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + bottom),
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
                    color: _T.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _T.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _T.accent.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: _T.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Sale Bill',
                          style: TextStyle(
                              color: _T.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      Text('Fill in the bill details below',
                          style: TextStyle(
                              color: _T.muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Party name — tappable field that opens the full-screen party
              // picker. The user can search existing parties or type a new
              // name; clicking "Done" confirms it. Matches the behaviour of
              // the Description field in Add Transaction.
              GestureDetector(
                onTap: _openPartyPicker,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _T.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _partyError
                          ? _T.red
                          : _partyCtrl.text.isNotEmpty
                              ? _T.accent.withValues(alpha: 0.4)
                              : _T.border,
                      width: _partyError ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.business_rounded,
                          color: _partyError ? _T.red : _T.muted,
                          size: 17),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _partyCtrl.text.isEmpty
                            ? Text(
                                'Party / Client Name *',
                                style: TextStyle(
                                  color: _partyError ? _T.red : _T.muted,
                                  fontSize: 13,
                                ),
                              )
                            : Text(
                                _partyCtrl.text,
                                style: const TextStyle(
                                  color: _T.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      if (_openingPartyPicker)
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: _T.accent),
                        )
                      else
                        const Icon(Icons.chevron_right_rounded,
                            color: _T.muted, size: 18),
                    ],
                  ),
                ),
              ),
              if (_partyError && _partyCtrl.text.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 16),
                  child: Text('Required',
                      style: TextStyle(color: _T.red, fontSize: 11)),
                ),

              // Opening balance display — read-only, appears after party name typed
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _obFetching
                    ? Padding(
                        key: const ValueKey('loading'),
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: _T.accent),
                            ),
                            const SizedBox(width: 8),
                            Text('Fetching opening balance…',
                                style: TextStyle(
                                    color: _T.muted.withValues(alpha: 0.7),
                                    fontSize: 11)),
                          ],
                        ),
                      )
                    : _fetchedOB != null
                        ? Container(
                            key: const ValueKey('ob'),
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: _T.accent.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _T.accent.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: _T.accent,
                                    size: 15),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Opening Balance',
                                          style: TextStyle(
                                              color: _T.muted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500)),
                                      SizedBox(height: 1),
                                      Text('Read-only · Edit via Client Balances',
                                          style: TextStyle(
                                              color: _T.muted,
                                              fontSize: 9.5)),
                                    ],
                                  ),
                                ),
                                Text(
                                  _fetchedOB! == 0.0
                                      ? 'Not set'
                                      : '₹${_fmtOB(_fetchedOB!)}',
                                  style: TextStyle(
                                      color: _fetchedOB! == 0.0
                                          ? _T.muted
                                          : _T.accent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
              ),
              const SizedBox(height: 12),

              // Bill number
              TextFormField(
                controller: _billNoCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Bill Number',
                    hint: 'e.g. INV-001', icon: Icons.tag_rounded).copyWith(
                  errorText: _billNoError,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Bill total
              TextFormField(
                controller: _totalCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Bill Total (₹)',
                    hint: '0.00',
                    icon: Icons.currency_rupee_rounded),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Date picker
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _T.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _T.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: _T.muted, size: 15),
                      const SizedBox(width: 10),
                      Text(dateFmt.format(_date),
                          style: const TextStyle(
                              color: _T.text, fontSize: 14)),
                      const Spacer(),
                      const Icon(Icons.expand_more_rounded,
                          color: _T.muted, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Note
              TextFormField(
                controller: _noteCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Note (optional)',
                    hint: 'Any details…', icon: Icons.notes_rounded),
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.accent,
                    foregroundColor: _T.bg,
                    disabledBackgroundColor:
                        _T.accent.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: _T.bg))
                      : const Text('Save Bill',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _fieldDec(String label,
        {String? hint, IconData? icon}) =>
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
//  Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Gradient rounded-rectangle avatar
// ─────────────────────────────────────────────────────────────────────────────

class _GradientAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _GradientAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _T.border,
        borderRadius: BorderRadius.circular(size * 0.30),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: _T.text,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.40,
          ),
        ),
      ),
    );
  }
}

class _CircleAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _CircleAvatar({required this.name, required this.size});

  @override
  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF3D5A8A),
      Color(0xFF4A7A6E),
      Color(0xFF7A5A8A),
      Color(0xFF8A6A3D),
      Color(0xFF4A6A7A),
    ];
    final c = colors[name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0];
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.40,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  Sales Summary Strip
//  Key design decisions:
//    • Caches raw Firestore tx docs in _rawTxs so _computeReceived() can
//      run synchronously any time bills update (fixes timing race).
//    • Per-party clamp: max(0, OB+Bills-Received) — matches party cards.
//    • Received is DERIVED as BillAmt−Closing (always consistent).
//    • Party doc IDs in Firestore == partyName.trim().toLowerCase().
// ════════════════════════════════════════════════════════════════════════

class _SalesSummaryStrip extends ConsumerStatefulWidget {
  const _SalesSummaryStrip();
  @override
  ConsumerState<_SalesSummaryStrip> createState() => _SalesSummaryStripState();
}

class _SalesSummaryStripState extends ConsumerState<_SalesSummaryStrip> {
  StreamSubscription<QuerySnapshot>? _txSub;
  StreamSubscription<QuerySnapshot>? _obSub;
  String? _cashbookId;

  // Bill groupings — rebuilt from allSaleBillsProvider on each build
  Map<String, Set<String>> _partyBillIds = {}; // partyKey -> {billId,...}
  Map<String, double>      _partyBillTot = {}; // partyKey -> sum(billTotal)

  // Raw income tx cache — updated by Firestore stream
  List<Map<String, dynamic>> _rawTxs = [];

  // Per-party received — recomputed whenever bills OR txs change
  Map<String, double> _partyReceived = {};

  // Per-party OB (Firestore parties collection, doc.id == partyKey)
  Map<String, double> _partyOB = {};

  void _startStreams(String cashbookId) {
    _txSub?.cancel();
    _obSub?.cancel();

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      _rawTxs = snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
      setState(() => _partyReceived = _computeReceived());
    });

    _obSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final ob = <String, double>{};
      for (final d in snap.docs) {
        ob[d.id] = ((d.data() as Map<String, dynamic>)['openingBalance']
                as num?)
            ?.toDouble() ??
            0.0;
      }
      setState(() => _partyOB = ob);
    });
  }

  // Compute per-party received from cached raw docs + current bill groupings.
  // Called synchronously from build (no setState) or from stream (with setState).
  Map<String, double> _computeReceived() {
    final rec = <String, double>{};
    for (final raw in _rawTxs) {
      final linkedId = raw['linkedSaleBillId'] as String?;
      final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
      final desc     = (raw['description'] as String? ?? '').toLowerCase();

      if (linkedId != null && linkedId.isNotEmpty) {
        // Bill-linked: attribute to the party that owns this bill
        for (final e in _partyBillIds.entries) {
          if (e.value.contains(linkedId)) {
            rec[e.key] = (rec[e.key] ?? 0) + amount;
            break;
          }
        }
      } else {
        // Unlinked: same description-match used by each party card
        for (final key in _partyBillIds.keys) {
          if (desc.contains(key)) {
            rec[key] = (rec[key] ?? 0) + amount;
          }
        }
      }
    }
    return rec;
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _obSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    final billsAsync = ref.watch(filteredSaleBillsProvider);
    final bills      = billsAsync.asData?.value ?? [];

    // Start / restart streams when cashbook changes
    if (cashbookId != null && cashbookId.isNotEmpty &&
        cashbookId != _cashbookId) {
      _cashbookId = cashbookId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startStreams(cashbookId);
      });
    }

    // Rebuild bill groupings synchronously — always up-to-date for this frame
    _partyBillIds = {};
    _partyBillTot = {};
    for (final b in bills) {
      final key = b.partyName.trim().toLowerCase();
      (_partyBillIds[key] ??= {}).add(b.saleBillId);
      _partyBillTot[key] = (_partyBillTot[key] ?? 0) + b.billTotal;
    }
    // Also recompute received with the fresh bill groupings
    // (no setState — we're already in build; the result is used immediately)
    _partyReceived = _computeReceived();

    if (bills.isEmpty && billsAsync.isLoading) return const SizedBox.shrink();

    // Sum per-party closing with per-party clamp (matches party card logic)
    double totalBillAmt = 0;
    double totalClosing = 0;
    for (final key in _partyBillIds.keys) {
      final pBills    = _partyBillTot[key]  ?? 0;
      final pOB       = _partyOB[key]        ?? 0;
      final pReceived = _partyReceived[key]   ?? 0;
      totalBillAmt += pOB + pBills;
      totalClosing +=
          (pOB + pBills - pReceived).clamp(0.0, double.infinity);
    }

    // Derived: keeps the three numbers always consistent
    final displayReceived =
        (totalBillAmt - totalClosing).clamp(0.0, double.infinity);
    final fmt = NumberFormat('#,##,##0.##');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.border),
      ),
      child: Row(
        children: [
          _SummaryCell(
            label: 'Bill Amt',
            value: '₹${fmt.format(totalBillAmt)}',
            color: _T.text,
          ),
          _SummaryDivider(),
          _SummaryCell(
            label: 'Received',
            value: '₹${fmt.format(displayReceived)}',
            color: _T.green,
          ),
          _SummaryDivider(),
          _SummaryCell(
            label: 'Closing Bal.',
            value: '₹${fmt.format(totalClosing)}',
            color: _T.darkOrange,
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _T.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: _T.border,
  );
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>  onChanged;
  const _SearchBar(
      {required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: _T.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search party or bill…',
          hintStyle: const TextStyle(color: _T.muted, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded,
              color: _T.muted, size: 18),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: _T.muted, size: 16),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: _T.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _T.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _T.accent, width: 1.5),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: _T.border,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearch
                    ? Icons.search_off_rounded
                    : Icons.receipt_long_outlined,
                color: _T.muted,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasSearch ? 'No results found' : 'No sale bills yet',
              style: const TextStyle(
                  color: _T.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (!hasSearch)
              const Text('Tap New Bill to get started',
                  style: TextStyle(color: _T.muted, fontSize: 13)),
          ],
        ),
      );
}

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final String       tooltip;
  final VoidCallback onTap;
  const _IconBtn(
      {required this.icon,
      required this.tooltip,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _T.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _T.accent.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: _T.accent, size: 18),
          ),
        ),
      );
}