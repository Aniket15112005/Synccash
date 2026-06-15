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

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(filteredSaleBillsProvider);

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── Header ─────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 100,
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
              _IconBtn(
                icon: Icons.account_balance_wallet_outlined,
                tooltip: 'Client Balances',
                onTap: () => Navigator.of(context)
                    .push(_slideRoute(const ManageOpeningBalanceScreen())),
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
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 100, 14),
              title: const Text('Sales',
                  style: TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: -0.4)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0C0E18), Color(0xFF080A0E)],
                  ),
                ),
              ),
            ),
          ),

          // ── Search ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: _SearchField(
                controller: _searchCtrl,
                onChanged: (q) =>
                    ref.read(saleBillSearchProvider.notifier).update(q),
                hint: 'Search party or bill…',
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────────
          billsAsync.when(
            data: (bills) {
              if (bills.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(hasSearch: _searchCtrl.text.isNotEmpty),
                );
              }
              final grouped = <String, List<SaleBillEntity>>{};
              for (final b in bills) {
                grouped.putIfAbsent(b.partyName, () => []).add(b);
              }
              final names = grouped.keys.toList();
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                sliver: SliverList.separated(
                  itemCount: names.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _PartyCard(
                    key: ValueKey(names[i]),
                    partyName: names[i],
                    bills:     grouped[names[i]]!,
                    onTap: () => Navigator.of(context).push(
                      _slideRoute(PartyDetailScreen(partyName: names[i])),
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
                      style: const TextStyle(color: _T.red, fontSize: 13),
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
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }

  void _addBill(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AddBillSheet(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party card with reactive streams
// ─────────────────────────────────────────────────────────────────────────────

class _PartyCard extends ConsumerStatefulWidget {
  final String               partyName;
  final List<SaleBillEntity> bills;
  final VoidCallback          onTap;

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

  double _received    = 0.0;
  double _ob          = 0.0;
  String _place       = '';

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
    final fmt         = NumberFormat('#,##,##0.00');
    final totalBills  =
        widget.bills.fold<double>(0.0, (s, b) => s + b.billTotal);
    final outstanding =
        (totalBills - _received).clamp(0.0, double.infinity);
    final settled = outstanding <= 0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1318), Color(0xFF0C1018)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _T.border),
        ),
        child: Row(
          children: [
            _CircleAvatar(name: widget.partyName, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.partyName,
                      style: const TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  if (_place.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: _T.muted, size: 10),
                          const SizedBox(width: 2),
                          Text(_place,
                              style: const TextStyle(
                                  color: _T.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _T.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('OB ₹${_obFmt(_ob)}',
                            style: const TextStyle(
                                color: _T.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                          '${widget.bills.length} bill${widget.bills.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: _T.muted, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${fmt.format(totalBills)}',
                    style: const TextStyle(
                        color: _T.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 5),
                _Pill(
                  label: settled
                      ? 'Settled'
                      : '₹${fmt.format(outstanding)} due',
                  color: settled ? _T.green : _T.amber,
                ),
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
}

String _obFmt(double v) => v == v.truncateToDouble()
    ? v.toStringAsFixed(0)
    : v.toStringAsFixed(2);

// ─────────────────────────────────────────────────────────────────────────────
//  Add bill sheet
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

  @override
  void dispose() {
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
              const Text('New Sale Bill',
                  style: TextStyle(
                      color: _T.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Fill in the bill details below',
                  style: TextStyle(color: _T.muted, fontSize: 12)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _partyCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Party / Client Name',
                    hint: 'e.g. ABC Traders',
                    icon: Icons.business_rounded),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _billNoCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Bill Number',
                    hint: 'e.g. INV-001', icon: Icons.tag_rounded),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
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
              TextFormField(
                controller: _noteCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Note (optional)',
                    hint: 'Any details…', icon: Icons.notes_rounded),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
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
//  Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

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
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
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
          color: color.withValues(alpha: 0.1),
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>  onChanged;
  final String                hint;
  const _SearchField(
      {required this.controller,
      required this.onChanged,
      required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
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
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  })
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
            Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.receipt_long_outlined,
              color: _T.border,
              size: 52,
            ),
            const SizedBox(height: 12),
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
  final IconData icon;
  final String   tooltip;
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
              border:
                  Border.all(color: _T.accent.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: _T.accent, size: 18),
          ),
        ),
      );
}
