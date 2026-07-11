// lib/features/bills/presentation/screens/bills_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../data/models/custom_bill_model.dart';
import '../providers/bills_provider.dart';
import 'create_bill_screen.dart';

import 'package:synccash/features/sales/presentation/screens/web_invoice_viewer_stub.dart'
    if (dart.library.html) 'package:synccash/features/sales/presentation/screens/web_invoice_viewer_web.dart';
import 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_stub.dart'
    if (dart.library.io) 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_native.dart';

// ── Theme ─────────────────────────────────────────────────────────────────────

class _T {
  static const bg      = Color(0xFF080A0E);
  static const card    = Color(0xFF0F1318);
  static const card2   = Color(0xFF141921);
  static const border  = Color(0xFF1C2130);
  static const muted   = Color(0xFF4A5568);
  static const muted2  = Color(0xFF8C8E9A);
  static const accent  = Color(0xFF6C7FE4);
  static const text    = Color(0xFFE8ECF4);
  static const green   = Color(0xFF38D68A);
  static const amber   = Color(0xFFF5A623);
  static const red     = Color(0xFFE85C5C);
}

// ── Route helper ──────────────────────────────────────────────────────────────

Route billsRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, a, __) => page,
      transitionsBuilder: (_, anim, __, child) {
        final slide = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
          child: SlideTransition(position: slide, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
    );

// ── Screen ────────────────────────────────────────────────────────────────────

class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _search = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openCreate() {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => const CreateBillScreen(),
        transitionsBuilder: (_, anim, __, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 1.0),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
          return SlideTransition(position: slide, child: child);
        },
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }

  void _openPdf(CustomBillModel bill) {
    if (bill.pdfUrl == null || bill.pdfUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('PDF not available for this bill'),
          backgroundColor: _T.amber,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
      return;
    }
    HapticFeedback.selectionClick();
    if (kIsWeb) {
      openPdfInApp(context, bill.pdfUrl!, bill.billNumber, bill.clientName);
    } else {
      openNativePdfInApp(
          context, bill.pdfUrl!, bill.billNumber, bill.clientName);
    }
  }

  Future<void> _deleteBill(CustomBillModel bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Bill',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700)),
        content: Text(
          'Delete bill #${bill.billNumber} for ${bill.clientName}?\nThis cannot be undone.',
          style: const TextStyle(color: _T.muted2, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: _T.muted2)),
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
    if (confirmed != true || !mounted) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    await ref
        .read(customBillActionsProvider.notifier)
        .deleteBill(cashbookId: cashbookId, billId: bill.billId);
  }

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(customBillsStreamProvider);
    final amtFmt  = NumberFormat('#,##,##0.00', 'en_IN');
    final dateFmt = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: _T.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  // Back
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: _T.text, size: 18),
                  ),
                  const SizedBox(width: 2),
                  const Expanded(
                    child: Text(
                      'Bills',
                      style: TextStyle(
                        color: _T.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  // New bill button
                  GestureDetector(
                    onTap: _openCreate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _T.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded,
                              color: Colors.white, size: 16),
                          SizedBox(width: 5),
                          Text('New',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Search ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: _T.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by client or bill number…',
                  hintStyle: TextStyle(
                      color: _T.muted.withValues(alpha: 0.7),
                      fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: _T.muted, size: 18),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: _T.muted, size: 16),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: _T.card,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _T.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _T.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: _T.accent.withValues(alpha: 0.45)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── List ─────────────────────────────────────────────────────────
            Expanded(
              child: billsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: _T.accent, strokeWidth: 2),
                ),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: _T.red)),
                ),
                data: (bills) {
                  final filtered = _search.isEmpty
                      ? bills
                      : bills
                          .where((b) =>
                              b.clientName
                                  .toLowerCase()
                                  .contains(_search) ||
                              b.billNumber
                                  .toLowerCase()
                                  .contains(_search))
                          .toList();

                  if (filtered.isEmpty) {
                    return _EmptyState(
                      hasSearch: _search.isNotEmpty,
                      onCreateTap: _openCreate,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    physics: const BouncingScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 1),
                    itemBuilder: (ctx, i) {
                      final bill = filtered[i];
                      return _BillRow(
                        bill: bill,
                        amtFmt: amtFmt,
                        dateFmt: dateFmt,
                        isFirst: i == 0,
                        isLast: i == filtered.length - 1,
                        onTap: () => _openPdf(bill),
                        onDelete: () => _deleteBill(bill),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // ── FAB ───────────────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        backgroundColor: _T.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add_rounded, size: 26),
      ),
    );
  }
}

// ── Bill Row ──────────────────────────────────────────────────────────────────

class _BillRow extends StatelessWidget {
  final CustomBillModel bill;
  final NumberFormat amtFmt;
  final DateFormat dateFmt;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BillRow({
    required this.bill,
    required this.amtFmt,
    required this.dateFmt,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Rounded corners only on first and last to give a grouped-list feel
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );

    // Initials avatar
    final initials = bill.clientName.trim().isNotEmpty
        ? bill.clientName.trim()[0].toUpperCase()
        : '#';

    return Material(
      color: _T.card,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: _T.accent.withValues(alpha: 0.06),
        highlightColor: _T.accent.withValues(alpha: 0.03),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border(
              left: isFirst
                  ? const BorderSide(color: _T.border)
                  : BorderSide.none,
              right: const BorderSide(color: _T.border),
              top: isFirst
                  ? const BorderSide(color: _T.border)
                  : BorderSide.none,
              bottom: const BorderSide(color: _T.border),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: _T.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),

              // Client name + bill number
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.clientName.isEmpty
                          ? 'Unknown Client'
                          : bill.clientName,
                      style: const TextStyle(
                        color: _T.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'Bill #${bill.billNumber}',
                          style: const TextStyle(
                              color: _T.muted2, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: _T.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateFmt.format(bill.billDate),
                          style: const TextStyle(
                              color: _T.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Amount + delete
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${amtFmt.format(bill.grandTotal)}',
                    style: const TextStyle(
                      color: _T.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onDelete,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.delete_outline_rounded,
                          color: _T.muted, size: 16),
                    ),
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

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onCreateTap;

  const _EmptyState(
      {required this.hasSearch, required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: _T.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border:
                    Border.all(color: _T.accent.withValues(alpha: 0.15)),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: _T.accent, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              hasSearch ? 'No bills found' : 'No bills yet',
              style: const TextStyle(
                  color: _T.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch
                  ? 'Try a different search term'
                  : 'Tap + to create your first bill',
              style: const TextStyle(color: _T.muted2, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onCreateTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    color: _T.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Create Bill',
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
}
