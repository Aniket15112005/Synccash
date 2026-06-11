import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_details_sheet.dart';

final _transactionDateFormat = DateFormat('hh:mm a • MMM dd');

class TransactionListItem extends ConsumerWidget {
  final TransactionEntity transaction;
  final String? currentUserId;

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.currentUserId,
  });

  Future<void> _deleteTransaction(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(transactionRepositoryProvider)
          .deleteTransaction(transaction);
    } catch (e) {
      ref.invalidate(transactionsStreamProvider(transaction.cashbookId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppColors.expense,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showActionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _ItemActionSheet(
        transaction: transaction,
        onViewDetails: () {
          Navigator.pop(sheetCtx);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            backgroundColor: Colors.transparent,
            builder: (_) => TransactionDetailsSheet(transaction: transaction),
          );
        },
        onDelete: () {
          Navigator.pop(sheetCtx);
          _confirmAndDelete(context, ref);
        },
      ),
    );
  }

  void _confirmAndDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete transaction?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: Text(
          'This will permanently remove the '
          '₹${transaction.amount.toStringAsFixed(0)} '
          '${transaction.type} entry. This cannot be undone.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.expense,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteTransaction(context, ref);
            },
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isCurrentUser = transaction.createdBy == currentUserId;
    final bool isIncome = transaction.type.toLowerCase() == 'income';
    final Color badgeColor =
        isCurrentUser ? AppColors.userABadge : AppColors.userBBadge;
    final Color transactionColor =
        isIncome ? AppColors.income : AppColors.expense;
    final String displayTitle = transaction.description.isEmpty
        ? transaction.category.toUpperCase()
        : transaction.description;
    final String formattedAmount =
        '${isIncome ? '+' : '-'}₹${CurrencyFormatter.format(transaction.amount)}';
    final String formattedDate =
        _transactionDateFormat.format(transaction.createdAt);

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showActionSheet(context, ref),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: transactionColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: transactionColor.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: transactionColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isIncome
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: transactionColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _TagChip(
                            label: transaction.creatorName.toUpperCase(),
                            backgroundColor:
                                badgeColor.withValues(alpha: 0.15),
                            borderColor: badgeColor.withValues(alpha: 0.3),
                            textColor: badgeColor,
                          ),
                          const SizedBox(width: 8),
                          _TagChip(
                            label: transaction.category.toUpperCase(),
                            backgroundColor: AppColors.surfaceVariant,
                            textColor: AppColors.textSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: transactionColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Amount + type badge only — NO delete icon
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formattedAmount,
                      style: TextStyle(
                        color: transactionColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _TagChip(
                      label: isIncome ? 'INCOME' : 'EXPENSE',
                      backgroundColor:
                          transactionColor.withValues(alpha: 0.1),
                      textColor: transactionColor,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Action sheet shown on tap ─────────────────────────────────────────────────

class _ItemActionSheet extends StatelessWidget {
  final TransactionEntity transaction;
  final VoidCallback onViewDetails;
  final VoidCallback onDelete;

  const _ItemActionSheet({
    required this.transaction,
    required this.onViewDetails,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.type.toLowerCase() == 'income';
    final Color typeColor = isIncome ? AppColors.income : AppColors.expense;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isIncome
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: typeColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.category,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        transaction.description.isNotEmpty
                            ? transaction.description
                            : transaction.creatorName,
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${isIncome ? '+' : '-'}₹${transaction.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: typeColor,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(
                height: 24,
                color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
          ),
          _ActionTile(
            icon: Icons.receipt_long_outlined,
            label: 'View details',
            color: theme.colorScheme.onSurface,
            onTap: onViewDetails,
          ),
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Delete transaction',
            color: AppColors.expense,
            onTap: onDelete,
          ),
          _ActionTile(
            icon: Icons.close_rounded,
            label: 'Cancel',
            color: theme.colorScheme.onSurfaceVariant,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final double fontSize;
  final double letterSpacing;

  const _TagChip({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
    this.fontSize = 10,
    this.letterSpacing = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }
}