import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../providers/party_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme constants
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg      = Color(0xFF080A0E);
  static const card    = Color(0xFF0F1318);
  static const card2   = Color(0xFF141921);
  static const border  = Color(0xFF1C2130);
  static const muted   = Color(0xFF4A5568);
  static const accent  = Color(0xFF6C7FE4);
  static const accentD = Color(0xFF3D51C4);
  static const text    = Color(0xFFE8ECF4);
  static const green   = Color(0xFF38D68A);
  static const red     = Color(0xFFE85C5C);
  static const amber   = Color(0xFFF5A623);
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
        title: const Text('Client Balances',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _IconBtn(
              icon: Icons.person_add_alt_1_rounded,
              onTap: _openCreate,
              tooltip: 'Add Client',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Summary header ─────────────────────────────────────────────────
          partiesAsync.maybeWhen(
            data: (parties) {
              if (parties.isEmpty) return const SizedBox.shrink();
              final totalOB = parties.fold<double>(
                  0.0, (s, p) => s + p.openingBalance);
              return _SummaryHeader(
                clientCount: parties.length,
                totalOB: totalOB,
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),

          // ── Search ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: _SearchField(
              controller: _searchCtrl,
              hint: 'Search clients…',
            ),
          ),

          // ── List ──────────────────────────────────────────────────────────
          Expanded(
            child: partiesAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: _T.accent, strokeWidth: 1.5),
              ),
              error: (e, _) => _ErrorMsg(message: e.toString()),
              data: (savedParties) {
                final merged   = _mergeParties(savedParties);
                final q        = _query.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? merged
                    : merged
                        .where((p) => p.name.toLowerCase().contains(q))
                        .toList();

                if (filtered.isEmpty) {
                  return _EmptyState(
                    hasSearch: q.isNotEmpty,
                    query: _query,
                    onAdd: _openCreate,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _PartyTile(
                    party: filtered[i],
                    onTap: () => _openEdit(filtered[i]),
                    onEdit: () => _openEdit(filtered[i]),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        backgroundColor: _T.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.add_rounded, size: 22),
      ),
    );
  }

  void _confirmDelete(_MergedParty party) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Client?',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'This will remove the opening balance record for "${party.name}". '
          'Bills and transactions are not affected.',
          style: const TextStyle(color: _T.muted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: _T.muted)),
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
                    _snackBar('Opening balance removed', success: true),
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
                    color: _T.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Merged model ──────────────────────────────────────────────────────────────

class _MergedParty {
  final String       name;
  final PartyEntity? entity;
  const _MergedParty({required this.name, required this.entity});
}

// ── Summary header ────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final int    clientCount;
  final double totalOB;
  const _SummaryHeader({required this.clientCount, required this.totalOB});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111828), Color(0xFF0D1120)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              label: 'Total Clients',
              value: '$clientCount',
              icon: Icons.people_alt_rounded,
              color: _T.accent,
            ),
          ),
          Container(width: 1, height: 36, color: _T.border),
          Expanded(
            child: _StatChip(
              label: 'Total OB',
              value: '₹${_fmtNum(totalOB)}',
              icon: Icons.account_balance_wallet_rounded,
              color: _T.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: _T.muted.withValues(alpha: 0.8), fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: -0.3)),
        ],
      );
}

// ── Party tile ────────────────────────────────────────────────────────────────

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
    final place    = party.entity?.place ?? '';
    final desc     = party.entity?.description ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasSaved
                ? _T.accent.withValues(alpha: 0.12)
                : _T.border,
          ),
        ),
        child: Row(
          children: [
            _CircleAvatar(name: party.name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(party.name,
                      style: const TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  if (place.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: _T.muted, size: 10),
                          const SizedBox(width: 3),
                          Text(place,
                              style: const TextStyle(
                                  color: _T.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                  if (desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _T.muted.withValues(alpha: 0.7),
                              fontSize: 11)),
                    ),
                  if (!hasSaved)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _T.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _T.accent.withValues(alpha: 0.18)),
                        ),
                        child: const Text('Tap to set opening balance',
                            style: TextStyle(
                                color: _T.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                ],
              ),
            ),
            if (hasSaved) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${_fmtNum(ob)}',
                      style: const TextStyle(
                          color: _T.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  const Text('Opening Bal.',
                      style: TextStyle(color: _T.muted, fontSize: 9)),
                ],
              ),
              const SizedBox(width: 6),
              // Edit button for saved parties
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.edit_rounded,
                      color: _T.accent.withValues(alpha: 0.55), size: 15),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 2),
                GestureDetector(
                  onTap: onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline_rounded,
                        color: _T.muted.withValues(alpha: 0.4), size: 15),
                  ),
                ),
              ],
            ] else ...[
              Icon(Icons.edit_outlined,
                  color: _T.muted.withValues(alpha: 0.4), size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _T.accent.withValues(alpha: 0.12)),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : Icons.people_alt_outlined,
                  color: _T.accent.withValues(alpha: 0.5),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasSearch
                    ? 'No clients match "$query"'
                    : 'No clients yet',
                style: const TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                hasSearch
                    ? 'Try a different search term'
                    : 'Add a client to track their opening balance',
                style: const TextStyle(color: _T.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              if (!hasSearch) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _T.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _T.accent.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: _T.accent, size: 16),
                        SizedBox(width: 6),
                        Text('Add First Client',
                            style: TextStyle(
                                color: _T.accent,
                                fontWeight: FontWeight.w600,
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

// ── Edit Opening Balance sheet ────────────────────────────────────────────────

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

  String _obText(double v) {
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

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
      _showSnack('Session expired. Please restart the app.', success: false);
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
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          _snackBar('Opening balance updated', success: true),
        );
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save: $e', success: false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      _snackBar(msg, success: success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final e      = widget.party.entity;
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

              // Party identity row
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
                                fontSize: 18,
                                letterSpacing: -0.2)),
                        const SizedBox(height: 2),
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
                      const Text('Current Opening Balance',
                          style: TextStyle(color: _T.muted, fontSize: 12)),
                      const Spacer(),
                      Text('₹${_fmtNum(e.openingBalance)}',
                          style: const TextStyle(
                              color: _T.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // OB input
              TextFormField(
                controller: _obCtrl,
                autofocus: true,
                style: const TextStyle(
                    color: _T.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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

              // Place input
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

              // Description input
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: _T.text, fontSize: 14),
                maxLines: 2,
                decoration: _fieldDec(
                    label: 'Description (optional)',
                    hint: 'e.g. Wholesale dealer',
                    icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 22),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
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
                      : const Text('Save Changes',
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

// ── New Party sheet ───────────────────────────────────────────────────────────

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
      _showSnack('Session expired. Please restart the app.', success: false);
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
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          _snackBar('Client added successfully', success: true),
        );
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save: $e', success: false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      _snackBar(msg, success: success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
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
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: _T.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Client',
                          style: TextStyle(
                              color: _T.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 18)),
                      Text('Add with opening balance',
                          style:
                              TextStyle(color: _T.muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Name
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

              // Opening Balance
              TextFormField(
                controller: _obCtrl,
                style: const TextStyle(color: _T.text),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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

              // Place
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

              // Description
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

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
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
                      : const Text('Add Client',
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

// ── Shared helpers ────────────────────────────────────────────────────────────

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

// ── Shared widgets ────────────────────────────────────────────────────────────

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
      const Color(0xFFE64980),
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
        border:
            Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
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

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  final String?      tooltip;
  const _IconBtn(
      {required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _T.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _T.accent.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: _T.accent, size: 20),
          ),
        ),
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _T.red.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: _T.red, size: 28),
              ),
              const SizedBox(height: 12),
              const Text('Something went wrong',
                  style: TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const SizedBox(height: 6),
              Text(message,
                  style: const TextStyle(color: _T.muted, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
