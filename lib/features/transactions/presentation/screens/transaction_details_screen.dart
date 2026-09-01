import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/purchases/presentation/screens/web_invoice_viewer_stub.dart'
    if (dart.library.html) 'package:synccash/features/purchases/presentation/screens/web_invoice_viewer_web.dart';
import 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_stub.dart'
    if (dart.library.io) 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_native.dart';

class TransactionDetailsScreen extends ConsumerStatefulWidget {
  final TransactionEntity transaction;

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
  });

  @override
  ConsumerState<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState
    extends ConsumerState<TransactionDetailsScreen> {
  // Bill-linked state
  String? _billNumber;
  bool    _loadingBill = false;

  // Opening-balance state
  bool    _isObPayment = false;
  String  _obDisplay   = '';

  @override
  void initState() {
    super.initState();
    final purchaseBillId = widget.transaction.linkedPurchaseBillId;
    final saleBillId = widget.transaction.linkedSaleBillId;
    if (purchaseBillId != null && purchaseBillId.isNotEmpty) {
      _fetchBillNumber(purchaseBillId, collection: 'purchase_bills');
    } else if (saleBillId != null && saleBillId.isNotEmpty) {
      _fetchBillNumber(saleBillId, collection: 'sale_bills');
    } else if (widget.transaction.type == 'income') {
      _checkObPayment();
    }
  }

  // ── Fetch bill number from sale_bills sub-collection ──────────────────────

  Future<void> _fetchBillNumber(
    String billId, {
    required String collection,
  }) async {
    if (!mounted) return;
    setState(() => _loadingBill = true);
    try {
      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId == null || cashbookId.isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection(collection)
          .doc(billId)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _billNumber = doc.data()?['billNumber'] as String?;
        });
      }
    } catch (_) {
      // silently ignore — bill number is optional display info
    } finally {
      if (mounted) setState(() => _loadingBill = false);
    }
  }

  void _openReceipt(String url) {
    if (kIsWeb) {
      openPdfInApp(
        context,
        url,
        'Payment receipt',
        widget.transaction.description,
        documentLabel: 'Receipt',
      );
    } else {
      openNativePdfInApp(
        context,
        url,
        'Payment receipt',
        widget.transaction.description,
        documentLabel: 'Receipt',
      );
    }
  }

  // ── Detect OB payment ─────────────────────────────────────────────────────
  //
  // Three detection strategies, tried in order:
  //
  // 1. isObPayment == true  (new transactions stamped by sale_bill_provider)
  //
  // 2. description contains "opening balance"  (old alloc-based OB overflow
  //    written by the old provider as "Opening balance payment – PartyName")
  //
  // 3. category == "wholesale" AND description matches a party name that has
  //    openingBalance > 0 in Firestore  (user's convention for normal income
  //    entry: type income / category wholesale / description = party name)

  Future<void> _checkObPayment() async {
    if (!mounted) return;
    try {
      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId == null || cashbookId.isEmpty) return;
      final txId = widget.transaction.transactionId;
      if (txId.isEmpty) return;

      final doc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('transactions')
          .doc(txId)
          .get();

      if (!mounted || !doc.exists) return;

      final d      = doc.data()!;
      final isOb   = d['isObPayment'] as bool? ?? false;
      final rawDesc = d['description'] as String? ?? '';
      final descLow = rawDesc.toLowerCase();

      String partyName = '';

      if (isOb) {
        // ── Strategy 1: flag-based (new transactions) ──────────────────────
        partyName = (d['obPartyName'] as String? ?? '').trim();

      } else if (descLow.contains('opening balance')) {
        // ── Strategy 2: description pattern (old alloc overflow) ──────────
        // Format: "Opening balance payment – PartyName" or "Note – PartyName"
        final sep = rawDesc.lastIndexOf(' – ');
        if (sep >= 0) {
          partyName = rawDesc.substring(sep + 3).trim();
        }
        if (partyName.isEmpty) {
          // Can't extract party name but clearly an OB transaction
          if (mounted) setState(() { _isObPayment = true; _obDisplay = 'Opening Balance'; });
          return;
        }

      } else {
        // ── Strategy 3: wholesale income with description = party name ─────
        // User convention: category "wholesale" + description = client/party
        final cat  = widget.transaction.category.toLowerCase().trim();
        final desc = widget.transaction.description.trim();
        if (cat == 'wholesale' && desc.isNotEmpty) {
          final partyDoc = await FirebaseFirestore.instance
              .collection('cashbooks')
              .doc(cashbookId)
              .collection('parties')
              .doc(desc.toLowerCase())
              .get();
          final ob =
              (partyDoc.data()?['openingBalance'] as num?)?.toDouble() ?? 0.0;
          if (ob > 0) {
            partyName = desc;
          }
        }
      }

      if (partyName.isEmpty) return;

      if (mounted) setState(() => _isObPayment = true);
      await _fetchObStatus(cashbookId, partyName);
    } catch (_) {
      // silently ignore
    }
  }

  // ── Determine OB status: Cleared or ₹X applied ───────────────────────────

  Future<void> _fetchObStatus(String cashbookId, String partyName) async {
    if (!mounted) return;
    try {
      final partyLow = partyName.toLowerCase();

      // 1. Get opening balance from party document
      final partyDoc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('parties')
          .doc(partyLow)
          .get();

      final ob =
          (partyDoc.data()?['openingBalance'] as num?)?.toDouble() ?? 0.0;

      if (ob <= 0) {
        if (mounted) setState(() => _obDisplay = 'Opening Balance');
        return;
      }

      // 2. Sum all OB payments for this party across all three detection modes
      final txSnap = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('transactions')
          .where('type', isEqualTo: 'income')
          .get();

      double totalObReceived = 0.0;
      for (final txDoc in txSnap.docs) {
        final raw    = txDoc.data();
        final linked = raw['linkedSaleBillId'] as String?;
        // Skip bill-linked allocations — those are not OB payments
        if (linked != null && linked.isNotEmpty) continue;

        final isObField  = raw['isObPayment'] as bool? ?? false;
        final txRawDesc  = raw['description'] as String? ?? '';
        final txDescLow  = txRawDesc.toLowerCase();
        final txCategory = (raw['category'] as String? ?? '').toLowerCase();

        bool countsAsOb = false;

        if (isObField) {
          // Strategy 1: flag-based
          final obParty = (raw['obPartyName'] as String? ?? '').toLowerCase();
          countsAsOb = obParty == partyLow;
        } else if (txDescLow.contains('opening balance') &&
                   txDescLow.contains(partyLow)) {
          // Strategy 2: description pattern
          countsAsOb = true;
        } else if (txCategory == 'wholesale' &&
                   txDescLow.trim() == partyLow) {
          // Strategy 3: wholesale income where description == party name
          countsAsOb = true;
        }

        if (countsAsOb) {
          totalObReceived += (raw['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }

      final remaining = (ob - totalObReceived).clamp(0.0, double.infinity);
      final fmt       = NumberFormat('#,##,##0.00');

      if (mounted) {
        if (remaining <= 0) {
          setState(() => _obDisplay = 'Cleared');
        } else {
          setState(() => _obDisplay =
              '₹${fmt.format(widget.transaction.amount)} applied to Opening Balance');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _obDisplay = 'Opening Balance');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isIncome = widget.transaction.type == 'income';
    final bool showPurchasePaymentDocs =
        kIsWeb || defaultTargetPlatform == TargetPlatform.iOS;
    final bool hasLinkedBill =
        (widget.transaction.linkedSaleBillId != null &&
            widget.transaction.linkedSaleBillId!.isNotEmpty) ||
        (showPurchasePaymentDocs &&
            widget.transaction.linkedPurchaseBillId != null &&
            widget.transaction.linkedPurchaseBillId!.isNotEmpty);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Transaction Details"),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isIncome
                    ? AppColors.income.withValues(alpha: 0.08)
                    : AppColors.expense.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isIncome
                      ? AppColors.income.withValues(alpha: 0.25)
                      : AppColors.expense.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                children: [

                  Icon(
                    isIncome
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: isIncome
                        ? AppColors.income
                        : AppColors.expense,
                    size: 40,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    isIncome ? "Income" : "Expense",
                    style: TextStyle(
                      color: isIncome
                          ? AppColors.income
                          : AppColors.expense,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    "₹${widget.transaction.amount.toStringAsFixed(0)}",
                    style: TextStyle(
                      color: isIncome
                          ? AppColors.income
                          : AppColors.expense,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _DetailTile(
              title: "Category",
              value: widget.transaction.category,
            ),

            _DetailTile(
              title: "Created By",
              value: widget.transaction.creatorName,
            ),

            _DetailTile(
              title: "Date",
              value: DateFormat(
                'dd MMM yyyy • hh:mm a',
              ).format(widget.transaction.createdAt),
            ),

            if (widget.transaction.description.isNotEmpty)
              _DetailTile(
                title: "Description",
                value: widget.transaction.description,
              ),

            if (showPurchasePaymentDocs &&
                widget.transaction.paymentAttachmentUrl != null &&
                widget.transaction.paymentAttachmentUrl!.isNotEmpty)
              _DocumentTile(
                title: 'Payment proof',
                name: widget.transaction.paymentAttachmentName ?? 'Attachment',
                icon: widget.transaction.paymentAttachmentType == 'pdf'
                    ? Icons.picture_as_pdf_rounded
                    : Icons.image_rounded,
                onTap: () => launchUrl(
                  Uri.parse(widget.transaction.paymentAttachmentUrl!),
                  mode: LaunchMode.externalApplication,
                ),
              ),

            if (showPurchasePaymentDocs &&
                widget.transaction.paymentReceiptUrl != null &&
                widget.transaction.paymentReceiptUrl!.isNotEmpty)
              _DocumentTile(
                title: 'Payment receipt',
                name: widget.transaction.paymentReceiptName ?? 'Receipt PDF',
                icon: Icons.receipt_long_rounded,
                onTap: () => _openReceipt(
                  widget.transaction.paymentReceiptUrl!,
                ),
              ),

            // Bill No. — shown when linked to either a sale or purchase bill
            if (hasLinkedBill)
              _DetailTile(
                title: "Bill No.",
                value: _loadingBill
                    ? 'Loading...'
                    : (_billNumber ?? '—'),
                valueBold: true,
              ),

            // Opening Balance status — shown for OB payments (all strategies)
            if (_isObPayment && !hasLinkedBill)
              _DetailTile(
                title: "Bill No.",
                value: _obDisplay.isEmpty ? 'Loading...' : _obDisplay,
                valueBold: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String title;
  final String value;
  final bool   valueBold;

  const _DetailTile({
    required this.title,
    required this.value,
    this.valueBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [

          Expanded(
            flex: 2,
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
                fontSize:   valueBold ? 15 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final String title;
  final String name;
  final IconData icon;
  final Future<bool> Function() onTap;

  const _DocumentTile({
    required this.title,
    required this.name,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        onTap: () async {
          final opened = await onTap();
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open this document')),
            );
          }
        },
        leading: Icon(icon, color: AppColors.income),
        title: Text(title,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        subtitle: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.open_in_new_rounded,
            color: AppColors.textSecondary, size: 18),
      ),
    );
  }
}
