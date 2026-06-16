import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/sales/presentation/providers/sale_bill_provider.dart';

class TransactionDetailsSheet extends ConsumerWidget {
  final TransactionEntity transaction;
  const TransactionDetailsSheet({super.key, required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = transaction.type.toLowerCase() == 'income';
    final amountStr =
        '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(transaction.amount)}';

    // Bill number lookup from live map (no extra Firestore read needed)
    final _billMap    = ref.watch(saleBillNumberMapProvider).asData?.value ?? {};
    final _linkedId   = transaction.linkedSaleBillId;
    final _billNumber = (_linkedId != null && _linkedId.isNotEmpty)
        ? _billMap[_linkedId]
        : null;
    final _hasBillNo  = _billNumber != null && _billNumber.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0E12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 32, height: 3, margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF374151),
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Amount hero
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1218),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1F2937)),
          ),
          child: Column(children: [
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2D3240)),
              ),
              child: Text(
                isIncome ? 'INCOME' : 'EXPENSE',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              amountStr,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                letterSpacing: -1,
                color: isIncome
                    ? const Color(0xF0E1EBF8)
                    : const Color(0xCCA0AEBE),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('dd MMM yyyy, hh:mm a')
                  .format(transaction.createdAt),
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 12,
              ),
            ),
          ]),
        ),

        const SizedBox(height: 16),

        // Detail rows
        _DetailRow(label: 'Category',   value: transaction.category),
        _DetailRow(label: 'Created by', value: transaction.creatorName),
        _DetailRow(
          label: 'Description',
          value: transaction.description.isEmpty
              ? 'No description'
              : transaction.description,
        ),
        _DetailRow(
          label: 'Date',
          value: DateFormat('dd MMM yyyy').format(transaction.createdAt),
        ),
        _DetailRow(
          label: 'Time',
          value: DateFormat('hh:mm a').format(transaction.createdAt),
          isLast: !_hasBillNo,
        ),
        if (_hasBillNo)
          _DetailRow(
            label: 'Bill No.',
            value: _billNumber!,
            isLast: true,
          ),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              )),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD1D9E6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      ),
      if (!isLast)
        Container(height: 0.5, color: const Color(0xFF1A1D25)),
    ]);
  }
}