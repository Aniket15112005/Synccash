import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

class TransactionDetailsScreen extends StatelessWidget {
  final TransactionEntity transaction;

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.type == 'income';

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
                    ? AppColors.income.withOpacity(0.08)
                    : AppColors.expense.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isIncome
                      ? AppColors.income.withOpacity(0.25)
                      : AppColors.expense.withOpacity(0.25),
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
                    "₹${transaction.amount.toStringAsFixed(0)}",
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
              value: transaction.category,
            ),

            _DetailTile(
              title: "Created By",
              value: transaction.creatorName,
            ),

            _DetailTile(
              title: "Date",
              value: DateFormat(
                'dd MMM yyyy • hh:mm a',
              ).format(transaction.createdAt),
            ),

            if (transaction.description.isNotEmpty)
              _DetailTile(
                title: "Description",
                value: transaction.description,
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

  const _DetailTile({
    required this.title,
    required this.value,
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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}