
// lib/features/purchases/presentation/screens/purchase_client_bill_detail_screen.dart
//
// Mirrors bill_detail_screen.dart (Sales) but for purchase bills owed to suppliers.
// Expense payments go OUT (money leaving); accent colour is amber.

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import '../../domain/entities/purchase_bill_entity.dart';
import '../providers/purchase_bill_provider.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'web_invoice_viewer_stub.dart'
    if (dart.library.html) 'web_invoice_viewer_web.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Theme  (amber = purchase-feature accent, mirrors _T in purchases_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  static const bg     = Color(0xFF080A0E);
  static const card   = Color(0xFF0F1318);
  static const card2  = Color(0xFF141921);
  static const border = Color(0xFF1C2130);
  static const muted  = Color(0xFF4A5568);
  static const accent = Color(0xFFF59E0B); // amber — purchase feature
  static const text   = Color(0xFFE8ECF4);
  static const red    = Color(0xFFE85C5C);
  static const amber  = Color(0xFFFBBF24);
  static const green  = Color(0xFF38D68A);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data class for a single payment entry shown in the history list
// ─────────────────────────────────────────────────────────────────────────────

class _TxItem {
  final String   id;
  final double   amount;
  final DateTime createdAt;
  final String   description;
  final bool     isLinked;
  final String?  paymentAttachmentUrl;
  final String?  paymentAttachmentName;
  final String?  paymentReceiptUrl;
  final String?  paymentReceiptName;
  const _TxItem({
    required this.id,
    required this.amount,
    required this.createdAt,
    required this.description,
    required this.isLinked,
    this.paymentAttachmentUrl,
    this.paymentAttachmentName,
    this.paymentReceiptUrl,
    this.paymentReceiptName,
  });

  bool get hasPaymentDocuments =>
      (paymentAttachmentUrl ?? '').isNotEmpty ||
      (paymentReceiptUrl ?? '').isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Snack helper
// ─────────────────────────────────────────────────────────────────────────────

SnackBar _snackBar(String msg, {required bool success}) => SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      backgroundColor: success ? _T.green : _T.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );

// ─────────────────────────────────────────────────────────────────────────────
//  Purchase Client Bill Detail Screen
// ─────────────────────────────────────────────────────────────────────────────

class PurchaseClientBillDetailScreen extends ConsumerStatefulWidget {
  final PurchaseBillEntity bill;
  /// Number of bills this client has. When > 1 the description-match
  /// fallback is skipped so unlinked payments don't appear in every bill.
  final int billCount;
  /// Pre-computed paid amount passed from purchase_client_detail_screen.
  /// When provided, the screen uses this value (which already accounts
  /// for overflow redistribution) instead of summing linked transactions.
  final double? precomputedPaid;
  const PurchaseClientBillDetailScreen({
    super.key,
    required this.bill,
    this.billCount = 1,
    this.precomputedPaid,
  });

  @override
  ConsumerState<PurchaseClientBillDetailScreen> createState() =>
      _PurchaseClientBillDetailScreenState();
}

class _PurchaseClientBillDetailScreenState
    extends ConsumerState<PurchaseClientBillDetailScreen>
    with TickerProviderStateMixin {

  StreamSubscription<QuerySnapshot>?    _txSub;
  StreamSubscription<DocumentSnapshot>? _billDocSub;
  ProviderSubscription<String?>?        _idSub;
  String?                               _cashbookId;

  List<_TxItem> _transactions = [];
  bool          _loading            = true;
  bool          _isGeneratingShare  = false;

  // ── Bill attachment state (iOS only) ────────────────────────────────────────
  String? _attachmentUrl;
  String? _attachmentType;   // 'image' | 'pdf'
  bool    _uploading          = false;
  bool    _removingAttachment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 310), () {
        if (!mounted) return;
        _idSub = ref.listenManual<String?>(
          currentCashbookIdProvider,
          (prev, next) {
            if (next != null && next.isNotEmpty && next != _cashbookId) {
              _cashbookId = next;
              _txSub?.cancel();
              _startStream(next);
              if (kIsWeb) {
                _startBillDocStream(next);
              }
            }
          },
          fireImmediately: true,
        );
      });
    });
  }

  void _startStream(String cashbookId) {
    if (!mounted) return;
    final billId  = widget.bill.purchaseBillId;
    final clientQ = widget.bill.clientName.trim().toLowerCase();

    _txSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .where('type', isEqualTo: 'expense')
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final items = snap.docs
            .where((doc) {
              final raw      = doc.data();
              final linkedId = raw['linkedPurchaseBillId'] as String?;
              if (linkedId != null && linkedId.isNotEmpty) {
                return linkedId == billId;
              }
              if (widget.billCount > 1) return false;
              if (raw['isObPayment'] as bool? ?? false) return false;
              return (raw['description'] as String? ?? '')
                  .toLowerCase()
                  .contains(clientQ);
            })
            .map((doc) {
              final raw = doc.data();
              return _TxItem(
                id:          raw['transactionId'] as String? ?? doc.id,
                amount:      (raw['amount'] as num?)?.toDouble() ?? 0.0,
                createdAt:   (raw['createdAt'] as Timestamp?)?.toDate() ??
                             DateTime.now(),
                description: raw['description'] as String? ?? '',
                isLinked:    (raw['linkedPurchaseBillId'] as String? ?? '')
                                 .isNotEmpty,
                paymentAttachmentUrl:
                    raw['paymentAttachmentUrl'] as String?,
                paymentAttachmentName:
                    raw['paymentAttachmentName'] as String?,
                paymentReceiptUrl: raw['paymentReceiptUrl'] as String?,
                paymentReceiptName: raw['paymentReceiptName'] as String?,
              );
            })
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        setState(() {
          _transactions = items;
          _loading      = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  @override
  void dispose() {
    _idSub?.close();
    _txSub?.cancel();
    _billDocSub?.cancel();
    super.dispose();
  }

  // ── Bill doc stream (attachment URL) ────────────────────────────────────────

  void _startBillDocStream(String cashbookId) {
    _billDocSub?.cancel();
    _billDocSub = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('purchase_bills')
        .doc(widget.bill.purchaseBillId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data() as Map<String, dynamic>?;
      setState(() {
        _attachmentUrl  = data?['billAttachmentUrl']  as String?;
        _attachmentType = data?['billAttachmentType'] as String?;
      });
    });
  }

  // ── Attachment actions ───────────────────────────────────────────────────────

  Future<void> _pickAndUploadAttachment() async {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AttachmentPickerSheet(),
    );
    if (choice == null || !mounted) return;

    FilePickerResult? picked;
    try {
      if (choice == 'image') {
        picked = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
      } else {
        picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          allowMultiple: false,
        );
      }
    } catch (_) {}

    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.path == null) return;

    setState(() => _uploading = true);
    try {
      final ext  = file.extension ?? (choice == 'image' ? 'jpg' : 'pdf');
      final path =
          'purchase_bills/$_cashbookId/${widget.bill.purchaseBillId}/attachment.$ext';
      final storageRef = FirebaseStorage.instance.ref(path);
      await storageRef.putFile(File(file.path!));
      final url = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(_cashbookId)
          .collection('purchase_bills')
          .doc(widget.bill.purchaseBillId)
          .update({
        'billAttachmentUrl':  url,
        'billAttachmentType': choice,
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_snackBar('Bill attachment saved', success: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_snackBar('Upload failed: $e', success: false));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _viewAttachment() async {
    if (_attachmentUrl == null) return;
    HapticFeedback.selectionClick();

    // ── Web (incl. iOS PWA): open PDFs/images in-app, never hand off ────────
    if (kIsWeb) {
      if (_attachmentType == 'pdf') {
        openPdfInApp(
          context,
          _attachmentUrl!,
          widget.bill.billNumber,
          widget.bill.clientName,
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _BillImageViewer(
              imageUrl:   _attachmentUrl!,
              billNumber: widget.bill.billNumber,
              clientName: widget.bill.clientName,
            ),
          ),
        );
      }
      return;
    }

    // ── Native iOS/Android ────────────────────────────────────────────────
    if (_attachmentType == 'pdf') {
      setState(() => _uploading = true);
      try {
        final response = await http.get(Uri.parse(_attachmentUrl!));
        final bytes    = response.bodyBytes;
        await Share.shareXFiles([
          XFile.fromData(bytes,
              name:     'bill_${widget.bill.billNumber}.pdf',
              mimeType: 'application/pdf'),
        ]);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(_snackBar('Could not open PDF: $e', success: false));
        }
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _BillImageViewer(
            imageUrl:   _attachmentUrl!,
            billNumber: widget.bill.billNumber,
            clientName: widget.bill.clientName,
          ),
        ),
      );
    }
  }

  Future<void> _removeAttachment() async {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Attachment?',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
          'The attached bill image/PDF will be permanently removed.',
          style: TextStyle(color: _T.muted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: _T.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(
                    color: _T.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _removingAttachment = true);
    try {
      if (_attachmentUrl != null) {
        try {
          await FirebaseStorage.instance
              .refFromURL(_attachmentUrl!)
              .delete();
        } catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(_cashbookId)
          .collection('purchase_bills')
          .doc(widget.bill.purchaseBillId)
          .update({
        'billAttachmentUrl':  FieldValue.delete(),
        'billAttachmentType': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_snackBar('Attachment removed', success: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_snackBar('Failed to remove: $e', success: false));
      }
    } finally {
      if (mounted) setState(() => _removingAttachment = false);
    }
  }

  // ── Computed values ─────────────────────────────────────────────────────────

  double get _paid {
    if (widget.precomputedPaid != null) {
      return widget.precomputedPaid!.clamp(0.0, widget.bill.billAmount);
    }
    final linkedRaw = _transactions
        .where((t) => t.isLinked)
        .fold<double>(0.0, (s, t) => s + t.amount);
    final linked = linkedRaw.clamp(0.0, widget.bill.billAmount);
    final unlinked = _transactions
        .where((t) => !t.isLinked)
        .fold<double>(0.0, (s, t) => s + t.amount);
    final unlinkedCapped = unlinked.clamp(
        0.0, (widget.bill.billAmount - linked).clamp(0.0, double.infinity));
    return linked + unlinkedCapped;
  }

  double get _remaining =>
      (widget.bill.billAmount - _paid).clamp(0.0, double.infinity);
  bool get _settled => _remaining <= 0;

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _recordPayment() {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPaymentSheet(
        bill:       widget.bill,
        cashbookId: _cashbookId!,
        remaining:  _remaining,
      ),
    );
  }

  Future<void> _generateAndShare() async {
    if (_isGeneratingShare || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _isGeneratingShare = true);

    final overlayKey = GlobalKey();
    OverlayEntry? entry;
    try {
      String cashbookName = '';
      if (_cashbookId != null) {
        final snap = await FirebaseFirestore.instance
            .collection('cashbooks').doc(_cashbookId).get();
        cashbookName = (snap.data()?['name'] as String? ?? '').trim();
      }

      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: -5000, top: 0, width: 520,
          child: Material(
            type: MaterialType.transparency,
            child: RepaintBoundary(
              key: overlayKey,
              child: _BillShareCard(
                bill:         widget.bill,
                cashbookName: cashbookName,
                paid:         _paid,
                remaining:    _remaining,
                settled:      _settled,
                transactions: List<_TxItem>.from(_transactions),
              ),
            ),
          ),
        ),
      );
      if (!mounted) return;
      Overlay.of(context).insert(entry);
      await Future.delayed(const Duration(milliseconds: 150));

      final boundary = overlayKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');

      final image    = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');

      final bytes    = byteData.buffer.asUint8List();
      final safeName = widget.bill.billNumber
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      await Share.shareXFiles(
        [XFile.fromData(bytes,
            name: 'synccash_purchase_bill_$safeName.png',
            mimeType: 'image/png')],
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Could not generate image: $e', success: false));
    } finally {
      entry?.remove();
      if (mounted) setState(() => _isGeneratingShare = false);
    }
  }

  void _showPaymentDetail(_TxItem tx) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaymentDetailSheet(tx: tx, bill: widget.bill),
    );
  }

  Future<void> _deletePayment(_TxItem tx) async {
    if (_cashbookId == null) return;
    HapticFeedback.mediumImpact();

    final fmt = NumberFormat('#,##,##0.00');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Payment?',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'Payment of ₹${fmt.format(tx.amount)} will be permanently deleted '
          'and the cashbook balance will be updated accordingly.',
          style: const TextStyle(color: _T.muted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _T.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: _T.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final db          = FirebaseFirestore.instance;
      final cashbookRef = db.collection('cashbooks').doc(_cashbookId);
      final txRef       = cashbookRef.collection('transactions').doc(tx.id);

      final batch = db.batch();
      batch.delete(txRef);
      // Reverse expense effect on cashbook totals. The transaction is already
      // present in the list, so no network read is needed before queueing the
      // delete while offline.
      batch.update(cashbookRef, {
        'balance': FieldValue.increment(tx.amount),   // restore balance
        'expense': FieldValue.increment(-tx.amount),  // subtract from expense
      });
      await batch.commit();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Payment entry deleted', success: true));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Failed to delete: $e', success: false));
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy');
    final timeFmt = DateFormat('dd MMM  ·  hh:mm a');
    final paid      = _paid;
    final remaining = _remaining;
    final settled   = _settled;
    final partial   = paid > 0 && remaining > 0;
    final Color remColor = settled ? _T.green : _T.amber;
    final pct = widget.bill.billAmount > 0
        ? (paid / widget.bill.billAmount).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: _T.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── App Bar ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 140,
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
              Center(child: _StatusBadge(settled: settled, partial: partial)),
              const SizedBox(width: 4),
              _BillMoreMenu(
                onShare:      _generateAndShare,
                isGenerating: _isGeneratingShare,
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 90, 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.bill.clientName,
                      style: const TextStyle(
                          color: _T.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.2)),
                  Text(widget.bill.billNumber,
                      style: const TextStyle(color: _T.muted, fontSize: 10)),
                ],
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0D1122), Color(0xFF080A0E)],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // Financial summary card
                _FinancialCard(
                  bill:      widget.bill,
                  paid:      paid,
                  remaining: remaining,
                  settled:   settled,
                  loading:   _loading,
                  remColor:  remColor,
                  fmt:       fmt,
                  pct:       pct,
                ).animate().fadeIn(duration: 300.ms).slideY(
                    begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 12),

                // Bill info card
                _BillInfoCard(bill: widget.bill, dateFmt: dateFmt)
                    .animate()
                    .fadeIn(delay: 60.ms, duration: 300.ms)
                    .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

                // ── Bill Attachment (web + iOS PWA) ───────────────────────
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  _BillAttachmentCard(
                    attachmentUrl:  _attachmentUrl,
                    attachmentType: _attachmentType,
                    uploading:      _uploading || _removingAttachment,
                    cashbookReady:  _cashbookId != null,
                    onAttach:       _pickAndUploadAttachment,
                    onView:         _viewAttachment,
                    onRemove:       _removeAttachment,
                  )
                      .animate()
                      .fadeIn(delay: 80.ms, duration: 300.ms)
                      .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                ],

                const SizedBox(height: 22),

                // Payment history label
                Row(
                  children: [
                    Container(
                      width: 3, height: 14,
                      decoration: BoxDecoration(
                        color: _T.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('PAYMENT HISTORY',
                        style: TextStyle(
                            color: _T.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    const Spacer(),
                    if (!_loading)
                      Text(
                        '${_transactions.length} record${_transactions.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: _T.muted, fontSize: 10),
                      ),
                  ],
                ).animate().fadeIn(delay: 100.ms, duration: 280.ms),
                const SizedBox(height: 10),

                // Payment list
                if (_loading)
                  _PaymentLoadingShimmer()
                else if (_transactions.isEmpty)
                  _EmptyPayments().animate().fadeIn(delay: 120.ms)
                else
                  ...List.generate(_transactions.length, (i) {
                    final tx = _transactions[i];
                    return _PaymentTile(
                      tx:       tx,
                      timeFmt:  timeFmt,
                      fmt:      fmt,
                      index:    i,
                      onTap:    () => _showPaymentDetail(tx),
                      onDelete: () => _deletePayment(tx),
                    );
                  }),

                // Action buttons
                if (!settled) ...[
                  const SizedBox(height: 28),
                  _ActionButtons(
                    bill:            widget.bill,
                    cashbookId:      _cashbookId,
                    remaining:       remaining,
                    onRecordPayment: _recordPayment,
                  ).animate().fadeIn(
                    delay: Duration(
                        milliseconds: 140 + _transactions.length * 40),
                    duration: 300.ms,
                  ),
                ] else ...[
                  const SizedBox(height: 24),
                  _SettledBanner()
                      .animate()
                      .fadeIn(delay: 120.ms, duration: 400.ms)
                      .scale(begin: const Offset(0.96, 0.96)),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Payment detail sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentDetailSheet extends StatelessWidget {
  final _TxItem            tx;
  final PurchaseBillEntity bill;
  const _PaymentDetailSheet({required this.tx, required this.bill});

  Future<void> _openDocument(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('Could not open document', success: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy  ·  hh:mm a');

    Widget documentTile({
      required IconData icon,
      required String label,
      required String name,
      required String url,
    }) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, color: _T.accent, size: 20),
        title: Text(label,
            style: const TextStyle(
                color: _T.text, fontSize: 12, fontWeight: FontWeight.w600)),
        subtitle: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _T.muted, fontSize: 10)),
        trailing: const Icon(Icons.open_in_new_rounded,
            color: _T.muted, size: 17),
        onTap: () => _openDocument(context, url),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: _T.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Amount hero
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _T.accent.withValues(alpha: 0.08),
                  _T.accent.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _T.accent.withValues(alpha: 0.18)),
            ),
            child: Column(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: _T.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _T.accent.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.arrow_upward_rounded,
                      color: _T.accent, size: 24),
                ),
                const SizedBox(height: 14),
                const Text('Payment Made',
                    style: TextStyle(
                        color: _T.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.3)),
                const SizedBox(height: 8),
                Text(
                  '₹${fmt.format(tx.amount)}',
                  style: const TextStyle(
                      color: _T.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 34,
                      letterSpacing: -1),
                ),
                if (tx.isLinked) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _T.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _T.accent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_rounded,
                            color: _T.accent, size: 12),
                        const SizedBox(width: 4),
                        const Text('Linked to bill',
                            style: TextStyle(
                                color: _T.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Details
          Container(
            decoration: BoxDecoration(
              color: _T.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _T.border),
            ),
            child: Column(
              children: [
                _DetailRow(
                    icon:  Icons.calendar_today_rounded,
                    label: 'Date & Time',
                    value: dateFmt.format(tx.createdAt)),
                _Divider(),
                _DetailRow(
                    icon:  Icons.confirmation_number_outlined,
                    label: 'Bill No.',
                    value: bill.billNumber),
                _Divider(),
                _DetailRow(
                    icon:  Icons.business_rounded,
                    label: 'Client',
                    value: bill.clientName),
                if (tx.description.isNotEmpty) ...[
                  _Divider(),
                  _DetailRow(
                      icon:  Icons.notes_rounded,
                      label: 'Description',
                      value: tx.description),
                ],
              ],
            ),
          ),
          if (tx.hasPaymentDocuments) ...[
            const SizedBox(height: 16),
            const Text('PAYMENT DOCUMENTS',
                style: TextStyle(
                    color: _T.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: _T.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _T.border),
              ),
              child: Column(
                children: [
                  if ((tx.paymentAttachmentUrl ?? '').isNotEmpty)
                    documentTile(
                      icon: (tx.paymentAttachmentName ?? '')
                              .toLowerCase()
                              .endsWith('.pdf')
                          ? Icons.picture_as_pdf_rounded
                          : Icons.image_rounded,
                      label: 'Payment proof',
                      name: tx.paymentAttachmentName ?? 'Attached proof',
                      url: tx.paymentAttachmentUrl!,
                    ),
                  if ((tx.paymentAttachmentUrl ?? '').isNotEmpty &&
                      (tx.paymentReceiptUrl ?? '').isNotEmpty)
                    const Divider(height: 1, color: _T.border),
                  if ((tx.paymentReceiptUrl ?? '').isNotEmpty)
                    documentTile(
                      icon: Icons.receipt_long_rounded,
                      label: 'Payment receipt',
                      name: tx.paymentReceiptName ?? 'Receipt PDF',
                      url: tx.paymentReceiptUrl!,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _T.muted,
                side: BorderSide(color: _T.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Close',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: _T.muted, size: 15),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: _T.muted, fontSize: 13)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: _T.border,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Financial summary card
// ─────────────────────────────────────────────────────────────────────────────

class _FinancialCard extends StatelessWidget {
  final PurchaseBillEntity bill;
  final double         paid;
  final double         remaining;
  final bool           settled;
  final bool           loading;
  final Color          remColor;
  final NumberFormat   fmt;
  final double         pct;

  const _FinancialCard({
    required this.bill,
    required this.paid,
    required this.remaining,
    required this.settled,
    required this.loading,
    required this.remColor,
    required this.fmt,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              remColor.withValues(alpha: 0.04),
              const Color(0xFF0C1018),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: remColor.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: remColor.withValues(alpha: 0.04),
              blurRadius: 24, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            _SummaryRow(
              icon:       Icons.receipt_long_rounded,
              label:      'Bill Amount',
              value:      '₹${fmt.format(bill.billAmount)}',
              valueColor: _T.text,
            ),
            const SizedBox(height: 10),
            _SummaryRow(
              icon:       Icons.arrow_upward_rounded,
              label:      'Paid',
              value:      loading ? '—' : '₹${fmt.format(paid)}',
              valueColor: _T.accent,
            ),
            if (!loading) ...[
              const SizedBox(height: 14),
              _ProgressBar(pct: pct, color: remColor),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 16),
            Container(height: 1, color: _T.border.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Remaining',
                    style: TextStyle(
                        color: _T.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                if (loading)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: _T.accent),
                  )
                else
                  Text(
                    settled ? 'Fully Paid ✓' : '₹${fmt.format(remaining)}',
                    style: TextStyle(
                        color: remColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.3),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    valueColor;
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: valueColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: valueColor, size: 13),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(color: _T.muted, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ],
      );
}

class _ProgressBar extends StatelessWidget {
  final double pct;
  final Color  color;
  const _ProgressBar({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: _T.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% paid',
            style: TextStyle(
                color: _T.muted.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w500),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bill info card
// ─────────────────────────────────────────────────────────────────────────────

class _BillInfoCard extends StatelessWidget {
  final PurchaseBillEntity bill;
  final DateFormat         dateFmt;
  const _BillInfoCard({required this.bill, required this.dateFmt});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.border),
        ),
        child: Column(
          children: [
            _InfoRow(label: 'Client',   value: bill.clientName),
            _InfoRow(label: 'Bill No.', value: bill.billNumber),
            _InfoRow(label: 'Date',     value: dateFmt.format(bill.billDate)),
            if ((bill.billNote ?? '').isNotEmpty)
              _InfoRow(label: 'Note', value: bill.billNote!),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(color: _T.muted, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Payment tile
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final _TxItem      tx;
  final DateFormat   timeFmt;
  final NumberFormat fmt;
  final int          index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PaymentTile({
    required this.tx,
    required this.timeFmt,
    required this.fmt,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _T.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: tx.isLinked
                  ? _T.accent.withValues(alpha: 0.15)
                  : _T.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _T.accent.withValues(alpha: 0.15)),
                ),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: _T.accent, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description.isNotEmpty
                          ? tx.description
                          : 'Payment made',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _T.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timeFmt.format(tx.createdAt),
                      style: TextStyle(
                          color: _T.muted.withValues(alpha: 0.8),
                          fontSize: 11),
                    ),
                     if (tx.hasPaymentDocuments) ...[
                       const SizedBox(height: 3),
                       Row(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           Icon(Icons.attach_file_rounded,
                               color: _T.accent.withValues(alpha: 0.7),
                               size: 11),
                           const SizedBox(width: 3),
                           Text('documents attached',
                               style: TextStyle(
                                   color: _T.accent.withValues(alpha: 0.7),
                                   fontSize: 9,
                                   fontWeight: FontWeight.w600)),
                         ],
                       ),
                     ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${fmt.format(tx.amount)}',
                    style: const TextStyle(
                        color: _T.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.3),
                  ),
                  if (tx.isLinked) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_rounded,
                            color: _T.accent.withValues(alpha: 0.6), size: 10),
                        const SizedBox(width: 2),
                        Text('linked',
                            style: TextStyle(
                                color: _T.accent.withValues(alpha: 0.6),
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              _PaymentPopupMenu(onDelete: onDelete),
            ],
          ),
        ),
      );
}

class _PaymentPopupMenu extends StatelessWidget {
  final VoidCallback onDelete;
  const _PaymentPopupMenu({required this.onDelete});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(Icons.more_vert_rounded,
            color: _T.muted.withValues(alpha: 0.55), size: 18),
        color: _T.card2,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _T.border)),
        onSelected: (v) { if (v == 'delete') onDelete(); },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'delete',
            height: 44,
            child: Row(
              children: [
                const Icon(Icons.delete_outline_rounded, color: _T.red, size: 16),
                const SizedBox(width: 10),
                const Text('Delete Entry',
                    style: TextStyle(
                        color: _T.red, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading / Empty / Settled widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentLoadingShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(3, (_) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          height: 64,
          decoration: BoxDecoration(
            color: _T.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _T.border),
          ),
        )),
      );
}

class _EmptyPayments extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: const BoxDecoration(
                  color: _T.border, shape: BoxShape.circle),
              child: const Icon(Icons.payments_outlined,
                  color: _T.muted, size: 22),
            ),
            const SizedBox(height: 10),
            const Text('No payments recorded',
                style: TextStyle(
                    color: _T.text, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Use "Record Payment" below to add one.',
                style: TextStyle(color: _T.muted, fontSize: 11)),
          ],
        ),
      );
}

class _SettledBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _T.green.withValues(alpha: 0.08),
              _T.green.withValues(alpha: 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.green.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _T.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: _T.green, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bill Fully Paid',
                    style: TextStyle(
                        color: _T.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                SizedBox(height: 2),
                Text('All payments to supplier have been recorded.',
                    style: TextStyle(color: _T.muted, fontSize: 11)),
              ],
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status badge
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool settled;
  final bool partial;
  const _StatusBadge({required this.settled, required this.partial});

  @override
  Widget build(BuildContext context) {
    final Color color = settled ? _T.green : partial ? _T.amber : _T.red;
    final String label = settled ? 'PAID' : partial ? 'PARTIAL' : 'PENDING';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  More menu (Share)
// ─────────────────────────────────────────────────────────────────────────────

class _BillMoreMenu extends StatelessWidget {
  final VoidCallback onShare;
  final bool         isGenerating;
  const _BillMoreMenu({required this.onShare, required this.isGenerating});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        icon: isGenerating
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _T.muted))
            : const Icon(Icons.more_vert_rounded, color: _T.muted, size: 20),
        color: _T.card2,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _T.border)),
        onSelected: (v) { if (v == 'share') onShare(); },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'share',
            height: 44,
            child: Row(
              children: [
                const Icon(Icons.share_rounded, color: _T.accent, size: 16),
                const SizedBox(width: 10),
                const Text('Share Bill',
                    style: TextStyle(
                        color: _T.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action buttons (record payment / settle)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final PurchaseBillEntity bill;
  final String?            cashbookId;
  final double             remaining;
  final VoidCallback       onRecordPayment;

  const _ActionButtons({
    required this.bill,
    required this.cashbookId,
    required this.remaining,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt      = NumberFormat('#,##,##0.00');
    final actState = ref.watch(purchaseBillActionsProvider);
    final isLoading = actState.isLoading;
    final enabled   = cashbookId != null && !isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: enabled ? onRecordPayment : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _T.accent,
              foregroundColor: Colors.black,
              disabledBackgroundColor: _T.accent.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Record Payment',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: enabled ? () => _confirmSettle(context, ref, fmt) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: _T.green,
              side: BorderSide(
                  color: enabled
                      ? _T.green.withValues(alpha: 0.4)
                      : _T.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _T.green))
                : const Icon(Icons.check_circle_outline_rounded, size: 16),
            label: Text(
              remaining > 0
                  ? 'Settle (write off ₹${fmt.format(remaining)})'
                  : 'Mark as Settled',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmSettle(BuildContext ctx, WidgetRef ref, NumberFormat fmt) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: _T.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Mark as Settled?',
            style: TextStyle(
                color: _T.text, fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (remaining > 0)
              Text(
                '₹${fmt.format(remaining)} is still outstanding. '
                'This will record a final expense entry and mark the bill as fully paid.',
                style: const TextStyle(
                    color: _T.muted, fontSize: 13, height: 1.5),
              )
            else
              const Text(
                'This will mark the bill as fully paid.',
                style: TextStyle(color: _T.muted, fontSize: 13, height: 1.5),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _T.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final user = FirebaseAuth.instance.currentUser;
              if (cashbookId == null || user == null) return;
              await ref
                  .read(purchaseBillActionsProvider.notifier)
                  .settleWithPayment(
                    cashbookId:    cashbookId!,
                    billId:        bill.purchaseBillId,
                    billNumber:    bill.billNumber,
                    clientName:    bill.clientName,
                    remaining:     remaining,
                    createdBy:     user.uid,
                    createdByName: user.displayName ?? '',
                  );
            },
            child: const Text('Settle',
                style: TextStyle(color: _T.green, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Record Payment sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  final PurchaseBillEntity bill;
  final String             cashbookId;
  final double             remaining;

  const _RecordPaymentSheet({
    required this.bill,
    required this.cashbookId,
    required this.remaining,
  });

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _amtCtrl  = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Not signed in. Please restart the app.', success: false);
      return;
    }
    setState(() => _submitting = true);
    try {
      final amount = double.parse(_amtCtrl.text.trim());
      final desc   = _noteCtrl.text.trim();

      await ref.read(purchaseBillActionsProvider.notifier).recordPaymentWithOverflow(
            cashbookId:     widget.cashbookId,
            selectedBillId: widget.bill.purchaseBillId,
            clientName:     widget.bill.clientName,
            totalAmount:    amount,
            description:    desc.isNotEmpty
                ? desc
                : 'Payment – ${widget.bill.clientName}',
            category:       'wholesale',
            createdBy:      user.uid,
            createdByName:  user.displayName ?? '',
            createdAt:      DateTime.now(),
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            _snackBar('Payment of ₹${_fmtNum(amount)} recorded', success: true));
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save: $e', success: false);
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
    final fmt    = NumberFormat('#,##,##0.00');

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
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _T.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _T.accent.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.add_rounded, color: _T.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Record Payment',
                            style: TextStyle(
                                color: _T.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                        Text(
                          '${widget.bill.clientName}  ·  Bill #${widget.bill.billNumber}',
                          style: const TextStyle(color: _T.muted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Remaining display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _T.amber.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _T.amber.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: _T.amber, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      'Outstanding: ₹${fmt.format(widget.remaining)}',
                      style: const TextStyle(
                          color: _T.amber,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amtCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(
                    color: _T.text, fontSize: 24, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: fmt.format(widget.remaining),
                  hintStyle: const TextStyle(
                      color: _T.muted, fontSize: 24, fontWeight: FontWeight.w700),
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(
                      color: _T.accent, fontSize: 20, fontWeight: FontWeight.w700),
                  filled: true,
                  fillColor: _T.card,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _T.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _T.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: _T.accent, width: 1.5)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter amount';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                style: const TextStyle(color: _T.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Note (optional)',
                  hintStyle: const TextStyle(color: _T.muted, fontSize: 14),
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
                      borderSide:
                          const BorderSide(color: _T.accent, width: 1.5)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.accent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor:
                        _T.accent.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Save Payment',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
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
//  Share card (rendered off-screen, captured as PNG)
// ─────────────────────────────────────────────────────────────────────────────

class _BillShareCard extends StatelessWidget {
  final PurchaseBillEntity bill;
  final String             cashbookName;
  final double             paid;
  final double             remaining;
  final bool               settled;
  final List<_TxItem>      transactions;

  const _BillShareCard({
    required this.bill,
    required this.cashbookName,
    required this.paid,
    required this.remaining,
    required this.settled,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##,##0.00');
    final dateFmt = DateFormat('dd MMM yyyy');
    final timeFmt = DateFormat('dd MMM  ·  hh:mm a');

    return Container(
      color: const Color(0xFF080A0E),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_outlined,
                    color: _T.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cashbookName.isNotEmpty ? cashbookName : 'SyncCash',
                        style: const TextStyle(
                            color: _T.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const Text('Purchase Bill',
                        style: TextStyle(color: _T.muted, fontSize: 11)),
                  ],
                ),
              ),
              _StatusBadge(settled: settled, partial: paid > 0 && !settled),
            ],
          ),
          const SizedBox(height: 20),
          // Bill details
          _ShareRow('Client',   bill.clientName),
          _ShareRow('Bill No.', bill.billNumber),
          _ShareRow('Date',     dateFmt.format(bill.billDate)),
          if ((bill.billNote ?? '').isNotEmpty)
            _ShareRow('Note', bill.billNote!),
          const SizedBox(height: 16),
          Container(height: 1, color: _T.border),
          const SizedBox(height: 16),
          // Summary
          _ShareRow('Bill Amount', '₹${fmt.format(bill.billAmount)}'),
          _ShareRow('Paid', '₹${fmt.format(paid)}',
              valueColor: _T.accent),
          _ShareRow(
              'Remaining',
              settled ? 'Fully Paid ✓' : '₹${fmt.format(remaining)}',
              valueColor: settled ? _T.green : _T.amber),
          if (transactions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: _T.border),
            const SizedBox(height: 12),
            const Text('PAYMENT HISTORY',
                style: TextStyle(
                    color: _T.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            ...transactions.take(5).map((tx) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tx.description.isNotEmpty
                          ? tx.description
                          : 'Payment made',
                      style: const TextStyle(color: _T.muted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(timeFmt.format(tx.createdAt),
                      style: const TextStyle(color: _T.muted, fontSize: 10)),
                  const SizedBox(width: 8),
                  Text('₹${fmt.format(tx.amount)}',
                      style: const TextStyle(
                          color: _T.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ],
              ),
            )),
          ],
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Generated by SyncCash',
              style: TextStyle(
                  color: _T.muted.withValues(alpha: 0.5), fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _ShareRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(color: _T.muted, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      color: valueColor ?? _T.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bill Attachment Card  (iOS only)
// ─────────────────────────────────────────────────────────────────────────────

class _BillAttachmentCard extends StatelessWidget {
  final String?      attachmentUrl;
  final String?      attachmentType;
  final bool         uploading;
  final bool         cashbookReady;
  final VoidCallback onAttach;
  final VoidCallback onView;
  final VoidCallback onRemove;

  const _BillAttachmentCard({
    required this.attachmentUrl,
    required this.attachmentType,
    required this.uploading,
    required this.cashbookReady,
    required this.onAttach,
    required this.onView,
    required this.onRemove,
  });

  bool get _hasAttachment =>
      attachmentUrl != null && attachmentUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Row(
          children: [
            Container(
              width: 3, height: 14,
              decoration: BoxDecoration(
                color: _T.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text('BILL ATTACHMENT',
                style: TextStyle(
                    color: _T.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          ],
        ),
        const SizedBox(height: 10),

        // Card
        Container(
          decoration: BoxDecoration(
            color: _T.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hasAttachment
                  ? _T.accent.withValues(alpha: 0.25)
                  : _T.border,
            ),
          ),
          child: uploading
              ? _buildLoadingState()
              : _hasAttachment
                  ? _buildAttachedState(context)
                  : _buildEmptyState(),
        ),
      ],
    );
  }

  Widget _buildLoadingState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _T.accent,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Please wait…',
                style: TextStyle(color: _T.muted, fontSize: 12)),
          ],
        ),
      );

  Widget _buildEmptyState() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: _T.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: _T.accent.withValues(alpha: 0.15)),
              ),
              child: const Icon(Icons.attach_file_rounded,
                  color: _T.accent, size: 26),
            ),
            const SizedBox(height: 12),
            const Text('No bill attached',
                style: TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Attach a photo or PDF of the original bill.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _T.muted, fontSize: 11, height: 1.4)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: cashbookReady ? onAttach : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _T.accent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      _T.accent.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.upload_rounded, size: 16),
                label: const Text('Attach Bill',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ],
        ),
      );

  Widget _buildAttachedState(BuildContext context) => Column(
        children: [
          // Preview area
          GestureDetector(
            onTap: onView,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
                color: const Color(0xFF0A0D14),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
                child: attachmentType == 'image'
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: attachmentUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _T.accent),
                              ),
                            ),
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined,
                                  color: _T.muted, size: 32),
                            ),
                          ),
                          // Tap overlay
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                              ),
                            ),
                          ),
                          const Positioned(
                            bottom: 12, left: 0, right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.zoom_in_rounded,
                                    color: Colors.white70, size: 14),
                                SizedBox(width: 4),
                                Text('Tap to view HD',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : _PdfPlaceholder(onTap: onView),
              ),
            ),
          ),

          // Action row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                // Attachment type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _T.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _T.accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        attachmentType == 'pdf'
                            ? Icons.picture_as_pdf_rounded
                            : Icons.image_rounded,
                        color: _T.accent, size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        attachmentType == 'pdf' ? 'PDF' : 'IMAGE',
                        style: const TextStyle(
                            color: _T.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // View button
                _AttachmentActionBtn(
                  icon:  attachmentType == 'pdf'
                      ? Icons.open_in_new_rounded
                      : Icons.visibility_rounded,
                  label: 'View Bill',
                  color: _T.accent,
                  onTap: onView,
                ),
                const SizedBox(width: 8),

                // Replace button
                _AttachmentActionBtn(
                  icon:  Icons.swap_horiz_rounded,
                  label: 'Replace',
                  color: _T.muted,
                  onTap: onAttach,
                ),
                const SizedBox(width: 8),

                // Remove button
                _AttachmentActionBtn(
                  icon:  Icons.delete_outline_rounded,
                  label: 'Remove',
                  color: _T.red,
                  onTap: onRemove,
                ),
              ],
            ),
          ),
        ],
      );
}

class _AttachmentActionBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _AttachmentActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class _PdfPlaceholder extends StatelessWidget {
  final VoidCallback onTap;
  const _PdfPlaceholder({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: _T.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: _T.accent.withValues(alpha: 0.22)),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: _T.accent, size: 30),
              ),
              const SizedBox(height: 10),
              const Text('PDF Attached',
                  style: TextStyle(
                      color: _T.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 4),
              const Text('Tap "View Bill" to open',
                  style: TextStyle(color: _T.muted, fontSize: 11)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attachment Type Picker Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet();

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
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: _T.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Attach Bill',
                style: TextStyle(
                    color: _T.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            const SizedBox(height: 4),
            const Text('Choose the type of file to attach',
                style: TextStyle(color: _T.muted, fontSize: 13)),
            const SizedBox(height: 24),

            // Image option
            _PickerOption(
              icon:        Icons.image_rounded,
              title:       'Photo / Image',
              subtitle:    'JPG, PNG — shows as HD image in-app',
              accentColor: _T.accent,
              onTap:       () => Navigator.pop(context, 'image'),
            ),
            const SizedBox(height: 10),

            // PDF option
            _PickerOption(
              icon:        Icons.picture_as_pdf_rounded,
              title:       'PDF Document',
              subtitle:    'Opens with iOS Quick Look for full PDF view',
              accentColor: const Color(0xFFEF4444),
              onTap:       () => Navigator.pop(context, 'pdf'),
            ),
            const SizedBox(height: 16),

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

class _PickerOption extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final Color        accentColor;
  final VoidCallback onTap;
  const _PickerOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: accentColor.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _T.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            color: _T.muted, fontSize: 11, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: _T.muted.withValues(alpha: 0.5), size: 14),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full-screen HD Image Viewer
// ─────────────────────────────────────────────────────────────────────────────

class _BillImageViewer extends StatefulWidget {
  final String imageUrl;
  final String billNumber;
  final String clientName;
  const _BillImageViewer({
    required this.imageUrl,
    required this.billNumber,
    required this.clientName,
  });

  @override
  State<_BillImageViewer> createState() => _BillImageViewerState();
}

class _BillImageViewerState extends State<_BillImageViewer>
    with SingleTickerProviderStateMixin {
  final _transformCtrl = TransformationController();
  bool _showControls   = true;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Image viewer ──────────────────────────────────────────────────
          GestureDetector(
            onTap: _toggleControls,
            child: InteractiveViewer(
              transformationController: _transformCtrl,
              boundaryMargin: EdgeInsets.all(double.infinity),
              minScale: 0.5,
              maxScale: 8.0,
              panEnabled: true,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  placeholder: (_, __) => const Center(
                    child: SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: _T.accent),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.broken_image_outlined,
                          color: _T.muted, size: 48),
                      SizedBox(height: 12),
                      Text('Could not load image',
                          style: TextStyle(color: _T.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Top controls ─────────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                  child: Row(
                    children: [
                      // Close
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 22),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Title
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
                            Text('Bill  ${widget.billNumber}',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      // Reset zoom
                      IconButton(
                        onPressed: _resetZoom,
                        icon: const Icon(Icons.fit_screen_rounded,
                            color: Colors.white, size: 20),
                        tooltip: 'Reset zoom',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
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
            bottom: _showControls ? 0 : -80,
            left: 0, right: 0,
            child: Container(
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
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Pinch to zoom  ·  Tap to hide controls',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
