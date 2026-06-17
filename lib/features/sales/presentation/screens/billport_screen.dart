// lib/features/sales/presentation/screens/billport_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/sale_bill_entity.dart';
import '../providers/party_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens  (dark theme matching sales_screen)
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg      = Color(0xFF080A0E);
  static const card    = Color(0xFF0F1318);
  static const card2   = Color(0xFF141921);
  static const border  = Color(0xFF1C2130);
  static const muted   = Color(0xFF4A5568);
  static const muted2  = Color(0xFF8C8E9A);
  static const accent  = Color(0xFF6C7FE4);
  static const accent2 = Color(0xFF8B5CF6);
  static const text    = Color(0xFFE8ECF4);
  static const green   = Color(0xFF38D68A);
  static const amber   = Color(0xFFF5A623);
  static const red     = Color(0xFFE85C5C);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Date-range filter
// ─────────────────────────────────────────────────────────────────────────────

enum _BpFilter { week, month, year, all, custom }

extension _BpFilterX on _BpFilter {
  String get label {
    switch (this) {
      case _BpFilter.week:   return 'This Week';
      case _BpFilter.month:  return 'This Month';
      case _BpFilter.year:   return 'This Year';
      case _BpFilter.all:    return 'All Time';
      case _BpFilter.custom: return 'Custom';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────────────────────────────────────

class _BillData {
  final SaleBillEntity bill;
  final double received;
  final DateTime? firstPayDate;
  final List<_PayEntry> payments;

  const _BillData({
    required this.bill,
    required this.received,
    this.firstPayDate,
    this.payments = const [],
  });

  double get balance =>
      (bill.billTotal - received).clamp(0.0, double.infinity);
  bool get isCleared => balance <= 0;
}

class _PayEntry {
  final double   amount;
  final DateTime date;
  const _PayEntry({required this.amount, required this.date});
}

class _PartyExportData {
  final String         name;
  final List<_BillData> bills;
  final double          openingBalance;

  const _PartyExportData({
    required this.name,
    required this.bills,
    this.openingBalance = 0.0,
  });

  double get totalBilled   =>
      bills.fold(0.0, (s, b) => s + b.bill.billTotal) + openingBalance;
  double get totalReceived => bills.fold(0.0, (s, b) => s + b.received);
  double get totalBalance  =>
      (totalBilled - totalReceived).clamp(0.0, double.infinity);
}

// ─────────────────────────────────────────────────────────────────────────────
//  BillportScreen
// ─────────────────────────────────────────────────────────────────────────────

class BillportScreen extends ConsumerStatefulWidget {
  const BillportScreen({super.key});

  @override
  ConsumerState<BillportScreen> createState() => _BillportScreenState();
}

class _BillportScreenState extends ConsumerState<BillportScreen> {
  // ── Party state ─────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<String> _allPartyNames = [];
  final Set<String> _selected = {};

  // ── Firestore ────────────────────────────────────────────────────────────
  String?                            _cashbookId;
  ProviderSubscription<String?>?     _idSub;
  StreamSubscription<QuerySnapshot>? _billsPartySub;
  StreamSubscription<QuerySnapshot>? _savedPartySub;
  final Set<String> _billOnlyParties = {};
  final Map<String, double> _savedOB = {}; // partyKey -> openingBalance

  // ── Filter ────────────────────────────────────────────────────────────────
  _BpFilter  _filter      = _BpFilter.all;
  DateTimeRange? _customRange;

  // ── Export state ─────────────────────────────────────────────────────────
  bool    _exporting     = false;
  String? _exportingFmt;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _idSub = ref.listenManual<String?>(
        currentCashbookIdProvider,
        (_, next) {
          if (next != null && next.isNotEmpty && next != _cashbookId) {
            _cashbookId = next;
            _billsPartySub?.cancel();
            _savedPartySub?.cancel();
            _startStreams(next);
          }
        },
        fireImmediately: true,
      );
    });
  }

  void _startStreams(String cashbookId) {
    _billsPartySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('sale_bills')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      _billOnlyParties.clear();
      for (final doc in snap.docs) {
        final name = (doc.data()['partyName'] as String? ?? '').trim();
        if (name.isNotEmpty) {
          _billOnlyParties.add(name.trim().toLowerCase());
        }
      }
      _rebuildPartyList();
    });

    _savedPartySub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('parties')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      _savedOB.clear();
      for (final doc in snap.docs) {
        final name = (doc.data()['partyName'] as String? ?? '').trim();
        final ob   = (doc.data()['openingBalance'] as num?)?.toDouble() ?? 0.0;
        if (name.isNotEmpty) {
          _savedOB[name.trim().toLowerCase()] = ob;
        }
      }
      _rebuildPartyList();
    });
  }

  void _rebuildPartyList() {
    final names = <String>{};
    for (final key in _billOnlyParties) names.add(key);
    for (final key in _savedOB.keys)    names.add(key);

    final partyAsync = ref.read(partiesProvider).asData?.value ?? [];
    final byKey = <String, String>{};
    for (final p in partyAsync) {
      byKey[p.partyName.trim().toLowerCase()] = p.partyName.trim();
    }

    // Prefer display names from provider
    final displayNames = <String>[];
    final seen = <String>{};
    for (final key in names) {
      if (seen.contains(key)) continue;
      seen.add(key);
      displayNames.add(byKey[key] ?? _capitalize(key));
    }
    displayNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (mounted) {
      setState(() => _allPartyNames = displayNames);
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) => w.isEmpty
        ? w
        : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  @override
  void dispose() {
    _idSub?.close();
    _billsPartySub?.cancel();
    _savedPartySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Filter helpers ────────────────────────────────────────────────────────

  DateTime? get _startDate {
    final now = DateTime.now();
    switch (_filter) {
      case _BpFilter.week:
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      case _BpFilter.month:
        return DateTime(now.year, now.month, 1);
      case _BpFilter.year:
        return DateTime(now.year, 1, 1);
      case _BpFilter.all:
        return null;
      case _BpFilter.custom:
        return _customRange?.start;
    }
  }

  DateTime? get _endDate {
    final now = DateTime.now();
    switch (_filter) {
      case _BpFilter.custom:
        if (_customRange != null) {
          return DateTime(
            _customRange!.end.year,
            _customRange!.end.month,
            _customRange!.end.day,
            23, 59, 59,
          );
        }
        return null;
      default:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
    }
  }

  String get _filterLabel {
    final dateFmt = DateFormat('dd MMM yyyy');
    switch (_filter) {
      case _BpFilter.week:
        final start = _startDate!;
        final end   = DateTime.now();
        return '${dateFmt.format(start)} – ${dateFmt.format(end)}';
      case _BpFilter.month:
        return DateFormat('MMMM yyyy').format(DateTime.now());
      case _BpFilter.year:
        return DateTime.now().year.toString();
      case _BpFilter.all:
        return 'All Time';
      case _BpFilter.custom:
        if (_customRange != null) {
          return '${dateFmt.format(_customRange!.start)} – '
              '${dateFmt.format(_customRange!.end)}';
        }
        return 'Custom Range';
    }
  }

  Future<void> _pickCustomRange() async {
    HapticFeedback.selectionClick();
    final now   = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate:  now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: DateTime(now.year, now.month, 1), end: now),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary:    _T.accent,
            onPrimary:  Colors.white,
            surface:    _T.card2,
            onSurface:  _T.text,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: _T.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (range != null && mounted) {
      setState(() {
        _customRange = range;
        _filter      = _BpFilter.custom;
      });
    }
  }

  // ─── Selection helpers ─────────────────────────────────────────────────────

  void _toggle(String name) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
  }

  void _selectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      _selected.addAll(_visible);
    });
  }

  void _clearAll() {
    HapticFeedback.selectionClick();
    setState(() => _selected.clear());
  }

  List<String> get _visible => _searchQuery.isEmpty
      ? _allPartyNames
      : _allPartyNames
          .where((n) => n.toLowerCase().contains(_searchQuery))
          .toList();

  // ─── Data fetching ─────────────────────────────────────────────────────────

  Future<List<_PartyExportData>> _fetchData() async {
    final cashbookId = _cashbookId;
    if (cashbookId == null) throw Exception('No active cashbook.');

    final db = FirebaseFirestore.instance;

    // Fetch all bills for selected parties
    final billsSnap = await db
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('sale_bills')
        .get();

    // Fetch all income transactions once
    final txSnap = await db
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'income')
        .get();

    // Build bill-id → list of payments map
    final payMap = <String, List<_PayEntry>>{};
    for (final doc in txSnap.docs) {
      final raw      = doc.data();
      final linkedId = raw['linkedSaleBillId'] as String?;
      if (linkedId == null || linkedId.isEmpty) continue;
      final amount   = (raw['amount'] as num?)?.toDouble() ?? 0.0;
      final ts       = raw['createdAt'] as Timestamp?;
      final date     = ts?.toDate() ?? DateTime.now();
      payMap.putIfAbsent(linkedId, () => [])
          .add(_PayEntry(amount: amount, date: date));
    }

    final start = _startDate;
    final end   = _endDate;

    final result = <_PartyExportData>[];

    for (final partyName in _selected) {
      final partyKey = partyName.trim().toLowerCase();
      final ob       = _savedOB[partyKey] ?? 0.0;

      // Filter bills belonging to this party and within date range
      final partyBills = <_BillData>[];
      for (final doc in billsSnap.docs) {
        final d    = doc.data();
        final name = (d['partyName'] as String? ?? '').trim().toLowerCase();
        if (name != partyKey) continue;

        final billDate = (d['billDate'] as Timestamp?)?.toDate() ?? DateTime.now();

        // Apply date filter to billDate
        if (start != null && billDate.isBefore(start)) continue;
        if (end   != null && billDate.isAfter(end))    continue;

        final bill = SaleBillEntity(
          saleBillId:        d['saleBillId']        as String? ?? doc.id,
          partyName:         d['partyName']          as String? ?? '',
          billNumber:        d['billNumber']          as String? ?? '',
          billTotal:         (d['billTotal']  as num?)?.toDouble() ?? 0.0,
          billDate:          billDate,
          billNote:          d['billNote']            as String?,
          billCreatedAt:     (d['billCreatedAt'] as Timestamp?)?.toDate() ??
                             DateTime.now(),
          billCreatedBy:     d['billCreatedBy']      as String? ?? '',
          billCreatedByName: d['billCreatedByName']  as String? ?? '',
          billStatus:        d['billStatus']          as String? ?? 'pending',
        );

        final billId  = bill.saleBillId;
        final pays    = List<_PayEntry>.from(payMap[billId] ?? []);
        pays.sort((a, b) => a.date.compareTo(b.date));

        final received = pays.fold(0.0, (s, p) => s + p.amount)
            .clamp(0.0, bill.billTotal);
        final firstPay = pays.isNotEmpty ? pays.first.date : null;

        partyBills.add(_BillData(
          bill:         bill,
          received:     received,
          firstPayDate: firstPay,
          payments:     pays,
        ));
      }

      // Sort bills by date ascending
      partyBills.sort((a, b) => a.bill.billDate.compareTo(b.bill.billDate));

      result.add(_PartyExportData(
        name:            partyName,
        bills:           partyBills,
        openingBalance:  ob,
      ));
    }

    // Sort parties by name
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  // ─── Export entry ──────────────────────────────────────────────────────────

  Future<void> _doExport(String format) async {
    if (_exporting) return;
    if (_selected.isEmpty) {
      _snack('Please select at least one party.', error: true);
      return;
    }
    if (_filter == _BpFilter.custom && _customRange == null) {
      _snack('Please pick a custom date range first.', error: true);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() { _exporting = true; _exportingFmt = format; });

    try {
      final data = await _fetchData();

      final hasAnyBill = data.any((p) => p.bills.isNotEmpty);
      if (!hasAnyBill) {
        if (mounted) {
          _snack('No bills found for the selected parties and date range.',
              error: true);
        }
        return;
      }

      if (!mounted) return;
      if (format == 'pdf') {
        await _generatePdf(data);
      } else {
        await _generateExcel(data);
      }

      if (mounted) {
        _snack('${format.toUpperCase()} exported — choose a location in the share sheet.');
      }
    } catch (e) {
      if (mounted) _snack('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() { _exporting = false; _exportingFmt = null; });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _T.red : _T.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  // ─── PDF Generation ────────────────────────────────────────────────────────

  Future<void> _generatePdf(List<_PartyExportData> data) async {
    const companyName = 'NEELKANTH GARMENTS';

    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yyyy');
    final now     = dateFmt.format(DateTime.now());

    // PDF color palette
    final cBlue      = PdfColor.fromHex('1e3a5f');
    final cDeepBlue  = PdfColor.fromHex('0f2547');
    final cWhite     = PdfColors.white;
    final cGreen     = PdfColor.fromHex('15803d');
    final cRed       = PdfColor.fromHex('b91c1c');
    final cGrey      = PdfColor.fromHex('6b7280');
    final cDarkText  = PdfColor.fromHex('111827');
    final cLightGrey = PdfColor.fromHex('f9fafb');
    final cAmber     = PdfColor.fromHex('f59e0b');
    final cLightBlue = PdfColor.fromHex('eff6ff');
    final cLightGrn  = PdfColor.fromHex('f0fdf4');
    final cLightRed  = PdfColor.fromHex('fff1f2');
    final cSubGrey   = PdfColor.fromHex('9ca3af');
    final cMidDark   = PdfColor.fromHex('374151');
    final cGrnLight  = PdfColor.fromHex('86efac');
    final cRedLight  = PdfColor.fromHex('fca5a5');
    final cPartyBg   = PdfColor.fromHex('e8f0fe');
    final cAccent    = PdfColor.fromHex('6c7fe4');

    pw.Widget statBox(String label, String value, PdfColor valueColor, PdfColor bg) =>
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: pw.BoxDecoration(
              color: bg,
              border: pw.Border.all(color: PdfColor.fromHex('e5e7eb')),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label,
                    style: pw.TextStyle(color: cGrey, fontSize: 7)),
                pw.SizedBox(height: 3),
                pw.Text(value,
                    style: pw.TextStyle(
                        color: valueColor,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        );

    pw.Widget hCell(String text, {pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          child: pw.Text(text,
              textAlign: align,
              style: pw.TextStyle(
                  color: cWhite,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget dCell(String text, {
      pw.TextAlign align = pw.TextAlign.left,
      PdfColor? color,
      double size = 8,
      bool bold = false,
    }) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          child: pw.Text(text,
              textAlign: align,
              style: pw.TextStyle(
                  color: color ?? cDarkText,
                  fontSize: size,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
        header: (ctx) => pw.Column(children: [
          // ── Company header bar ───────────────────────────────────────────
          pw.Container(
            decoration: pw.BoxDecoration(color: cDeepBlue),
            padding: const pw.EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName,
                        style: pw.TextStyle(
                            color: cWhite,
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('BILLPORT — MULTI-PARTY STATEMENT',
                        style: pw.TextStyle(
                            color: PdfColor.fromHex('7ab3d8'),
                            fontSize: 8,
                            letterSpacing: 0.5)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('DATE RANGE',
                        style: pw.TextStyle(
                            color: PdfColor.fromHex('7ab3d8'), fontSize: 7)),
                    pw.SizedBox(height: 2),
                    pw.Text(_filterLabel,
                        style: pw.TextStyle(
                            color: cWhite,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('Generated: $now',
                        style: pw.TextStyle(
                            color: PdfColor.fromHex('93b8d4'), fontSize: 8)),
                  ],
                ),
              ],
            ),
          ),
          // Gradient accent bar
          pw.Container(
            height: 3,
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(colors: [cAmber, cAccent, cDeepBlue]),
            ),
          ),
          pw.SizedBox(height: 6),
        ]),
        footer: (ctx) => pw.Column(children: [
          pw.Divider(color: cBlue, thickness: 0.8),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Computer-generated statement · $companyName',
                  style: pw.TextStyle(color: cSubGrey, fontSize: 7)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: pw.TextStyle(color: cSubGrey, fontSize: 7)),
            ],
          ),
        ]),
        build: (ctx) {
          final widgets = <pw.Widget>[];

          // ── Overall summary strip ──────────────────────────────────────────
          final grandTotalBilled   = data.fold(0.0, (s, p) => s + p.totalBilled);
          final grandTotalReceived = data.fold(0.0, (s, p) => s + p.totalReceived);
          final grandBalance       = data.fold(0.0, (s, p) => s + p.totalBalance);

          widgets.add(pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: cLightBlue,
              border: pw.Border.all(color: PdfColor.fromHex('bfdbfe')),
            ),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('TOTAL ACROSS ${data.length} PART${data.length == 1 ? 'Y' : 'IES'}',
                      style: pw.TextStyle(
                          color: cBlue, fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  pw.Text('${data.fold(0, (s, p) => s + p.bills.length)} bills',
                      style: pw.TextStyle(color: cGrey, fontSize: 8)),
                ],
              )),
              pw.SizedBox(width: 8),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('Total Billed: Rs. ${fmt.format(grandTotalBilled)}',
                    style: pw.TextStyle(
                        color: cBlue, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Total Received: Rs. ${fmt.format(grandTotalReceived)}',
                    style: pw.TextStyle(
                        color: cGreen, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Balance Due: Rs. ${fmt.format(grandBalance)}',
                    style: pw.TextStyle(
                        color: grandBalance > 0 ? cRed : cGreen,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold)),
              ]),
            ]),
          ));

          widgets.add(pw.SizedBox(height: 14));

          // ── Per-party sections ─────────────────────────────────────────────
          for (final party in data) {
            // Party header
            widgets.add(pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                    colors: [cBlue, PdfColor.fromHex('2d5186')],
                    begin: pw.Alignment.centerLeft,
                    end: pw.Alignment.centerRight),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PARTY',
                          style: pw.TextStyle(
                              color: PdfColor.fromHex('7ab3d8'), fontSize: 7)),
                      pw.SizedBox(height: 2),
                      pw.Text(party.name,
                          style: pw.TextStyle(
                              color: cWhite,
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Text(
                    '${party.bills.length} bill${party.bills.length == 1 ? '' : 's'}   '
                    'Cleared: ${party.bills.where((b) => b.isCleared).length}   '
                    'Pending: ${party.bills.where((b) => !b.isCleared).length}',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('93b8d4'), fontSize: 8),
                  ),
                ],
              ),
            ));

            widgets.add(pw.SizedBox(height: 6));

            if (party.bills.isEmpty && party.openingBalance <= 0) {
              widgets.add(pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: cLightGrey,
                  border: pw.Border.all(color: PdfColor.fromHex('e5e7eb')),
                ),
                child: pw.Text(
                  'No bills found for this party in the selected date range.',
                  style: pw.TextStyle(color: cGrey, fontSize: 9),
                ),
              ));
              widgets.add(pw.SizedBox(height: 14));
              continue;
            }

            // Stats row
            widgets.add(pw.Row(children: [
              statBox('TOTAL BILLED',
                  'Rs. ${fmt.format(party.totalBilled)}',
                  cBlue, cLightBlue),
              pw.SizedBox(width: 6),
              statBox('TOTAL RECEIVED',
                  'Rs. ${fmt.format(party.totalReceived)}',
                  cGreen, cLightGrn),
              pw.SizedBox(width: 6),
              statBox(
                'BALANCE DUE',
                'Rs. ${fmt.format(party.totalBalance)}',
                party.totalBalance > 0 ? cRed : cGreen,
                party.totalBalance > 0 ? cLightRed : cLightGrn,
              ),
            ]));

            widgets.add(pw.SizedBox(height: 8));

            // Bills table
            widgets.add(pw.Table(
              border: pw.TableBorder(
                bottom: pw.BorderSide(color: PdfColor.fromHex('e5e7eb')),
                horizontalInside: pw.BorderSide(
                    color: PdfColor.fromHex('f0f0f0')),
              ),
              columnWidths: const {
                0: pw.FixedColumnWidth(18),
                1: pw.FlexColumnWidth(2.4),
                2: pw.FlexColumnWidth(2.0),
                3: pw.FlexColumnWidth(2.0),
                4: pw.FlexColumnWidth(1.8),
                5: pw.FlexColumnWidth(2.0),
                6: pw.FlexColumnWidth(2.2),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: cBlue),
                  children: [
                    hCell('#', align: pw.TextAlign.center),
                    hCell('Bill No.'),
                    hCell('Bill Date'),
                    hCell('Bill Amt', align: pw.TextAlign.right),
                    hCell('Pay Date', align: pw.TextAlign.right),
                    hCell('Paid', align: pw.TextAlign.right),
                    hCell('Balance / Status', align: pw.TextAlign.right),
                  ],
                ),

                // Opening Balance row (if any)
                if (party.openingBalance > 0)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: cLightBlue),
                    children: [
                      dCell('OB', align: pw.TextAlign.center, color: cSubGrey),
                      dCell('Opening Balance',
                          color: cMidDark, size: 8.5, bold: true),
                      dCell('—', color: cSubGrey),
                      dCell('Rs. ${fmt.format(party.openingBalance)}',
                          align: pw.TextAlign.right, size: 8.5, bold: true),
                      dCell('—', align: pw.TextAlign.right, color: cSubGrey),
                      dCell('—', align: pw.TextAlign.right, color: cSubGrey),
                      dCell('Rs. ${fmt.format(party.openingBalance)} Due',
                          align: pw.TextAlign.right,
                          color: cRed, size: 8, bold: true),
                    ],
                  ),

                // Bill rows
                ...party.bills.asMap().entries.map((entry) {
                  final idx  = entry.key;
                  final bd   = entry.value;
                  final rowBg = idx % 2 == 0 ? cLightGrey : PdfColors.white;

                  final payDateStr = bd.firstPayDate != null
                      ? dateFmt.format(bd.firstPayDate!)
                      : '-';

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowBg),
                    children: [
                      dCell('${idx + 1}',
                          align: pw.TextAlign.center, color: cSubGrey),
                      dCell(bd.bill.billNumber,
                          color: cBlue, size: 8.5, bold: true),
                      dCell(dateFmt.format(bd.bill.billDate),
                          color: cMidDark),
                      dCell('Rs. ${fmt.format(bd.bill.billTotal)}',
                          align: pw.TextAlign.right, size: 8.5, bold: true),
                      dCell(payDateStr,
                          align: pw.TextAlign.right,
                          color: bd.firstPayDate != null ? cMidDark : cSubGrey),
                      dCell(
                          bd.received > 0
                              ? 'Rs. ${fmt.format(bd.received)}'
                              : '-',
                          align: pw.TextAlign.right,
                          color: bd.received > 0 ? cGreen : cSubGrey,
                          bold: bd.received > 0),
                      bd.isCleared
                          ? pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 7),
                              child: pw.Text('Bill Cleared',
                                  textAlign: pw.TextAlign.right,
                                  style: pw.TextStyle(
                                      color: cGreen,
                                      fontSize: 8,
                                      fontWeight: pw.FontWeight.bold)))
                          : dCell('Rs. ${fmt.format(bd.balance)}',
                              align: pw.TextAlign.right,
                              color: cRed, size: 8.5, bold: true),
                    ],
                  );
                }),

                // Totals row
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: cBlue),
                  children: [
                    for (final t in [
                      ('', pw.TextAlign.left, cWhite, 8.0, false),
                      ('Total', pw.TextAlign.left, cWhite, 8.5, true),
                      ('', pw.TextAlign.left, cWhite, 8.0, false),
                      ('Rs. ${fmt.format(party.totalBilled)}',
                          pw.TextAlign.right, cWhite, 9.0, true),
                      ('', pw.TextAlign.left, cWhite, 8.0, false),
                      ('Rs. ${fmt.format(party.totalReceived)}',
                          pw.TextAlign.right, cGrnLight, 9.0, true),
                      (party.totalBalance > 0
                          ? 'Rs. ${fmt.format(party.totalBalance)} Due'
                          : 'Settled',
                          pw.TextAlign.right,
                          party.totalBalance > 0 ? cRedLight : cGrnLight,
                          8.5, true),
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 5, vertical: 8),
                        child: pw.Text(t.$1,
                            textAlign: t.$2,
                            style: pw.TextStyle(
                                color: t.$3,
                                fontSize: t.$4,
                                fontWeight: t.$5
                                    ? pw.FontWeight.bold
                                    : pw.FontWeight.normal)),
                      ),
                  ],
                ),
              ],
            ));

            widgets.add(pw.SizedBox(height: 18));
          }

          return widgets;
        },
      ),
    );

    final bytes    = await doc.save();
    final safeName = 'billport_${DateTime.now().millisecondsSinceEpoch}';

    if (!mounted) return;
    if (kIsWeb) {
      await Share.shareXFiles([
        XFile.fromData(bytes,
            name: '$safeName.pdf',
            mimeType: 'application/pdf'),
      ], subject: 'Billport — Multi-party Statement');
    } else {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$safeName.pdf');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Billport — Multi-party Statement');
    }
  }

  // ─── Excel Generation ──────────────────────────────────────────────────────

  Future<void> _generateExcel(List<_PartyExportData> data) async {
    const companyName = 'NEELKANTH GARMENTS';
    final fmt     = NumberFormat('#,##,##0.##');
    final dateFmt = DateFormat('dd MMM yyyy');
    final now     = dateFmt.format(DateTime.now());

    final excel = Excel.createExcel();

    // ── Summary sheet ────────────────────────────────────────────────────────
    final summarySheet = excel['Summary'];
    excel.setDefaultSheet('Summary');

    // Title rows
    summarySheet.appendRow([TextCellValue(companyName)]);
    summarySheet.appendRow([TextCellValue('BILLPORT — MULTI-PARTY STATEMENT')]);
    summarySheet.appendRow([TextCellValue('Date Range: $_filterLabel')]);
    summarySheet.appendRow([TextCellValue('Generated: $now')]);
    summarySheet.appendRow([TextCellValue('')]);

    // Summary header
    summarySheet.appendRow([
      TextCellValue('Party Name'),
      TextCellValue('No. of Bills'),
      TextCellValue('Total Billed (Rs.)'),
      TextCellValue('Total Received (Rs.)'),
      TextCellValue('Balance Due (Rs.)'),
      TextCellValue('Status'),
    ]);

    double grandBilled   = 0;
    double grandReceived = 0;
    double grandBalance  = 0;

    for (final party in data) {
      summarySheet.appendRow([
        TextCellValue(party.name),
        IntCellValue(party.bills.length),
        DoubleCellValue(party.totalBilled),
        DoubleCellValue(party.totalReceived),
        DoubleCellValue(party.totalBalance),
        TextCellValue(party.totalBalance <= 0 ? 'Settled' : 'Balance Due'),
      ]);
      grandBilled   += party.totalBilled;
      grandReceived += party.totalReceived;
      grandBalance  += party.totalBalance;
    }

    // Totals row
    summarySheet.appendRow([
      TextCellValue('GRAND TOTAL'),
      IntCellValue(data.fold(0, (s, p) => s + p.bills.length)),
      DoubleCellValue(grandBilled),
      DoubleCellValue(grandReceived),
      DoubleCellValue(grandBalance),
      TextCellValue(''),
    ]);

    // ── Per-party sheets ──────────────────────────────────────────────────────
    for (final party in data) {
      final safeName = party.name
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_');
      // Excel sheet names are max 31 chars
      final sheetName = safeName.length > 28
          ? safeName.substring(0, 28)
          : safeName;

      final sheet = excel[sheetName];

      // Party header
      sheet.appendRow([TextCellValue(companyName)]);
      sheet.appendRow([TextCellValue('Party: ${party.name}')]);
      sheet.appendRow([TextCellValue('Date Range: $_filterLabel')]);
      sheet.appendRow([TextCellValue('Generated: $now')]);
      sheet.appendRow([TextCellValue('')]);

      // Party summary
      sheet.appendRow([
        TextCellValue('Total Billed'),
        TextCellValue('Total Received'),
        TextCellValue('Balance Due'),
        TextCellValue('Bills Count'),
      ]);
      sheet.appendRow([
        DoubleCellValue(party.totalBilled),
        DoubleCellValue(party.totalReceived),
        DoubleCellValue(party.totalBalance),
        IntCellValue(party.bills.length),
      ]);
      sheet.appendRow([TextCellValue('')]);

      if (party.bills.isEmpty) {
        sheet.appendRow([
          TextCellValue('No bills found for selected date range.'),
        ]);
        continue;
      }

      // Bills detail header
      sheet.appendRow([
        TextCellValue('#'),
        TextCellValue('Bill No.'),
        TextCellValue('Bill Date'),
        TextCellValue('Bill Amount (Rs.)'),
        TextCellValue('Amount Received (Rs.)'),
        TextCellValue('Balance Due (Rs.)'),
        TextCellValue('First Payment Date'),
        TextCellValue('Status'),
      ]);

      // Opening Balance row
      if (party.openingBalance > 0) {
        sheet.appendRow([
          TextCellValue('OB'),
          TextCellValue('Opening Balance'),
          TextCellValue('—'),
          DoubleCellValue(party.openingBalance),
          TextCellValue('—'),
          DoubleCellValue(party.openingBalance),
          TextCellValue('—'),
          TextCellValue('Pending'),
        ]);
      }

      for (int i = 0; i < party.bills.length; i++) {
        final bd = party.bills[i];
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(bd.bill.billNumber),
          TextCellValue(dateFmt.format(bd.bill.billDate)),
          DoubleCellValue(bd.bill.billTotal),
          DoubleCellValue(bd.received),
          DoubleCellValue(bd.balance),
          TextCellValue(bd.firstPayDate != null
              ? dateFmt.format(bd.firstPayDate!)
              : '-'),
          TextCellValue(bd.isCleared ? 'Cleared' : 'Pending'),
        ]);
      }

      // Total row
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue('TOTAL'),
        TextCellValue(''),
        DoubleCellValue(party.totalBilled),
        DoubleCellValue(party.totalReceived),
        DoubleCellValue(party.totalBalance),
        TextCellValue(''),
        TextCellValue(party.totalBalance <= 0 ? 'All Settled' : 'Balance Due'),
      ]);
    }

    // Remove default blank sheet if no default sheets exist
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileBytes = excel.save();
    if (fileBytes == null) throw Exception('Failed to generate Excel file.');

    final safeName = 'billport_${DateTime.now().millisecondsSinceEpoch}';

    final fileBytesTyped = fileBytes is Uint8List
        ? fileBytes
        : Uint8List.fromList(fileBytes);

    if (!mounted) return;
    if (kIsWeb) {
      await Share.shareXFiles([
        XFile.fromData(fileBytesTyped,
            name: '$safeName.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      ], subject: 'Billport — Multi-party Statement');
    } else {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$safeName.xlsx');
      await file.writeAsBytes(fileBytesTyped);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Billport — Multi-party Statement');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final allSelected = visible.isNotEmpty &&
        visible.every((n) => _selected.contains(n));

    return Scaffold(
      backgroundColor: _T.bg,
      body: Column(
        children: [

          // ── App Bar ───────────────────────────────────────────────────────
          _BpAppBar(
            selectedCount: _selected.length,
            allSelected:   allSelected,
            onBack:        () => Navigator.of(context).pop(),
            onSelectAll:   allSelected ? _clearAll : _selectAll,
          ),

          // ── Date filter strip ────────────────────────────────────────────
          _DateFilterBar(
            active:       _filter,
            customRange:  _customRange,
            onSelect:     (f) {
              if (f == _BpFilter.custom) {
                _pickCustomRange();
              } else {
                HapticFeedback.selectionClick();
                setState(() => _filter = f);
              }
            },
          ),

          // ── Search bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _SearchField(
              controller: _searchCtrl,
              hint:       'Search parties…',
            ),
          ),

          // ── Party list ────────────────────────────────────────────────────
          Expanded(
            child: _allPartyNames.isEmpty
                ? const _EmptyParties()
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          'No parties match "$_searchQuery"',
                          style: const TextStyle(
                              color: _T.muted2, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final name = visible[i];
                          final on   = _selected.contains(name);
                          return _PartyCheckTile(
                            key:      ValueKey(name),
                            name:     name,
                            selected: on,
                            onTap:    () => _toggle(name),
                          );
                        },
                      ),
          ),

          // ── Export bar ────────────────────────────────────────────────────
          _ExportBar(
            selected:     _selected.length,
            exporting:    _exporting,
            exportingFmt: _exportingFmt,
            onPdf:        () => _doExport('pdf'),
            onExcel:      () => _doExport('excel'),
          ),

        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BpAppBar extends StatelessWidget {
  final int       selectedCount;
  final bool      allSelected;
  final VoidCallback onBack;
  final VoidCallback onSelectAll;

  const _BpAppBar({
    required this.selectedCount,
    required this.allSelected,
    required this.onBack,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 12),
      decoration: const BoxDecoration(
        color: _T.bg,
        border: Border(bottom: BorderSide(color: _T.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 14, color: _T.muted2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Billport',
                    style: TextStyle(
                        color: _T.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4)),
                Text(
                  selectedCount == 0
                      ? 'Select parties to export'
                      : '$selectedCount part${selectedCount == 1 ? 'y' : 'ies'} selected',
                  style: TextStyle(
                      color: selectedCount == 0 ? _T.muted : _T.accent,
                      fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onSelectAll,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _T.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: _T.accent.withValues(alpha: 0.25)),
              ),
              child: Text(
                allSelected ? 'Deselect All' : 'Select All',
                style: const TextStyle(
                    color: _T.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Date filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _DateFilterBar extends StatelessWidget {
  final _BpFilter           active;
  final DateTimeRange?      customRange;
  final void Function(_BpFilter) onSelect;

  const _DateFilterBar({
    required this.active,
    required this.customRange,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _T.bg,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DATE RANGE',
              style: TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _BpFilter.values.map((f) {
                final on     = f == active;
                final isCustom = f == _BpFilter.custom;
                final dateFmt  = DateFormat('dd MMM');
                final label    = (isCustom && customRange != null)
                    ? '${dateFmt.format(customRange!.start)}–'
                      '${dateFmt.format(customRange!.end)}'
                    : f.label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onSelect(f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: on
                            ? _T.accent
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: on
                              ? _T.accent
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCustom)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.date_range_rounded,
                                  size: 12, color: Colors.white70),
                            ),
                          Text(label,
                              style: TextStyle(
                                color: on
                                    ? Colors.white
                                    : const Color(0xFF9CA3AF),
                                fontSize: 12,
                                fontWeight: on
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              )),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Party check tile
// ─────────────────────────────────────────────────────────────────────────────

class _PartyCheckTile extends StatelessWidget {
  final String       name;
  final bool         selected;
  final VoidCallback onTap;

  const _PartyCheckTile({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? _T.accent.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? _T.accent.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.07),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected ? _T.accent : const Color(0xFF4B5563),
                  width: 2,
                ),
                color: selected ? _T.accent : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color:
                      selected ? _T.text : const Color(0xFFD1D5DB),
                  fontSize: 15,
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.file_present_rounded,
                  size: 16, color: _T.accent.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Search field
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String                hint;

  const _SearchField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: _T.text, fontSize: 14),
        decoration: InputDecoration(
          hintText:    hint,
          hintStyle:   const TextStyle(color: _T.muted, fontSize: 14),
          prefixIcon:  const Icon(Icons.search_rounded,
              color: _T.muted, size: 18),
          suffixIcon: ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, v, __) => v.text.isNotEmpty
                ? GestureDetector(
                    onTap: controller.clear,
                    child: const Icon(Icons.clear_rounded,
                        color: _T.muted, size: 16),
                  )
                : const SizedBox.shrink(),
          ),
          border:        InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Export bar  (sticky bottom)
// ─────────────────────────────────────────────────────────────────────────────

class _ExportBar extends StatelessWidget {
  final int       selected;
  final bool      exporting;
  final String?   exportingFmt;
  final VoidCallback onPdf;
  final VoidCallback onExcel;

  const _ExportBar({
    required this.selected,
    required this.exporting,
    required this.exportingFmt,
    required this.onPdf,
    required this.onExcel,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: _T.card,
        border: const Border(top: BorderSide(color: _T.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '$selected part${selected == 1 ? 'y' : 'ies'} selected — choose export format',
                style: const TextStyle(color: _T.muted2, fontSize: 12),
              ),
            ),
          Row(
            children: [
              // PDF button
              Expanded(
                child: _ExportBtn(
                  icon:     Icons.picture_as_pdf_rounded,
                  label:    'Export PDF',
                  color:    const Color(0xFFEF4444),
                  loading:  exporting && exportingFmt == 'pdf',
                  disabled: exporting || selected == 0,
                  onTap:    onPdf,
                ),
              ),
              const SizedBox(width: 12),
              // Excel button
              Expanded(
                child: _ExportBtn(
                  icon:     Icons.table_chart_rounded,
                  label:    'Export Excel',
                  color:    const Color(0xFF22C55E),
                  loading:  exporting && exportingFmt == 'excel',
                  disabled: exporting || selected == 0,
                  onTap:    onExcel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final bool         loading;
  final bool         disabled;
  final VoidCallback onTap;

  const _ExportBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: AnimatedOpacity(
        opacity: disabled && !loading ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            gradient: disabled && !loading
                ? null
                : LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.85),
                      color,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: disabled && !loading
                ? Colors.white.withValues(alpha: 0.05)
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: disabled || loading
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              else
                Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                loading ? 'Exporting…' : label,
                style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   13,
                  fontWeight: FontWeight.w700,
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
//  Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyParties extends StatelessWidget {
  const _EmptyParties();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 48, color: _T.muted),
            SizedBox(height: 12),
            Text('No parties found',
                style: TextStyle(
                    color: _T.muted2,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Add parties in the Sales screen first.',
                style: TextStyle(color: _T.muted, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
