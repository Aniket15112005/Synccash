import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

class TransactionDetailsSheet extends StatelessWidget {
  final TransactionEntity transaction;

  const TransactionDetailsSheet({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIncome =
        transaction.type.toLowerCase() == 'income';

    final Color color =
        isIncome ? AppColors.income : AppColors.expense;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          const SizedBox(height: 24),

          Icon(
            isIncome
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            color: color,
            size: 42,
          ),

          const SizedBox(height: 12),

          Text(
            isIncome ? "Income" : "Expense",
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            "${isIncome ? '+' : '-'}₹${CurrencyFormatter.format(transaction.amount)}",
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 28),

          _DetailTile(
            title: "Created By",
            value: transaction.creatorName,
          ),

          _DetailTile(
            title: "Category",
            value: transaction.category,
          ),

          _DetailTile(
            title: "Description",
            value: transaction.description.isEmpty
                ? "No description"
                : transaction.description,
          ),

          _DetailTile(
            title: "Date",
            value: DateFormat(
              'dd MMM yyyy, hh:mm a',
            ).format(transaction.createdAt),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String title;
  final String value;

  const _DetailTile({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}