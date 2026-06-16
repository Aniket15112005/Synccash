import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/sale_bill_entity.dart';
import '../providers/sale_bill_provider.dart';
import 'manage_opening_balance_screen.dart';
import 'party_detail_screen.dart';

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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _addBill(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AddBillSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(filteredSaleBillsProvider);

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
              _IconBtn(
                icon: Icons.account_balance_wallet_outlined,
                tooltip: 'Client Balances',
                onTap: () => Navigator.of(context).push(
                  _slideRoute(const ManageOpeningBalanceScreen()),
                ),
              ),
              const SizedBox(width: 8),
              _IconBtn(
                icon: Icons.add_rounded,
                tooltip: 'New Bill',
                onTap: () => _addBill(context),
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
                          fontSize: 22,
                          letterSpacing: -0.5)),
                  billsAsync.maybeWhen(
                    data: (bills) {
                      final partyCount = bills
                          .map((b) => b.partyName)
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
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D0F1C), Color(0xFF080A0E)],
                  ),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Icon(Icons.receipt_long_rounded,
                        size: 90,
                        color:
                            _T.accent.withValues(alpha: 0.04)),
                  ),
                ),
              ),
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
          billsAsync.when(
            data: (bills) {
              if (bills.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                      hasSearch: _searchCtrl.text.isNotEmpty),
                );
              }

              // Group bills by party name
              final grouped = <String, List<SaleBillEntity>>{};
              for (final b in bills) {
                grouped.putIfAbsent(b.partyName, () => []).add(b);
              }
              final names = grouped.keys.toList();

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                sliver: SliverList.separated(
                  itemCount: names.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _PartyCard(
                    key:       ValueKey(names[i]),
                    partyName: names[i],
                    bills:     grouped[names[i]]!,
                    onTap: () => Navigator.of(context).push(
                      _slideRoute(
                          PartyDetailScreen(partyName: names[i])),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addBill(context),
        backgroundColor: _T.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('New Bill',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
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

  double _received = 0.0;
  double _ob       = 0.0;
  String _place    = '';

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
    final q = widget.partyName.trim().toLowerCase();

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      double total = 0.0;
      for (final d in snap.docs) {
        final desc = (d['description'] as String? ?? '').toLowerCase();
        if (desc.contains(q)) {
          total += (d['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      setState(() => _received = total);
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

  @override
  Widget build(BuildContext context) {
    final fmt       = NumberFormat('#,##,##0.00');
    final totalBill = widget.bills
        .fold<double>(0.0, (s, b) => s + b.billTotal);
    final outstanding =
        (totalBill - _received).clamp(0.0, double.infinity);
    final settled = outstanding <= 0;
    final partial = _received > 0 && outstanding > 0;

    final statusColor =
        settled ? _T.green : (partial ? _T.amber : _T.red);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _T.card,
              const Color(0xFF0C0E16),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _T.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Avatar ──────────────────────────────────────────────────
            _CircleAvatar(name: widget.partyName, size: 46),
            const SizedBox(width: 12),

            // ── Left info ────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.partyName,
                      style: const TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          letterSpacing: -0.1)),
                  if (_place.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: _T.muted, size: 10),
                        const SizedBox(width: 2),
                        Text(_place,
                            style: const TextStyle(
                                color: _T.muted, fontSize: 11)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _T.border,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${widget.bills.length} bill${widget.bills.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: _T.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (_ob > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _T.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: _T.accent.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            'OB ₹${_shortFmt(_ob)}',
                            style: const TextStyle(
                                color: _T.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── Right amounts (highlighted) ──────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Label
                const Text('Bill Amt',
                    style: TextStyle(
                        color: _T.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2)),
                const SizedBox(height: 3),
                // Bill total — larger, bright
                Text(
                  '₹${fmt.format(totalBill)}',
                  style: const TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                // Remaining — color-coded, prominent
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    settled
                        ? '✓ Settled'
                        : '₹${fmt.format(outstanding)} due',
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                color: _T.muted.withValues(alpha: 0.3), size: 16),
          ],
        ),
      ),
    );
  }
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

  // Opening balance fetch
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
            surface: Color(0xFF141921),
            onSurface: _T.text,
          ),
          dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF080A0E)),
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

              // Party name field
              TextFormField(
                controller: _partyCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Party / Client Name *',
                    hint: 'e.g. ABC Traders',
                    icon: Icons.business_rounded),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                    hint: 'e.g. INV-001', icon: Icons.tag_rounded),
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
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        _T.accent.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
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

class _CircleAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _CircleAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = [
      [const Color(0xFF4C6EF5), const Color(0xFF3451D1)],
      [const Color(0xFF7950F2), const Color(0xFF5C3DD8)],
      [const Color(0xFF1C7ED6), const Color(0xFF1465B0)],
      [const Color(0xFF0CA678), const Color(0xFF08845F)],
      [const Color(0xFFE67700), const Color(0xFFC46000)],
    ];
    final idx = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors[idx],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colors[idx][0].withValues(alpha: 0.25),
            blurRadius: 8,
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
