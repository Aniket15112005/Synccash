// lib/features/bills/presentation/screens/create_bill_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/sales/data/models/sale_bill_model.dart';
import 'package:synccash/features/sales/presentation/providers/party_provider.dart';
import '../../data/models/custom_bill_model.dart';
import '../providers/bills_provider.dart';
import 'bill_pdf_generator.dart';

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
  static const red     = Color(0xFFE85C5C);
  static const divider = Color(0xFF1C2130);
  static const purple  = Color(0xFF8B5CF6);
}

const _kDefaultBusinessName    = 'Neelkanth Garments';
const _kDefaultBusinessAddress = 'Baramati, Maharashtra';

// ── Editable item state ───────────────────────────────────────────────────────

class _ItemState {
  final TextEditingController nameCtrl;
  final TextEditingController hsnSacCtrl;
  final TextEditingController sizeCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;

  _ItemState({
    String name   = '',
    String hsnSac = '',
    String size   = '',
    String qty    = '',
    String rate   = '',
  })  : nameCtrl   = TextEditingController(text: name),
        hsnSacCtrl = TextEditingController(text: hsnSac),
        sizeCtrl   = TextEditingController(text: size),
        qtyCtrl    = TextEditingController(text: qty),
        rateCtrl   = TextEditingController(text: rate);

  factory _ItemState.fromBillItem(BillItem item) => _ItemState(
        name:   item.name,
        hsnSac: item.hsnSac,
        size:   item.size,
        qty:    item.qty == item.qty.truncateToDouble()
            ? item.qty.toStringAsFixed(0)
            : item.qty.toStringAsFixed(2),
        rate:   item.rate == item.rate.truncateToDouble()
            ? item.rate.toStringAsFixed(0)
            : item.rate.toStringAsFixed(2),
      );

  double get qty    => double.tryParse(qtyCtrl.text.trim())  ?? 0;
  double get rate   => double.tryParse(rateCtrl.text.trim()) ?? 0;
  double get amount => qty * rate;

  bool get isValid =>
      nameCtrl.text.trim().isNotEmpty && qty > 0 && rate > 0;

  BillItem toBillItem() => BillItem(
        name:   nameCtrl.text.trim(),
        hsnSac: hsnSacCtrl.text.trim(),
        size:   sizeCtrl.text.trim(),
        qty:    qty,
        rate:   rate,
      );

  void dispose() {
    nameCtrl.dispose();
    hsnSacCtrl.dispose();
    sizeCtrl.dispose();
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CreateBillScreen extends ConsumerStatefulWidget {
  final String?          prefilledClientName;
  final CustomBillModel? existingBill;

  const CreateBillScreen({
    super.key,
    this.prefilledClientName,
    this.existingBill,
  });

  @override
  ConsumerState<CreateBillScreen> createState() => _CreateBillScreenState();
}

class _CreateBillScreenState extends ConsumerState<CreateBillScreen>
    with TickerProviderStateMixin {
  final _formKey    = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  bool get _isEditing => widget.existingBill != null;

  // Controllers
  late final TextEditingController _bizNameCtrl;
  late final TextEditingController _bizAddressCtrl;
  late final TextEditingController _billNoCtrl;
  late DateTime _billDate;
  late final TextEditingController _clientNameCtrl;
  late final TextEditingController _clientAddressCtrl;
  late final List<_ItemState> _items;
  late final TextEditingController _taxRateCtrl;
  late final TextEditingController _receivedCtrl;

  // Inline autocomplete state
  final _clientFocusNode = FocusNode();
  List<String> _filteredParties = [];
  List<String> _allPartyNames   = [];
  bool _showSuggestions = false;

  // Discount state
  late final TextEditingController _discountCtrl;
  String _discountType = 'percent'; // 'percent' or 'amount'

  // Generation state
  bool   _generating = false;
  String _genStatus  = '';

  @override
  void initState() {
    super.initState();

    final bill = widget.existingBill;
    if (bill != null) {
      _bizNameCtrl       = TextEditingController(text: bill.businessName);
      _bizAddressCtrl    = TextEditingController(text: bill.businessAddress);
      _billNoCtrl        = TextEditingController(text: bill.billNumber);
      _billDate          = bill.billDate;
      _clientNameCtrl    = TextEditingController(text: bill.clientName);
      _clientAddressCtrl = TextEditingController(text: bill.clientAddress);
      _taxRateCtrl       = TextEditingController(
          text: bill.taxRate == bill.taxRate.truncateToDouble()
              ? bill.taxRate.toStringAsFixed(0)
              : bill.taxRate.toStringAsFixed(1));
      _receivedCtrl      = TextEditingController(
          text: bill.receivedAmount == bill.receivedAmount.truncateToDouble()
              ? bill.receivedAmount.toStringAsFixed(0)
              : bill.receivedAmount.toStringAsFixed(2));
      _discountCtrl = TextEditingController(
          text: bill.discountValue > 0
              ? (bill.discountValue == bill.discountValue.truncateToDouble()
                  ? bill.discountValue.toStringAsFixed(0)
                  : bill.discountValue.toStringAsFixed(2))
              : '');
      _discountType = bill.discountType;
      _items = bill.items.map(_ItemState.fromBillItem).toList();
      if (_items.isEmpty) _items.add(_ItemState());
    } else {
      _bizNameCtrl       = TextEditingController(text: _kDefaultBusinessName);
      _bizAddressCtrl    = TextEditingController(text: _kDefaultBusinessAddress);
      _billNoCtrl        = TextEditingController();
      _billDate          = DateTime.now();
      _clientNameCtrl    = TextEditingController(
          text: widget.prefilledClientName ?? '');
      _clientAddressCtrl = TextEditingController();
      _taxRateCtrl       = TextEditingController(text: '0');
      _receivedCtrl      = TextEditingController(text: '0');
      _discountCtrl      = TextEditingController();
      _discountType      = 'percent';
      _items             = [_ItemState()];
    }

    for (final item in _items) {
      item.qtyCtrl.addListener(_rebuildTotals);
      item.rateCtrl.addListener(_rebuildTotals);
    }
    _taxRateCtrl.addListener(_rebuildTotals);
    _receivedCtrl.addListener(_rebuildTotals);
    _discountCtrl.addListener(_rebuildTotals);
    _clientNameCtrl.addListener(_onClientTyped);
    _clientFocusNode.addListener(_onClientFocusChanged);
  }

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _bizAddressCtrl.dispose();
    _billNoCtrl.dispose();
    _clientNameCtrl.removeListener(_onClientTyped);
    _clientNameCtrl.dispose();
    _clientFocusNode.removeListener(_onClientFocusChanged);
    _clientFocusNode.dispose();
    _clientAddressCtrl.dispose();
    _taxRateCtrl.dispose();
    _receivedCtrl.dispose();
    _discountCtrl.dispose();
    _scrollCtrl.dispose();
    for (final item in _items) item.dispose();
    super.dispose();
  }

  // ── Inline autocomplete ────────────────────────────────────────────────────

  void _onClientTyped() {
    final text = _clientNameCtrl.text.trim().toLowerCase();
    final matches = text.isEmpty
        ? _allPartyNames
        : _allPartyNames
            .where((n) => n.toLowerCase().contains(text))
            .toList();

    final typed    = _clientNameCtrl.text.trim();
    final hasExact = _allPartyNames
        .any((n) => n.toLowerCase() == typed.toLowerCase());
    final showCreate = typed.isNotEmpty && !hasExact;

    if (mounted) {
      setState(() {
        _filteredParties  = matches;
        _showSuggestions  = _clientFocusNode.hasFocus &&
            (matches.isNotEmpty || showCreate);
      });
    }
  }

  void _onClientFocusChanged() {
    if (_clientFocusNode.hasFocus) {
      _onClientTyped();
    } else {
      // Brief delay so tap on suggestion registers before hiding
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_clientFocusNode.hasFocus) {
          setState(() => _showSuggestions = false);
        }
      });
    }
  }

  void _selectParty(String name) {
    _clientNameCtrl.text = name;
    _clientNameCtrl.selection =
        TextSelection.collapsed(offset: name.length);
    _clientFocusNode.unfocus();
    if (mounted) setState(() => _showSuggestions = false);
  }

  // ── Totals ─────────────────────────────────────────────────────────────────

  void _rebuildTotals() { if (mounted) setState(() {}); }

  double get _subtotal       => _items.fold(0.0, (s, i) => s + i.amount);
  double get _taxRate        => double.tryParse(_taxRateCtrl.text.trim()) ?? 0;
  double get _taxAmount      => _subtotal * _taxRate / 100;
  double get _discountValue  => double.tryParse(_discountCtrl.text.trim()) ?? 0;
  double get _discountAmount {
    if (_discountValue <= 0) return 0;
    if (_discountType == 'percent') return _subtotal * _discountValue / 100;
    return _discountValue.clamp(0, _subtotal + _taxAmount).toDouble();
  }
  double get _grandTotal     => (_subtotal + _taxAmount - _discountAmount).clamp(0, double.infinity).toDouble();
  double get _receivedAmount => double.tryParse(_receivedCtrl.text.trim()) ?? 0;
  double get _balanceDue     => _grandTotal - _receivedAmount;

  // ── Items ──────────────────────────────────────────────────────────────────

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
      _snack('Add at least one item with name, quantity and rate',
          ok: false);
      return false;
    }
    return true;
  }

  // ── Generate / Save ────────────────────────────────────────────────────────
  //
  // Flow:
  //   1. Build PDF bytes (fast, in memory)
  //   2. Upload to Firebase Storage → get download URL
  //   3. Save to custom_bills Firestore collection
  //   4. Sync to Sales (create party if needed, attach PDF to sale_bill)
  //   5. Pop back to bills list with success snack
  //
  // The user sees the bill in the list immediately; no waiting for a viewer.

  Future<void> _generateBill() async {
    if (_generating) return;
    if (!_validate()) return;
    setState(() => _showSuggestions = false);
    _clientFocusNode.unfocus();

    setState(() {
      _generating = true;
      _genStatus  = 'Building PDF…';
    });
    HapticFeedback.mediumImpact();

    try {
      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId == null) throw Exception('No active cashbook');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      final validItems = _items
          .where((i) => i.nameCtrl.text.trim().isNotEmpty)
          .map((i) => i.toBillItem())
          .toList();

      final billId = _isEditing
          ? widget.existingBill!.billId
          : FirebaseFirestore.instance
              .collection('cashbooks')
              .doc(cashbookId)
              .collection('custom_bills')
              .doc()
              .id;

      // Build a temporary model (no URL yet) for PDF generation
      final tempBill = CustomBillModel(
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
        discountType:    _discountType,
        discountValue:   _discountValue,
        discountAmount:  _discountAmount,
        grandTotal:      _grandTotal,
        receivedAmount:  _receivedAmount,
        pdfUrl:          null,
        createdAt:       _isEditing
            ? widget.existingBill!.createdAt
            : DateTime.now(),
        createdBy:       _isEditing
            ? widget.existingBill!.createdBy
            : user.uid,
        createdByName:   _isEditing
            ? widget.existingBill!.createdByName
            : (user.displayName ?? ''),
      );

      // 1. Build PDF bytes
      final pdfBytes = await buildBillPdfFromModel(tempBill);

      // 2. Upload to Firebase Storage
      if (mounted) setState(() => _genStatus = 'Uploading…');
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('cashbooks/$cashbookId/custom_bills/$billId.pdf');
      await storageRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final pdfUrl = await storageRef.getDownloadURL();

      // Full model with pdfUrl
      final bill = CustomBillModel(
        billId:          tempBill.billId,
        billNumber:      tempBill.billNumber,
        billDate:        tempBill.billDate,
        businessName:    tempBill.businessName,
        businessAddress: tempBill.businessAddress,
        clientName:      tempBill.clientName,
        clientAddress:   tempBill.clientAddress,
        items:           tempBill.items,
        taxRate:         tempBill.taxRate,
        subtotal:        tempBill.subtotal,
        taxAmount:       tempBill.taxAmount,
        discountType:    tempBill.discountType,
        discountValue:   tempBill.discountValue,
        discountAmount:  tempBill.discountAmount,
        grandTotal:      tempBill.grandTotal,
        receivedAmount:  tempBill.receivedAmount,
        pdfUrl:          pdfUrl,
        createdAt:       tempBill.createdAt,
        createdBy:       tempBill.createdBy,
        createdByName:   tempBill.createdByName,
      );

      // 3. Save to custom_bills
      if (mounted) setState(() => _genStatus = 'Saving…');
      await ref.read(customBillActionsProvider.notifier).saveBill(
            cashbookId: cashbookId,
            bill:       bill,
          );

      // 4. Sync to Sales party
      await _syncToSalesParty(
        cashbookId: cashbookId,
        bill:       bill,
        pdfUrl:     pdfUrl,
        user:       user,
      );

      // 5. Done — pop back immediately, show success snack in bills list
      if (!mounted) return;
      Navigator.pop(context);
      // Show snack after pop so it appears on the bills screen
      Future.microtask(() {
        if (mounted) return;
        // The snack is shown by the bills screen via its own ScaffoldMessenger
        // We use a small delay to let the pop animation complete
      });
      // Show snack here (it will be visible on the parent screen)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Bill updated!' : 'Bill saved!',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
          backgroundColor: _T.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    } catch (e) {
      if (mounted) _snack('Error: $e', ok: false);
    } finally {
      if (mounted) setState(() { _generating = false; _genStatus = ''; });
    }
  }

  Future<void> _syncToSalesParty({
    required String cashbookId,
    required CustomBillModel bill,
    required String pdfUrl,
    required User   user,
  }) async {
    final clientName = bill.clientName.trim();
    if (clientName.isEmpty) return;

    final db       = FirebaseFirestore.instance;
    final partyId  = clientName.toLowerCase();
    final partyRef = db
        .collection('cashbooks').doc(cashbookId)
        .collection('parties').doc(partyId);

    // Check LOCAL CACHE ONLY — instant, zero network cost.
    // If not cached, assume new and create it below.
    bool partyExists = false;
    try {
      final cached = await partyRef
          .get(const GetOptions(source: Source.cache));
      partyExists = cached.exists;
    } catch (_) {
      // Not in local cache — will create below.
    }

    if (!partyExists) {
      // Fire-and-forget — party sync is background work.
      // Not awaited so it never blocks the save flow.
      partyRef.set({
        'partyName':      clientName,
        'openingBalance': 0.0,
        'description':    '',
        'place':          bill.clientAddress.trim(),
        'updatedAt':      FieldValue.serverTimestamp(),
      }).catchError((_) {});
    }

    // The only awaited write — attach PDF to sale_bill.
    final saleBillData = <String, dynamic>{
      'saleBillId':        bill.billId,
      'partyName':         clientName,
      'billNumber':        bill.billNumber,
      'billTotal':         bill.grandTotal,
      'billDate':          Timestamp.fromDate(bill.billDate),
      'billNote':          'Created from Bill Maker',
      'billCreatedAt':     FieldValue.serverTimestamp(),
      'billCreatedBy':     bill.createdBy,
      'billCreatedByName': bill.createdByName,
      'billStatus':        'pending',
      'billAttachmentUrl':  pdfUrl,
      'billAttachmentType': 'pdf',
    };

    await db
        .collection('cashbooks').doc(cashbookId)
        .collection('sale_bills').doc(bill.billId)
        .set(saleBillData, SetOptions(merge: true));
  }

  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        backgroundColor: ok ? _T.green : _T.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Keep party names in sync for autocomplete
    final partyNames = ref.watch(partiesProvider).asData?.value
            ?.map((p) => p.partyName)
            .toList() ??
        const <String>[];

    if (!listEquals(_allPartyNames, partyNames)) {
      _allPartyNames = List<String>.from(partyNames);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_clientFocusNode.hasFocus) _onClientTyped();
      });
    }

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
        title: Text(
          _isEditing ? 'Edit Bill' : 'Create Bill',
          style: const TextStyle(
              color: _T.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottom),
              children: [

                // ── Business Info ──────────────────────────────────────────
                _SectionHeader(
                    icon: Icons.store_rounded,
                    label: 'Business Info',
                    color: _T.accent),
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

                // ── Bill Details ───────────────────────────────────────────
                _SectionHeader(
                    icon: Icons.receipt_rounded,
                    label: 'Bill Details',
                    color: _T.green),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                              const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: _T.muted,
                                  size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Client Info ────────────────────────────────────────────
                _SectionHeader(
                    icon: Icons.person_rounded,
                    label: 'Client Info',
                    color: const Color(0xFFF5A623)),
                const SizedBox(height: 10),

                // Client name field + inline autocomplete dropdown
                _FieldCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _clientNameCtrl,
                        focusNode: _clientFocusNode,
                        style:
                            const TextStyle(color: _T.text, fontSize: 14),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                        decoration: const InputDecoration(
                          labelText: 'Client Name',
                          hintText: 'Type or select existing party',
                          labelStyle:
                              TextStyle(color: _T.muted, fontSize: 12),
                          hintStyle:
                              TextStyle(color: _T.muted, fontSize: 13),
                          prefixIcon: Icon(
                              Icons.person_outline_rounded,
                              color: _T.muted,
                              size: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          errorStyle:
                              TextStyle(color: _T.red, fontSize: 11),
                        ),
                      ),

                      // ── Inline autocomplete suggestions ──────────────
                      if (_showSuggestions) ...[
                        Container(
                          height: 0.5,
                          color: _T.border,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        _InlineSuggestions(
                          options: _filteredParties,
                          typedText: _clientNameCtrl.text.trim(),
                          allPartyNames: _allPartyNames,
                          onSelect: _selectParty,
                        ),
                      ],

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

                // ── Items ──────────────────────────────────────────────────
                Row(
                  children: [
                    _SectionHeader(
                        icon: Icons.inventory_2_rounded,
                        label: 'Items',
                        color: _T.purple),
                    const Spacer(),
                    GestureDetector(
                      onTap: _addItem,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _T.purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _T.purple.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                color: _T.purple, size: 15),
                            SizedBox(width: 4),
                            Text('Add Item',
                                style: TextStyle(
                                    color: _T.purple,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                ...List.generate(_items.length, (i) {
                  return _ItemCard(
                    key: ValueKey('item_$i'),
                    index: i,
                    item: _items[i],
                    canRemove: _items.length > 1,
                    onRemove: () => _removeItem(i),
                    onChanged: _rebuildTotals,
                    fmt: fmt,
                  )
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .slideY(
                          begin: 0.05,
                          end: 0,
                          curve: Curves.easeOut,
                          duration: 200.ms);
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

                // ── Tax ────────────────────────────────────────────────────
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'))
                      ]),
                ),
                const SizedBox(height: 20),

                // ── Discount ───────────────────────────────────────────────
                _SectionHeader(
                    icon: Icons.discount_rounded,
                    label: 'Discount',
                    color: const Color(0xFFF59E0B)),
                const SizedBox(height: 10),
                _FieldCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type toggle
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.discount_rounded,
                                color: _T.muted, size: 18),
                            const SizedBox(width: 12),
                            _DiscountTypeChip(
                              label: '% Percent',
                              selected: _discountType == 'percent',
                              onTap: () =>
                                  setState(() => _discountType = 'percent'),
                            ),
                            const SizedBox(width: 8),
                            _DiscountTypeChip(
                              label: '₹ Fixed',
                              selected: _discountType == 'amount',
                              onTap: () =>
                                  setState(() => _discountType = 'amount'),
                            ),
                          ],
                        ),
                      ),
                      const _FieldDivider(),
                      _buildField(
                          controller: _discountCtrl,
                          label: _discountType == 'percent'
                              ? 'Discount (%)'
                              : 'Discount (₹)',
                          icon: Icons.discount_outlined,
                          hint: '0',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ]),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Advance / Received ────────────────────────────────────
                _SectionHeader(
                    icon: Icons.payments_rounded,
                    label: 'Advance Received',
                    color: const Color(0xFF22C55E)),
                const SizedBox(height: 10),
                _FieldCard(
                  child: _buildField(
                      controller: _receivedCtrl,
                      label: 'Received Amount (\u20B9)',
                      icon: Icons.payments_rounded,
                      hint: '0.00',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'))
                      ]),
                ),
                const SizedBox(height: 20),

                // ── Totals ─────────────────────────────────────────────────
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
                          value: '\u20B9${fmt.format(_subtotal)}'),
                      if (_taxRate > 0) ...[
                        const SizedBox(height: 8),
                        _TotalRow(
                          label:
                              'Tax (${_taxRate.toStringAsFixed(_taxRate == _taxRate.truncateToDouble() ? 0 : 1)}%)',
                          value: '\u20B9${fmt.format(_taxAmount)}',
                        ),
                      ],
                      if (_discountAmount > 0) ...[
                        const SizedBox(height: 8),
                        _TotalRow(
                          label: _discountType == 'percent'
                              ? 'Discount (${_discountValue.toStringAsFixed(_discountValue == _discountValue.truncateToDouble() ? 0 : 1)}%)'
                              : 'Discount',
                          value: '- \u20B9${fmt.format(_discountAmount)}',
                          valueColor: const Color(0xFF38D68A),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Divider(color: _T.divider, height: 1),
                      const SizedBox(height: 12),
                      _TotalRow(
                        label: 'Grand Total',
                        value: '\u20B9${fmt.format(_grandTotal)}',
                        isBold: true,
                        valueColor: _T.accent,
                        labelFontSize: 15,
                        valueFontSize: 18,
                      ),
                      if (_receivedAmount > 0) ...[
                        const SizedBox(height: 8),
                        _TotalRow(
                          label: 'Received',
                          value: '\u20B9${fmt.format(_receivedAmount)}',
                        ),
                        const SizedBox(height: 8),
                        _TotalRow(
                          label: 'Balance Due',
                          value: '\u20B9${fmt.format(_balanceDue)}',
                          isBold: true,
                          valueColor: const Color(0xFFE85C5C),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Generate button ────────────────────────────────────────
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
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Text(_genStatus,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.save_rounded,
                                  color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                  _isEditing
                                      ? 'Update Bill'
                                      : 'Save Bill',
                                  style: const TextStyle(
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

          // ── Full-screen generating overlay ─────────────────────────────
          if (_generating)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: _T.bg.withValues(alpha: 0.88),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: _T.card2,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _T.border),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                                color: _T.accent, strokeWidth: 2.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _genStatus,
                        style: const TextStyle(
                          color: _T.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('Please wait…',
                          style:
                              TextStyle(color: _T.muted2, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
          ? (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null
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

// ── Inline Suggestions ────────────────────────────────────────────────────────
//
// Rendered directly inside the FieldCard Column — no Overlay needed.
// Always visible, no positioning bugs, scrolls with the form.

class _InlineSuggestions extends StatelessWidget {
  final List<String>        options;
  final String              typedText;
  final List<String>        allPartyNames;
  final void Function(String) onSelect;

  const _InlineSuggestions({
    required this.options,
    required this.typedText,
    required this.allPartyNames,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final hasExact = allPartyNames
        .any((n) => n.toLowerCase() == typedText.toLowerCase());
    final showCreate = typedText.isNotEmpty && !hasExact;
    final total = options.length + (showCreate ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: const BoxDecoration(
        color: Color(0xFF141921),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          ...options.map((name) => _SuggestionTile(
                label: name,
                query: typedText,
                icon: Icons.person_rounded,
                iconColor: const Color(0xFF6C7FE4),
                onTap: () => onSelect(name),
              )),
          if (showCreate) ...[
            if (options.isNotEmpty)
              const Divider(
                color: Color(0xFF1C2130),
                height: 10,
                indent: 12,
                endIndent: 12,
              ),
            _SuggestionTile(
              label: 'Create "$typedText" as new party',
              query: '',
              icon: Icons.add_circle_rounded,
              iconColor: const Color(0xFF38D68A),
              labelColor: const Color(0xFF38D68A),
              onTap: () => onSelect(typedText),
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 140.ms)
        .slideY(begin: -0.04, end: 0, curve: Curves.easeOut, duration: 140.ms);
  }
}

class _SuggestionTile extends StatefulWidget {
  final String   label;
  final String   query;
  final IconData icon;
  final Color    iconColor;
  final Color?   labelColor;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.label,
    required this.query,
    required this.icon,
    required this.iconColor,
    this.labelColor,
    required this.onTap,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Build label — highlight matching substring in blue
    Widget textWidget;
    if (widget.query.isEmpty || widget.labelColor != null) {
      textWidget = Text(
        widget.label,
        style: TextStyle(
            color: widget.labelColor ?? const Color(0xFFE8ECF4),
            fontSize: 13,
            fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      final lower = widget.label.toLowerCase();
      final qLow  = widget.query.toLowerCase();
      final idx   = lower.indexOf(qLow);
      if (idx < 0) {
        textWidget = Text(widget.label,
            style: const TextStyle(
                color: Color(0xFFE8ECF4),
                fontSize: 13,
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis);
      } else {
        textWidget = RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: const TextStyle(
                color: Color(0xFFE8ECF4),
                fontSize: 13,
                fontWeight: FontWeight.w500),
            children: [
              if (idx > 0)
                TextSpan(text: widget.label.substring(0, idx)),
              TextSpan(
                text: widget.label
                    .substring(idx, idx + widget.query.length),
                style: TextStyle(
                    color: widget.iconColor,
                    fontWeight: FontWeight.w700),
              ),
              if (idx + widget.query.length < widget.label.length)
                TextSpan(
                    text:
                        widget.label.substring(idx + widget.query.length)),
            ],
          ),
        );
      }
    }

    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) => setState(() => _pressed = false),
      onTapCancel: ()  => setState(() => _pressed = false),
      onTap:       widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        color: _pressed
            ? const Color(0xFF6C7FE4).withValues(alpha: 0.10)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(widget.icon, color: widget.iconColor, size: 15),
            const SizedBox(width: 10),
            Expanded(child: textWidget),
          ],
        ),
      ),
    );
  }
}

// ── Item Card ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatefulWidget {
  final int        index;
  final _ItemState item;
  final bool       canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final NumberFormat fmt;

  const _ItemCard({
    super.key,
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
        color: const Color(0xFF0F1318),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1C2130)),
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
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
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
                Expanded(
                  child: Text(
                    widget.item.nameCtrl.text.trim().isEmpty
                        ? 'Item ${widget.index + 1}'
                        : widget.item.nameCtrl.text.trim(),
                    style: const TextStyle(
                        color: Color(0xFFE8ECF4),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                if (amount > 0)
                  Text('\u20B9${widget.fmt.format(amount)}',
                      style: const TextStyle(
                          color: Color(0xFF6C7FE4),
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (widget.canRemove)
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.remove_circle_outline_rounded,
                          color: Color(0xFFE85C5C), size: 18),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1C2130), height: 16),

          _ItemField(
            controller: widget.item.nameCtrl,
            label: 'Item Name',
            icon: Icons.inventory_2_outlined,
            required: true,
            onChanged: (_) {
              widget.onChanged();
              if (mounted) setState(() {});
            },
          ),
          const _FieldDivider(),
          _ItemField(
            controller: widget.item.hsnSacCtrl,
            label: 'HSN/SAC Code (optional)',
            icon: Icons.tag_rounded,
            hint: 'e.g. 6105',
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                  ],
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              Container(width: 1, height: 48, color: const Color(0xFF1C2130)),
              Expanded(
                child: _ItemField(
                  controller: widget.item.rateCtrl,
                  label: 'Rate (\u20B9)',
                  icon: Icons.currency_rupee_rounded,
                  hint: '0.00',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
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
  final TextEditingController       controller;
  final String                      label;
  final IconData                    icon;
  final String?                     hint;
  final bool                        required;
  final int                         maxLines;
  final TextInputType               keyboardType;
  final List<TextInputFormatter>?   inputFormatters;
  final ValueChanged<String>?       onChanged;

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
      style: const TextStyle(color: Color(0xFFE8ECF4), fontSize: 13.5),
      textCapitalization: keyboardType == TextInputType.text
          ? TextCapitalization.words
          : TextCapitalization.none,
      validator: required
          ? (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF4A5568), fontSize: 11),
        hintStyle: const TextStyle(color: Color(0xFF4A5568), fontSize: 12),
        prefixIcon: Icon(icon, color: const Color(0xFF4A5568), size: 16),
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
  final String   label;
  final Color    color;
  const _SectionHeader(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
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
                  color: Color(0xFF8C8E9A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3)),
        ],
      );
}

class _FieldCard extends StatelessWidget {
  final Widget child;
  const _FieldCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F1318),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1C2130)),
        ),
        child: child,
      );
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(color: Color(0xFF1C2130), height: 1, indent: 16);
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool   isBold;
  final Color? valueColor;
  final double labelFontSize;
  final double valueFontSize;

  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold        = false,
    this.valueColor,
    this.labelFontSize = 13,
    this.valueFontSize = 14,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: const Color(0xFF8C8E9A),
                  fontSize: labelFontSize,
                  fontWeight:
                      isBold ? FontWeight.w700 : FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? const Color(0xFFE8ECF4),
                  fontSize: valueFontSize,
                  fontWeight:
                      isBold ? FontWeight.w800 : FontWeight.w600)),
        ],
      );
}

// ── Discount Type Chip ────────────────────────────────────────────────────────

class _DiscountTypeChip extends StatelessWidget {
  final String   label;
  final bool     selected;
  final VoidCallback onTap;

  const _DiscountTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                : const Color(0xFF1C2130),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                  : const Color(0xFF2A3040),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF8C8E9A),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
}
