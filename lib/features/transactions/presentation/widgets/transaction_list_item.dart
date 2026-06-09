import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

class TransactionListItem extends ConsumerWidget {
  final TransactionEntity transaction;

  const TransactionListItem({super.key, required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authProvider).value;
    final bool isCurrentUser = transaction.createdBy == currentUser?.uid;
    final bool isIncome = transaction.type == 'income';

    final Color badgeColor = isCurrentUser ? AppColors.userABadge : AppColors.userBBadge;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor.withOpacity(0.5), width: 1),
            ),
            child: Text(
              transaction.creatorName.toUpperCase(),
              style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description.isEmpty ? transaction.category.toUpperCase() : transaction.description,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('hh:mm a - MMM dd').format(transaction.createdAt),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${isIncome ? "+" : "-"}₹${transaction.amount.toStringAsFixed(0)}',
            style: TextStyle(
              color: isIncome ? AppColors.income : AppColors.expense,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}