
// lib/features/purchases/presentation/screens/purchase_client_detail_screen.dart
//
// Mirrors lib/features/sales/presentation/screens/party_detail_screen.dart
// Bills are now tappable — tapping opens PurchaseClientBillDetailScreen.

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/purchase_bill_entity.dart';
import '../providers/purchase_client_provider.dart';
import '../providers/purchase_bill_provider.dart';
import 'purchase_client_bill_detail_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'web_invoice_viewer_stub.dart'
    if (dart.library.html) 'web_invoice_viewer_web.dart';

class _T {
  static const bg      = Color(0xFF0F1011);
  static const card    = Color(0xFF1A1B1E);
  static const card2   = Color(0xFF1E1F22);
  static const border  = Color(0xFF2C2D32);
  static const muted   = Color(0xFF8C8E9A);
  static const text    = Color(0xFFF1F2F5);
  static const accent  = Color(0xFFF59E0B);
  static const green   = Color(0xFF4ADE80);
  static const amber   = Color(0xFFFBBF24);
  static const red     = Color(0xFFFC8181);
}

class PurchaseClientDetailScreen extends ConsumerStatefulWidget {
  final String clientName;
  const PurchaseClientDetailScreen({super.key, required this.clientName});

  @override
  ConsumerState<PurchaseClientDetailScreen> createState() =>
      _PurchaseClientDetailScreenState();
}

class _PurchaseClientDetailScreenState
    extends ConsumerState<PurchaseClientDetailScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _attachmentSub;
  Map<String, double>  _paidPerBill          = {};
  double               _obPaid               = 0.0;
  Map<String, String>  _attachmentUrlPerBill  = {};
  Map<String, String>  _attachmentTypePerBill = {};
  bool                 _uploadingBillId_      = false;
  String?              _processingBillId;

  @override
  void initState() {
    super.initState();
    _startTxStream();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      _startAttachmentStream();
    }
  }

  void _startAttachmentStream() {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    _attachmentSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('purchase_bills')
        .where('clientName', isEqualTo: widget.clientName)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final urls  = <String, String>{};
      final types = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final id   = data['purchaseBillId'] as String? ?? doc.id;
        final url  = data['billAttachmentUrl']  as String?;
        final type = data['billAttachmentType'] as String?;
        if (url != null && url.isNotEmpty) {
          urls[id]  = url;
          types[id] = type ?? 'image';
        }
      }
      setState(() {
        _attachmentUrlPerBill  = urls;
        _attachmentTypePerBill = types;
      });
    });
  }

  void _startTxStream() {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    final clientLow = widget.clientName.trim().toLowerCase();

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'expense')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      double obPaid = 0.0;
      final perBill = <String, double>{};
      for (final d in snap.docs) {
        final raw = d.data();
        final linkedId = raw['linkedPurchaseBillId'] as String?;
        final amount = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final desc = (raw['description'] as String? ?? '').toLowerCase();
        final isObForThisClient = raw['isObPayment'] == true &&
            (raw['obPartyName'] as String? ?? '').trim().toLowerCase() ==
                clientLow;
        if (linkedId != null && linkedId.isNotEmpty) {
          perBill[linkedId] = (perBill[linkedId] ?? 0.0) + amount;
        } else if (isObForThisClient || desc.contains(clientLow)) {
          obPaid += amount;
        }
      }
      setState(() {
        _paidPerBill = perBill;
        _obPaid = obPaid;
      });
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _attachmentSub?.cancel();
    super.dispose();
  }

  // ── Attachment helpers ───────────────────────────────────────────────────────

  void _showAttachmentOptions(PurchaseBillEntity bill) {
    HapticFeedback.mediumImpact();
    final hasAttachment =
        _attachmentUrlPerBill.containsKey(bill.purchaseBillId);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillAttachOptionsSheet(
        billNumber:    bill.billNumber,
        hasAttachment: hasAttachment,
        onAttach:  () { Navigator.pop(context); _pickAndUpload(bill, replace: false); },
        onReplace: () { Navigator.pop(context); _pickAndUpload(bill, replace: true);  },
        onDelete:  () { Navigator.pop(context); _removeAttachment(bill); },
      ),
    );
  }

  Future<void> _pickAndUpload(PurchaseBillEntity bill,
      {required bool replace}) async {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FileTypePickerSheet(billNumber: bill.billNumber),
    );
    if (choice == null || !mounted) return;

    FilePickerResult? picked;
    try {
      if (choice == 'image') {
        picked = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: kIsWeb);
      } else {
        picked = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf'],
            allowMultiple: false,
            withData: kIsWeb);
      }
    } catch (_) {}

    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    // On web, accessing file.path throws — only check bytes.
    // On native, check path (bytes may be null when withData is false).
    if (kIsWeb) {
      if (file.bytes == null || file.bytes!.isEmpty) return;
    } else {
      if (file.path == null || file.path!.isEmpty) return;
    }

    setState(() => _processingBillId = bill.purchaseBillId);
    try {
      // Delete old file from Storage if replacing
      if (replace) {
        final oldUrl = _attachmentUrlPerBill[bill.purchaseBillId];
        if (oldUrl != null) {
          try { await FirebaseStorage.instance.refFromURL(oldUrl).delete(); }
          catch (_) {}
        }
      }

      final ext  = file.extension ?? (choice == 'image' ? 'jpg' : 'pdf');
      final path =
          'purchase_bills/$cashbookId/${bill.purchaseBillId}/attachment.$ext';
      final storageRef = FirebaseStorage.instance.ref(path);
      try {
        if (kIsWeb) {
          await storageRef.putData(file.bytes!).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
                'Upload timed out. Check Firebase Storage CORS settings for web.'),
          );
        } else {
          await storageRef.putFile(File(file.path!)).timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException('Upload timed out.'),
          );
        }
      } on TimeoutException catch (e) {
        throw Exception(e.message ?? 'Upload timed out');
      }
      final url  = await storageRef.getDownloadURL().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Could not get download URL — check Firebase Storage rules.'),
      );

      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('purchase_bills')
          .doc(bill.purchaseBillId)
          .update({'billAttachmentUrl': url, 'billAttachmentType': choice});

      if (mounted) {
        _showSnack('Bill attachment saved', success: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Upload failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _processingBillId = null);
    }
  }

  Future<void> _removeAttachment(PurchaseBillEntity bill) async {
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Attachment?',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
            'The attached bill image / PDF will be permanently removed.',
            style: TextStyle(color: _T.muted, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: _T.muted))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove',
                  style: TextStyle(
                      color: _T.red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _processingBillId = bill.purchaseBillId);
    try {
      final url = _attachmentUrlPerBill[bill.purchaseBillId];
      if (url != null) {
        try { await FirebaseStorage.instance.refFromURL(url).delete(); }
        catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('purchase_bills')
          .doc(bill.purchaseBillId)
          .update({
        'billAttachmentUrl':  FieldValue.delete(),
        'billAttachmentType': FieldValue.delete(),
      });
      if (mounted) _showSnack('Attachment removed', success: true);
    } catch (e) {
      if (mounted) _showSnack('Failed to remove: $e', success: false);
    } finally {
      if (mounted) setState(() => _processingBillId = null);
    }
  }

  Future<void> _viewAttachment(PurchaseBillEntity bill) async {
    final url  = _attachmentUrlPerBill[bill.purchaseBillId];
    final type = _attachmentTypePerBill[bill.purchaseBillId] ?? 'image';
    if (url == null) return;
    HapticFeedback.selectionClick();

    // ── Web: show in-app (iframe for PDF, pinch-zoom viewer for images) ──────
    if (kIsWeb) {
      if (type == 'pdf') {
        openPdfInApp(context, url, bill.billNumber, bill.clientName);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _InvoiceImageViewer(
              imageUrl:   url,
              billNumber: bill.billNumber,
              clientName: bill.clientName,
            ),
          ),
        );
      }
      return;
    }

    // ── iOS: PDF → share sheet (iOS Quick Look), Image → full-screen viewer ─
    if (type == 'pdf') {
      setState(() => _processingBillId = bill.purchaseBillId);
      try {
        final response = await http.get(Uri.parse(url));
        await Share.shareXFiles([
          XFile.fromData(response.bodyBytes,
              name:     'bill_${bill.billNumber}.pdf',
              mimeType: 'application/pdf'),
        ]);
      } catch (e) {
        if (mounted) _showSnack('Could not open PDF: $e', success: false);
      } finally {
        if (mounted) setState(() => _processingBillId = null);
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _InvoiceImageViewer(
            imageUrl:   url,
            billNumber: bill.billNumber,
            clientName: bill.clientName,
          ),
        ),
      );
    }
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      backgroundColor: success ? _T.green : _T.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  Future<void> _editOpeningBalance(double currentOb) async {
    final ctrl = TextEditingController(
        text: currentOb == 0 ? '' : currentOb.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _T.card2,
        title: const Text('Opening Balance', style: TextStyle(color: _T.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: _T.text),
          decoration: const InputDecoration(
            hintText: 'Amount owed to this client',
            hintStyle: TextStyle(color: _T.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _T.muted)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('Save', style: TextStyle(color: _T.accent)),
          ),
        ],
      ),
    );
    if (result == null) return;
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    await ref
        .read(purchaseClientActionsProvider.notifier)
        .setOpeningBalance(cashbookId, widget.clientName, result);
  }

  Future<void> _editBill(PurchaseBillEntity bill) async {
    HapticFeedback.selectionClick();
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditBillSheet(bill: bill, cashbookId: cashbookId),
    );
  }

  Future<void> _deleteBill(PurchaseBillEntity bill) async {
    HapticFeedback.mediumImpact();
    final cashbookId = ref.read(currentCashbookIdProvider);
    if (cashbookId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _T.card2,
        title: const Text('Delete Bill?', style: TextStyle(color: _T.text)),
        content: Text('Bill #${bill.billNumber} will be permanently deleted.',
            style: const TextStyle(color: _T.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: _T.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(purchaseBillActionsProvider.notifier)
        .deleteBill(cashbookId, bill.purchaseBillId);
  }

  void _openBillDetail(PurchaseBillEntity bill, List<PurchaseBillEntity> allBills) {
    HapticFeedback.selectionClick();
    final precomputedPaid = _paidPerBill[bill.purchaseBillId] ?? 0.0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseClientBillDetailScreen(
          bill:            bill,
          billCount:       allBills.length,
          precomputedPaid: precomputedPaid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(purchaseClientsProvider);
    final billsAsync   = ref.watch(purchaseBillsForClientProvider(widget.clientName));
    final client = clientsAsync.asData?.value.where(
        (c) => c.clientName.toLowerCase() == widget.clientName.toLowerCase());
    final openingBalance =
        (client != null && client.isNotEmpty) ? client.first.openingBalance : 0.0;
    final bills = billsAsync.asData?.value ?? [];

    final totalBilled = bills.fold<double>(0, (sum, b) => sum + b.billAmount);
    final totalBillsPaid = bills.fold<double>(
        0, (sum, b) => sum + (_paidPerBill[b.purchaseBillId] ?? 0.0));
    final obRemaining = (openingBalance - _obPaid).clamp(0.0, double.infinity);
    final closingBalance =
        (obRemaining + totalBilled - totalBillsPaid).clamp(0.0, double.infinity);
    final totalDue = closingBalance;
    final dateFmt = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: _T.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: _T.text),
                  ),
                  Expanded(
                    child: Text(widget.clientName,
                        style: const TextStyle(
                            color: _T.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _T.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _T.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Due',
                            style: TextStyle(color: _T.muted, fontSize: 12)),
                        InkWell(
                          onTap: () => _editOpeningBalance(openingBalance),
                          child: const Row(
                            children: [
                              Text('Edit opening balance',
                                  style: TextStyle(
                                      color: _T.accent, fontSize: 12)),
                              SizedBox(width: 4),
                              Icon(Icons.edit_rounded,
                                  size: 12, color: _T.accent),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('₹${totalDue.abs().toStringAsFixed(0)}',
                        style: TextStyle(
                            color: totalDue >= 0 ? _T.red : _T.green,
                            fontSize: 28,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                        'Opening balance: ₹${openingBalance.toStringAsFixed(0)}'
                        '${_obPaid > 0 ? ' (₹${obRemaining.toStringAsFixed(0)} remaining)' : ''}',
                        style: const TextStyle(color: _T.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  Icon(Icons.receipt_long_rounded, size: 16, color: _T.muted),
                  SizedBox(width: 6),
                  Text('All Bills',
                      style: TextStyle(
                          color: _T.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  SizedBox(width: 6),
                  Text('(tap to view details)',
                      style: TextStyle(color: _T.muted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: bills.isEmpty
                  ? const Center(
                      child: Text('No bills yet',
                          style: TextStyle(color: _T.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: bills.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final bill = bills[i];
                        final paidOnBill =
                            _paidPerBill[bill.purchaseBillId] ?? 0.0;
                        final pendingOnBill =
                            (bill.billAmount - paidOnBill)
                                .clamp(0.0, double.infinity);
                        final isSettled = pendingOnBill <= 0;
                        final isPartial = !isSettled && paidOnBill > 0;
                        final statusColor = isSettled
                            ? _T.green
                            : isPartial
                                ? _T.amber
                                : _T.red;
                        final statusLabel = isSettled
                            ? 'PAID'
                            : isPartial
                                ? 'PARTIAL'
                                : 'PENDING';

                        // Tappable bill row — opens PurchaseClientBillDetailScreen
                        final hasAttachment =
                            (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) &&
                            _attachmentUrlPerBill
                                .containsKey(bill.purchaseBillId);
                        final isProcessing =
                            _processingBillId == bill.purchaseBillId;

                        return InkWell(
                          onTap: () => _openBillDetail(bill, bills),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _T.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: hasAttachment
                                    ? _T.accent.withValues(alpha: 0.3)
                                    : _T.border,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Bill #${bill.billNumber}',
                                              style: const TextStyle(
                                                  color: _T.text,
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          const SizedBox(height: 2),
                                          Text(dateFmt.format(bill.billDate),
                                              style: const TextStyle(
                                                  color: _T.muted,
                                                  fontSize: 12)),
                                          if (bill.billNote != null &&
                                              bill.billNote!
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(bill.billNote!,
                                                style: const TextStyle(
                                                    color: _T.muted,
                                                    fontSize: 12),
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                            '₹${bill.billAmount.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                                color: _T.text,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
                                        if (!isSettled) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                              '₹${pendingOnBill.toStringAsFixed(0)} pending',
                                              style: const TextStyle(
                                                  color: _T.amber,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ],
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                                alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(statusLabel,
                                              style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    // ── iOS / web: attach icon ───────────
                                    if (kIsWeb || defaultTargetPlatform ==
                                        TargetPlatform.iOS)
                                      isProcessing
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: _T.accent,
                                              ),
                                            )
                                          : GestureDetector(
                                              onTap: () =>
                                                  _showAttachmentOptions(
                                                      bill),
                                              child: Container(
                                                width: 30,
                                                height: 30,
                                                margin: const EdgeInsets.only(
                                                    right: 2),
                                                decoration: BoxDecoration(
                                                  color: hasAttachment
                                                      ? _T.accent.withValues(
                                                          alpha: 0.12)
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: hasAttachment
                                                      ? Border.all(
                                                          color: _T.accent
                                                              .withValues(
                                                                  alpha: 0.3))
                                                      : null,
                                                ),
                                                child: Icon(
                                                  hasAttachment
                                                      ? Icons
                                                          .attach_file_rounded
                                                      : Icons
                                                          .attach_file_rounded,
                                                  color: hasAttachment
                                                      ? _T.accent
                                                      : _T.muted
                                                          .withValues(
                                                              alpha: 0.5),
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                    const Icon(Icons.chevron_right_rounded,
                                        color: _T.muted, size: 18),
                                    _BillRowMenu(
                                      onEdit:   () => _editBill(bill),
                                      onDelete: () => _deleteBill(bill),
                                    ),
                                  ],
                                ),

                                // ── View Invoice button (iOS/web, attachment exists)
                                if ((kIsWeb || defaultTargetPlatform ==
                                        TargetPlatform.iOS) &&
                                    hasAttachment) ...[
                                  const SizedBox(height: 10),
                                  GestureDetector(
                                    onTap: () => _viewAttachment(bill),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 9),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            _T.accent.withValues(alpha: 0.1),
                                            _T.accent.withValues(alpha: 0.05),
                                          ],
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: _T.accent
                                                .withValues(alpha: 0.25)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _attachmentTypePerBill[
                                                        bill.purchaseBillId] ==
                                                    'pdf'
                                                ? Icons
                                                    .picture_as_pdf_rounded
                                                : Icons.visibility_rounded,
                                            color: _T.accent,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text('View Invoice',
                                              style: TextStyle(
                                                  color: _T.accent,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  letterSpacing: 0.3)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Three-dot menu for a bill row ──────────────────────────────────────────

class _BillRowMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _BillRowMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert_rounded, color: _T.muted, size: 18),
        color: _T.card2,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _T.border)),
        onSelected: (v) {
          if (v == 'edit') onEdit();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'edit',
            height: 44,
            child: Row(
              children: const [
                Icon(Icons.edit_outlined, color: _T.accent, size: 16),
                SizedBox(width: 10),
                Text('Edit Bill',
                    style: TextStyle(
                        color: _T.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            height: 44,
            child: Row(
              children: const [
                Icon(Icons.delete_outline_rounded, color: _T.red, size: 16),
                SizedBox(width: 10),
                Text('Delete Bill',
                    style: TextStyle(
                        color: _T.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
}

// ─── Edit bill sheet ─────────────────────────────────────────────────────────

class _EditBillSheet extends ConsumerStatefulWidget {
  final PurchaseBillEntity bill;
  final String cashbookId;
  const _EditBillSheet({required this.bill, required this.cashbookId});

  @override
  ConsumerState<_EditBillSheet> createState() => _EditBillSheetState();
}

class _EditBillSheetState extends ConsumerState<_EditBillSheet> {
  final _formKey    = GlobalKey<FormState>();
  late final _billNoCtrl = TextEditingController(text: widget.bill.billNumber);
  late final _amountCtrl = TextEditingController(
      text: widget.bill.billAmount.toStringAsFixed(0));
  late final _noteCtrl   = TextEditingController(
      text: widget.bill.billNote ?? '');
  late DateTime _date    = widget.bill.billDate;
  bool _submitting       = false;

  @override
  void dispose() {
    _billNoCtrl.dispose();
    _amountCtrl.dispose();
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
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final updated = PurchaseBillEntity(
        purchaseBillId:    widget.bill.purchaseBillId,
        clientName:        widget.bill.clientName,
        billNumber:        _billNoCtrl.text.trim(),
        billAmount:        double.parse(_amountCtrl.text.trim()),
        billDate:          _date,
        billNote:          _noteCtrl.text.trim().isEmpty
                               ? null
                               : _noteCtrl.text.trim(),
        billCreatedAt:     widget.bill.billCreatedAt,
        billCreatedBy:     widget.bill.billCreatedBy,
        billCreatedByName: widget.bill.billCreatedByName,
        billStatus:        widget.bill.billStatus,
      );
      await ref
          .read(purchaseBillActionsProvider.notifier)
          .updateBill(widget.cashbookId, updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _T.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDec(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _T.muted, fontSize: 13),
        prefixIcon: icon != null ? Icon(icon, color: _T.muted, size: 18) : null,
        filled: true,
        fillColor: _T.card,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _T.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _T.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _T.accent)),
      );

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
                      color: _T.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Edit Bill',
                  style: TextStyle(
                      color: _T.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${widget.bill.clientName}',
                  style: const TextStyle(color: _T.muted, fontSize: 13)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _billNoCtrl,
                style: const TextStyle(color: _T.text),
                decoration: _fieldDec('Bill No *',
                    icon: Icons.confirmation_number_outlined),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amountCtrl,
                style: const TextStyle(color: _T.text),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    _fieldDec('Bill Amount (INR) *', icon: Icons.currency_rupee_rounded),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v.trim());
                  if (n == null || n < 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteCtrl,
                style: const TextStyle(color: _T.text),
                maxLines: 2,
                decoration: _fieldDec('Description', icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                      color: _T.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _T.border)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: _T.muted),
                      const SizedBox(width: 10),
                      Text(dateFmt.format(_date),
                          style: const TextStyle(
                              color: _T.text, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w700)),
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
//  Attachment Options Sheet  (iOS only)
// ─────────────────────────────────────────────────────────────────────────────

class _BillAttachOptionsSheet extends StatelessWidget {
  final String       billNumber;
  final bool         hasAttachment;
  final VoidCallback onAttach;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  const _BillAttachOptionsSheet({
    required this.billNumber,
    required this.hasAttachment,
    required this.onAttach,
    required this.onReplace,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: _T.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Title
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: _T.accent.withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.attach_file_rounded,
                    color: _T.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bill Attachment',
                      style: TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                  Text('Bill #$billNumber',
                      style: const TextStyle(
                          color: _T.muted, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Attach (shown when no attachment)
          if (!hasAttachment)
            _OptionTile(
              icon:    Icons.upload_rounded,
              label:   'Attach Bill',
              sub:     'Upload a photo or PDF of this bill',
              color:   _T.accent,
              onTap:   onAttach,
            ),

          // Replace (shown when attachment exists)
          if (hasAttachment) ...[
            _OptionTile(
              icon:  Icons.swap_horiz_rounded,
              label: 'Replace Attachment',
              sub:   'Upload a new file to replace the existing one',
              color: _T.accent,
              onTap: onReplace,
            ),
            const SizedBox(height: 8),
            _OptionTile(
              icon:  Icons.delete_outline_rounded,
              label: 'Delete Attachment',
              sub:   'Permanently remove the attached bill',
              color: _T.red,
              onTap: onDelete,
            ),
          ],

          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: _T.muted,
              side: BorderSide(color: _T.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Cancel',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       sub;
  final Color        color;
  final VoidCallback onTap;
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _T.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                            color: _T.muted, fontSize: 11, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: color.withValues(alpha: 0.5), size: 13),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  File type picker (Image vs PDF)
// ─────────────────────────────────────────────────────────────────────────────

class _FileTypePickerSheet extends StatelessWidget {
  final String billNumber;
  const _FileTypePickerSheet({required this.billNumber});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D1018),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Choose File Type',
                style: TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 17)),
            Text('Bill #$billNumber',
                style: const TextStyle(color: _T.muted, fontSize: 12)),
            const SizedBox(height: 20),
            _OptionTile(
              icon:  Icons.image_rounded,
              label: 'Photo / Image',
              sub:   'JPG or PNG — shown as HD image inside the app',
              color: _T.accent,
              onTap: () => Navigator.pop(context, 'image'),
            ),
            const SizedBox(height: 10),
            _OptionTile(
              icon:  Icons.picture_as_pdf_rounded,
              label: 'PDF Document',
              sub:   'Opens via iOS Quick Look for full PDF view',
              color: const Color(0xFFEF4444),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _T.muted,
                side: BorderSide(color: _T.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Cancel',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full-screen HD Invoice Image Viewer
// ─────────────────────────────────────────────────────────────────────────────

class _InvoiceImageViewer extends StatefulWidget {
  final String imageUrl;
  final String billNumber;
  final String clientName;
  const _InvoiceImageViewer({
    required this.imageUrl,
    required this.billNumber,
    required this.clientName,
  });

  @override
  State<_InvoiceImageViewer> createState() => _InvoiceImageViewerState();
}

class _InvoiceImageViewerState extends State<_InvoiceImageViewer>
    with SingleTickerProviderStateMixin {
  final _transformCtrl = TransformationController();
  bool _showControls   = true;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── HD image with pinch-to-zoom ───────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _showControls = !_showControls),
            child: InteractiveViewer(
              transformationController: _transformCtrl,
              minScale: 0.5,
              maxScale: 8.0,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  placeholder: (_, __) => const Center(
                    child: SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFFF59E0B)),
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined,
                            color: Color(0xFF4A5568), size: 48),
                        SizedBox(height: 12),
                        Text('Could not load image',
                            style: TextStyle(
                                color: Color(0xFF4A5568), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar ───────────────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 22),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.clientName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            Text('Invoice  #${widget.billNumber}',
                                style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.55),
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      // Reset zoom
                      IconButton(
                        onPressed: () => _transformCtrl.value =
                            Matrix4.identity(),
                        icon: const Icon(Icons.fit_screen_rounded,
                            color: Colors.white, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom hint ───────────────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showControls ? 0 : -60,
            left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: const Center(
                child: Text('Pinch to zoom  ·  Tap to hide controls',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
