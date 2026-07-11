// lib/features/bills/presentation/screens/create_bill_screen.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/sales/data/models/sale_bill_model.dart';
import 'package:synccash/features/sales/presentation/providers/party_provider.dart';
import '../../data/models/custom_bill_model.dart';
import '../providers/bills_provider.dart';

import 'package:synccash/features/sales/presentation/screens/web_invoice_viewer_stub.dart'
    if (dart.library.html) 'package:synccash/features/sales/presentation/screens/web_invoice_viewer_web.dart';
import 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_stub.dart'
    if (dart.library.io) 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_native.dart';

// ── Theme tokens ──────────────────────────────────────────────────────────────

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
  static const red     = Color(0xFFE85C5C);
  static const divider = Color(0xFF1C2130);
}

// ── Default business constants ────────────────────────────────────────────────

const _kDefaultBusinessName    = 'Neelkanth Garments';
const _kDefaultBusinessAddress = 'Baramati, Maharashtra';

// ── Editable bill item state ──────────────────────────────────────────────────

class _ItemState {
  final TextEditingController nameCtrl;
  final TextEditingController sizeCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;

  _ItemState()
      : nameCtrl = TextEditingController(),
        sizeCtrl = TextEditingController(),
        qtyCtrl  = TextEditingController(),
        rateCtrl = TextEditingController();

  double get qty    => double.tryParse(qtyCtrl.text.trim())  ?? 0;
  double get rate   => double.tryParse(rateCtrl.text.trim()) ?? 0;
  double get amount => qty * rate;

  bool get isValid =>
      nameCtrl.text.trim().isNotEmpty && qty > 0 && rate > 0;

  BillItem toBillItem() => BillItem(
        name: nameCtrl.text.trim(),
        size: sizeCtrl.text.trim(),
        qty:  qty,
        rate: rate,
      );

  void dispose() {
    nameCtrl.dispose();
    sizeCtrl.dispose();
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}

// ── Create Bill Screen ────────────────────────────────────────────────────────

class CreateBillScreen extends ConsumerStatefulWidget {
  final String? prefilledClientName;
  const CreateBillScreen({super.key, this.prefilledClientName});

  @override
  ConsumerState<CreateBillScreen> createState() => _CreateBillScreenState();
}

class _CreateBillScreenState extends ConsumerState<CreateBillScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // Business info
  final _bizNameCtrl    = TextEditingController(text: _kDefaultBusinessName);
  final _bizAddressCtrl = TextEditingController(text: _kDefaultBusinessAddress);

  // Bill info
  final _billNoCtrl = TextEditingController();
  DateTime _billDate = DateTime.now();

  // Client info
  final _clientNameCtrl    = TextEditingController();
  // ▶ FIX 1: store FocusNode as a field, not inline inside build()
  final _clientFocusNode   = FocusNode();
  final _clientAddressCtrl = TextEditingController();

  // Items
  final List<_ItemState> _items = [_ItemState()];

  // Tax
  final _taxRateCtrl = TextEditingController(text: '0');

  // State
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledClientName != null) {
      _clientNameCtrl.text = widget.prefilledClientName!;
    }
    for (final item in _items) {
      item.qtyCtrl.addListener(_rebuildTotals);
      item.rateCtrl.addListener(_rebuildTotals);
    }
    _taxRateCtrl.addListener(_rebuildTotals);
  }

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _bizAddressCtrl.dispose();
    _billNoCtrl.dispose();
    _clientNameCtrl.dispose();
    _clientFocusNode.dispose(); // ▶ FIX 1: dispose properly
    _clientAddressCtrl.dispose();
    _taxRateCtrl.dispose();
    _scrollCtrl.dispose();
    for (final item in _items) item.dispose();
    super.dispose();
  }

  void _rebuildTotals() { if (mounted) setState(() {}); }

  double get _subtotal   => _items.fold(0.0, (s, i) => s + i.amount);
  double get _taxRate    => double.tryParse(_taxRateCtrl.text.trim()) ?? 0;
  double get _taxAmount  => _subtotal * _taxRate / 100;
  double get _grandTotal => _subtotal + _taxAmount;

  void _addItem() {
    HapticFeedback.selectionClick();
    final newItem = _ItemState();
    newItem.qtyCtrl.addListener(_rebuildTotals);
    newItem.rateCtrl.addListener(_rebuildTotals);
    setState(() => _items.add(newItem));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeItem(int index) {
    HapticFeedback.selectionClick();
    if (_items.length <= 1) return;
    _items[index].dispose();
    setState(() => _items.removeAt(index));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _billDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _T.accent,
            onPrimary: _T.bg,
            surface: _T.card2,
            onSurface: _T.text,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: _T.bg),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _billDate = picked);
  }

  bool _validate() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (_items.every((i) => !i.isValid)) {
      _showSnack('Add at least one item with name, quantity and rate',
          success: false);
      return false;
    }
    return true;
  }

  // ── PDF Generation ─────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdfBytes() async {
    final pdf  = pw.Document();
    final fmt  = NumberFormat('#,##,##0.00', 'en_IN');
    final date = DateFormat('dd MMM yyyy').format(_billDate);

    final validItems =
        _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).toList();

    final cWhite     = PdfColors.white;
    final cDark      = PdfColor.fromHex('0F1318');
    final cAccent    = PdfColor.fromHex('4C6EF5');
    final cAccentBg  = PdfColor.fromHex('EEF2FF');
    final cAccentBdr = PdfColor.fromHex('A5B4FC');
    final cGrey      = PdfColor.fromHex('6B7280');
    final cLightGrey = PdfColor.fromHex('F9FAFB');
    final cBorder    = PdfColor.fromHex('E5E7EB');
    final cTotal     = PdfColor.fromHex('1F2937');

    final bodyStyle       = pw.TextStyle(fontSize: 9, color: cGrey);
    final boldStyle       = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black);
    final headerCellStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: cWhite);
    final dataCellStyle   = pw.TextStyle(fontSize: 8.5, color: PdfColors.black);

    pw.Widget hCell(String t, {pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(t, style: headerCellStyle, textAlign: align),
        );

    pw.Widget dCell(String t,
            {pw.TextAlign align = pw.TextAlign.left, bool bold = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(t,
              style: bold ? boldStyle : dataCellStyle, textAlign: align),
        );

    final itemRows = List.generate(validItems.length, (i) {
      final item = validItems[i];
      return pw.TableRow(
        decoration: pw.BoxDecoration(color: i.isEven ? cWhite : cLightGrey),
        children: [
          dCell('${i + 1}', align: pw.TextAlign.center),
          dCell(item.nameCtrl.text.trim()),
          dCell(item.sizeCtrl.text.trim().isEmpty
              ? '—'
              : item.sizeCtrl.text.trim()),
          dCell(
              item.qty == item.qty.truncateToDouble()
                  ? item.qty.toStringAsFixed(0)
                  : item.qty.toStringAsFixed(2),
              align: pw.TextAlign.center),
          dCell('₹${fmt.format(item.rate)}', align: pw.TextAlign.right),
          dCell('₹${fmt.format(item.amount)}',
              align: pw.TextAlign.right, bold: true),
        ],
      );
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Center(
            child: pw.Text('BILL',
                style: pw.TextStyle(
                    fontSize: 32,
                    fontWeight: pw.FontWeight.bold,
                    color: cDark,
                    letterSpacing: 6)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Container(width: 60, height: 3, color: cAccent)),
          pw.SizedBox(height: 20),

          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: cDark,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _bizNameCtrl.text.trim().toUpperCase(),
                      style: pw.TextStyle(
                          color: cWhite,
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.5),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(_bizAddressCtrl.text.trim(),
                        style: pw.TextStyle(
                            color: PdfColor.fromHex('9CA3AF'), fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Bill No: ${_billNoCtrl.text.trim()}',
                        style: pw.TextStyle(
                            color: cWhite,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Date: $date',
                        style: pw.TextStyle(
                            color: PdfColor.fromHex('9CA3AF'), fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: cAccentBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: cAccentBdr),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BILL TO',
                    style: pw.TextStyle(
                        color: cAccent,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.2)),
                pw.SizedBox(height: 5),
                pw.Text(
                  _clientNameCtrl.text.trim().isEmpty
                      ? '—'
                      : _clientNameCtrl.text.trim(),
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: cTotal),
                ),
                if (_clientAddressCtrl.text.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(_clientAddressCtrl.text.trim(), style: bodyStyle),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 18),

          pw.Text('ITEMS',
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: cGrey,
                  letterSpacing: 1.2)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder(
              bottom: pw.BorderSide(color: cBorder),
              horizontalInside: pw.BorderSide(color: cBorder, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FixedColumnWidth(22),
              1: pw.FlexColumnWidth(3.0),
              2: pw.FlexColumnWidth(1.5),
              3: pw.FixedColumnWidth(34),
              4: pw.FlexColumnWidth(1.8),
              5: pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: cAccent),
                children: [
                  hCell('#', align: pw.TextAlign.center),
                  hCell('Item Name'),
                  hCell('Size'),
                  hCell('Qty', align: pw.TextAlign.center),
                  hCell('Rate', align: pw.TextAlign.right),
                  hCell('Amount', align: pw.TextAlign.right),
                ],
              ),
              ...itemRows,
            ],
          ),
          pw.SizedBox(height: 16),

          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Subtotal', style: bodyStyle),
                      pw.Text('₹${fmt.format(_subtotal)}', style: boldStyle),
                    ],
                  ),
                  if (_taxRate > 0) ...[
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                            'Tax (${_taxRate.toStringAsFixed(_taxRate == _taxRate.truncateToDouble() ? 0 : 1)}%)',
                            style: bodyStyle),
                        pw.Text('₹${fmt.format(_taxAmount)}',
                            style: boldStyle),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                  ],
                  pw.Container(height: 1, color: cBorder),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL',
                          style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: cTotal)),
                      pw.Text('₹${fmt.format(_grandTotal)}',
                          style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: cAccent)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 28),

          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: pw.BoxDecoration(
              color: cLightGrey,
              border: pw.Border.all(color: cBorder),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Center(
              child: pw.Text(
                'Thank you for your business — ${_bizNameCtrl.text.trim()}',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: cGrey,
                    fontStyle: pw.FontStyle.italic),
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Save + Open PDF ────────────────────────────────────────────────────────

  Future<void> _generateBill() async {
    if (_generating) return;
    if (!_validate()) return;

    setState(() => _generating = true);
    HapticFeedback.mediumImpact();

    try {
      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId == null) throw Exception('No active cashbook');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      // 1. Generate PDF bytes locally (fast — no network)
      final pdfBytes = await _buildPdfBytes();

      // 2. Create the bill ID upfront
      final billId = FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('custom_bills')
          .doc()
          .id;

      final validItems = _items
          .where((i) => i.nameCtrl.text.trim().isNotEmpty)
          .map((i) => i.toBillItem())
          .toList();

      // ▶ FIX 2: open the PDF from a local temp file IMMEDIATELY —
      //   no waiting for Firebase Storage upload.
      if (!kIsWeb) {
        final tempDir  = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/bill_$billId.pdf');
        await tempFile.writeAsBytes(pdfBytes);
        if (mounted) {
          openNativePdfInApp(
              context, tempFile.path, _billNoCtrl.text.trim(), _clientNameCtrl.text.trim());
        }
      }

      if (mounted) _showSnack('Bill saved! Uploading PDF…', success: true);

      // 3. Upload to Firebase Storage in the background
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('cashbooks/$cashbookId/custom_bills/$billId.pdf');

      await storageRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final pdfUrl = await storageRef.getDownloadURL();

      // 4. Save CustomBillModel to Firestore
      final bill = CustomBillModel(
        billId:          billId,
        billNumber:      _billNoCtrl.text.trim(),
        billDate:        _billDate,
        businessName:    _bizNameCtrl.text.trim(),
        businessAddress: _bizAddressCtrl.text.trim(),
        clientName:      _clientNameCtrl.text.trim(),
        clientAddress:   _clientAddressCtrl.text.trim(),
        items:           validItems,
        taxRate:         _taxRate,
        subtotal:        _subtotal,
        taxAmount:       _taxAmount,
        grandTotal:      _grandTotal,
        pdfUrl:          pdfUrl,
        createdAt:       DateTime.now(),
        createdBy:       user.uid,
        createdByName:   user.displayName ?? '',
      );

      await ref.read(customBillActionsProvider.notifier).saveBill(
            cashbookId: cashbookId,
            bill: bill,
          );

      // 5. Sync to Sales party if client name matches
      await _syncToSalesParty(
        cashbookId: cashbookId,
        billId:     billId,
        user:       user,
      );

      // 6. On web, open after upload (no temp-file option on web)
      if (kIsWeb && mounted) {
        openPdfInApp(context, pdfUrl, bill.billNumber, bill.clientName);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', success: false);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _syncToSalesParty({
    required String cashbookId,
    required String billId,
    required User user,
  }) async {
    final clientName = _clientNameCtrl.text.trim();
    if (clientName.isEmpty) return;

    final parties = ref.read(partiesProvider).asData?.value ?? [];
    final match = parties.firstWhere(
      (p) => p.partyName.trim().toLowerCase() == clientName.toLowerCase(),
      orElse: () => PartyEntity.nameOnly(''),
    );
    if (match.partyId.isEmpty) return;

    final saleBill = SaleBillModel(
      saleBillId:        billId,
      partyName:         clientName,
      billNumber:        _billNoCtrl.text.trim(),
      billTotal:         _grandTotal,
      billDate:          _billDate,
      billNote:          'Created from Bill Maker',
      billCreatedAt:     DateTime.now(),
      billCreatedBy:     user.uid,
      billCreatedByName: user.displayName ?? '',
      billStatus:        'pending',
    );

    await FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('sale_bills')
        .doc(billId)
        .set(saleBill.toFirestore());
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        backgroundColor: success ? _T.green : _T.red,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final partyNames = ref.watch(partiesProvider).asData?.value
            ?.map((p) => p.partyName)
            .toList() ??
        const <String>[];

    final fmt     = NumberFormat('#,##,##0.00', 'en_IN');
    final dateFmt = DateFormat('dd MMM yyyy');
    final bottom  = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: _T.bg,
      appBar: AppBar(
        backgroundColor: _T.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _T.text, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Bill',
          style: TextStyle(
              color: _T.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollCtrl,
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottom),
          children: [
            // ── Business Info ──────────────────────────────────────────────
            _SectionHeader(
                icon: Icons.store_rounded,
                label: 'Business Info',
                color: const Color(0xFF6C7FE4)),
            const SizedBox(height: 10),
            _FieldCard(
              child: Column(
                children: [
                  _buildField(
                      controller: _bizNameCtrl,
                      label: 'Business Name',
                      icon: Icons.business_rounded,
                      required: true),
                  const _FieldDivider(),
                  _buildField(
                      controller: _bizAddressCtrl,
                      label: 'Business Address',
                      icon: Icons.location_on_rounded,
                      maxLines: 2),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Bill Details ───────────────────────────────────────────────
            _SectionHeader(
                icon: Icons.receipt_rounded,
                label: 'Bill Details',
                color: const Color(0xFF38D68A)),
            const SizedBox(height: 10),
            _FieldCard(
              child: Column(
                children: [
                  _buildField(
                      controller: _billNoCtrl,
                      label: 'Bill Number',
                      icon: Icons.tag_rounded,
                      hint: 'e.g. 001',
                      required: true),
                  const _FieldDivider(),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              color: _T.muted, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Bill Date',
                                    style: TextStyle(
                                        color: _T.muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(dateFmt.format(_billDate),
                                    style: const TextStyle(
                                        color: _T.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: _T.muted, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Client Info ────────────────────────────────────────────────
            _SectionHeader(
                icon: Icons.person_rounded,
                label: 'Client Info',
                color: const Color(0xFFF5A623)),
            const SizedBox(height: 10),
            _FieldCard(
              child: Column(
                children: [
                  // ▶ FIX 1: pass the stored _clientFocusNode instead of
                  //   creating a new FocusNode() on every build().
                  RawAutocomplete<String>(
                    textEditingController: _clientNameCtrl,
                    focusNode: _clientFocusNode,
                    optionsBuilder: (textEditingValue) {
                      final input =
                          textEditingValue.text.trim().toLowerCase();
                      if (input.isEmpty) return const Iterable.empty();
                      return partyNames
                          .where((n) => n.toLowerCase().contains(input));
                    },
                    onSelected: (selection) {
                      _clientNameCtrl.text = selection;
                      _clientNameCtrl.selection = TextSelection.collapsed(
                          offset: selection.length);
                      if (mounted) setState(() {});
                    },
                    fieldViewBuilder:
                        (ctx, ctrl, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: ctrl,
                        focusNode: focusNode,
                        style: const TextStyle(
                            color: _T.text, fontSize: 14),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                        decoration: InputDecoration(
                          labelText: 'Client Name',
                          hintText: 'Type or select existing party',
                          labelStyle: const TextStyle(
                              color: _T.muted, fontSize: 12),
                          hintStyle: const TextStyle(
                              color: _T.muted, fontSize: 13),
                          prefixIcon: const Icon(
                              Icons.person_outline_rounded,
                              color: _T.muted,
                              size: 18),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        onFieldSubmitted: (_) => onFieldSubmitted(),
                      );
                    },
                    optionsViewBuilder: (ctx, onSelected, options) =>
                        Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          constraints: const BoxConstraints(
                              maxHeight: 200, maxWidth: 340),
                          decoration: BoxDecoration(
                            color: _T.card2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _T.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(6),
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (_, i) {
                              final name = options.elementAt(i);
                              return InkWell(
                                onTap: () => onSelected(name),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person_rounded,
                                          color: _T.accent, size: 14),
                                      const SizedBox(width: 8),
                                      Text(name,
                                          style: const TextStyle(
                                              color: _T.text,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _FieldDivider(),
                  _buildField(
                      controller: _clientAddressCtrl,
                      label: 'Client Address (optional)',
                      icon: Icons.location_on_outlined,
                      maxLines: 2),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Items ──────────────────────────────────────────────────────
            Row(
              children: [
                _SectionHeader(
                    icon: Icons.inventory_2_rounded,
                    label: 'Items',
                    color: const Color(0xFF8B5CF6)),
                const Spacer(),
                GestureDetector(
                  onTap: _addItem,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            color: Color(0xFF8B5CF6), size: 15),
                        SizedBox(width: 4),
                        Text('Add Item',
                            style: TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            ...List.generate(_items.length, (index) {
              return _ItemCard(
                index: index,
                item: _items[index],
                canRemove: _items.length > 1,
                onRemove: () => _removeItem(index),
                onChanged: _rebuildTotals,
                fmt: fmt,
              )
                  .animate()
                  .fadeIn(duration: 200.ms)
                  .slideY(begin: 0.05, end: 0, curve: Curves.easeOut);
            }),

            const SizedBox(height: 10),
            GestureDetector(
              onTap: _addItem,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _T.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _T.border),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        color: _T.muted, size: 18),
                    SizedBox(width: 8),
                    Text('Add Another Item',
                        style: TextStyle(
                            color: _T.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Tax ────────────────────────────────────────────────────────
            _SectionHeader(
                icon: Icons.percent_rounded,
                label: 'Tax',
                color: const Color(0xFF3B82F6)),
            const SizedBox(height: 10),
            _FieldCard(
              child: _buildField(
                  controller: _taxRateCtrl,
                  label: 'Tax Rate (%)',
                  icon: Icons.percent_rounded,
                  hint: '0',
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*'))
                  ]),
            ),
            const SizedBox(height: 20),

            // ── Totals ─────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _T.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _T.border),
              ),
              child: Column(
                children: [
                  _TotalRow(
                      label: 'Subtotal',
                      value: '₹${fmt.format(_subtotal)}'),
                  if (_taxRate > 0) ...[
                    const SizedBox(height: 8),
                    _TotalRow(
                        label:
                            'Tax (${_taxRate.toStringAsFixed(_taxRate == _taxRate.truncateToDouble() ? 0 : 1)}%)',
                        value: '₹${fmt.format(_taxAmount)}'),
                  ],
                  const SizedBox(height: 12),
                  const Divider(color: _T.divider, height: 1),
                  const SizedBox(height: 12),
                  _TotalRow(
                    label: 'Grand Total',
                    value: '₹${fmt.format(_grandTotal)}',
                    isBold: true,
                    valueColor: _T.accent,
                    labelFontSize: 15,
                    valueFontSize: 18,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Generate Button ────────────────────────────────────────────
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _generating ? null : _generateBill,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _T.accent,
                  disabledBackgroundColor:
                      _T.accent.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _generating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text('Generate Bill PDF',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              )),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Field builder ──────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: _T.text, fontSize: 14),
      textCapitalization: keyboardType == TextInputType.text
          ? TextCapitalization.words
          : TextCapitalization.none,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _T.muted, fontSize: 12),
        hintStyle: const TextStyle(color: _T.muted, fontSize: 13),
        prefixIcon: Icon(icon, color: _T.muted, size: 18),
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        errorStyle: const TextStyle(color: _T.red, fontSize: 11),
      ),
    );
  }
}

// ── Item Card ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatefulWidget {
  final int index;
  final _ItemState item;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final NumberFormat fmt;

  const _ItemCard({
    required this.index,
    required this.item,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    required this.fmt,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  @override
  Widget build(BuildContext context) {
    final amount = widget.item.amount;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: Text('${widget.index + 1}',
                        style: const TextStyle(
                            color: Color(0xFF8B5CF6),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.item.nameCtrl.text.trim().isEmpty
                      ? 'Item ${widget.index + 1}'
                      : widget.item.nameCtrl.text.trim(),
                  style: const TextStyle(
                      color: _T.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (amount > 0)
                  Text('₹${widget.fmt.format(amount)}',
                      style: const TextStyle(
                          color: _T.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (widget.canRemove)
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.remove_circle_outline_rounded,
                          color: _T.red, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: _T.border, height: 16),

          _ItemField(
            controller: widget.item.nameCtrl,
            label: 'Item Name',
            icon: Icons.inventory_2_outlined,
            required: true,
            onChanged: (_) => widget.onChanged(),
          ),
          const _FieldDivider(),
          _ItemField(
            controller: widget.item.sizeCtrl,
            label: 'Size (optional)',
            icon: Icons.straighten_rounded,
            hint: 'e.g. XL, 42, 2kg',
            onChanged: (_) => widget.onChanged(),
          ),
          const _FieldDivider(),
          Row(
            children: [
              Expanded(
                child: _ItemField(
                  controller: widget.item.qtyCtrl,
                  label: 'Quantity',
                  icon: Icons.numbers_rounded,
                  hint: '0',
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*'))
                  ],
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              Container(width: 1, height: 48, color: _T.border),
              Expanded(
                child: _ItemField(
                  controller: widget.item.rateCtrl,
                  label: 'Rate (₹)',
                  icon: Icons.currency_rupee_rounded,
                  hint: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*'))
                  ],
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ItemField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final bool required;
  final int maxLines;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const _ItemField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: const TextStyle(color: _T.text, fontSize: 13.5),
      textCapitalization: keyboardType == TextInputType.text
          ? TextCapitalization.words
          : TextCapitalization.none,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _T.muted, fontSize: 11),
        hintStyle: const TextStyle(color: _T.muted, fontSize: 12),
        prefixIcon: Icon(icon, color: _T.muted, size: 16),
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: _T.muted2,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  final Widget child;
  const _FieldCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.border),
      ),
      child: child,
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(color: _T.border, height: 1, indent: 16);
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;
  final double labelFontSize;
  final double valueFontSize;

  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
    this.labelFontSize = 13,
    this.valueFontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: isBold ? _T.text : _T.muted2,
                fontSize: labelFontSize,
                fontWeight:
                    isBold ? FontWeight.w700 : FontWeight.w500)),
        Text(value,
            style: TextStyle(
                color: valueColor ?? _T.text,
                fontSize: valueFontSize,
                fontWeight:
                    isBold ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.3)),
      ],
    );
  }
}
