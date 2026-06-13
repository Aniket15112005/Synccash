// lib/features/transactions/presentation/widgets/transaction_action_sheet.dart

import 'package:flutter/material.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_list_item.dart';

class TransactionActionWrapper extends StatelessWidget {
  final TransactionEntity transaction;
  final String? currentUserId;
  final Future<void> Function() onDelete;

  const TransactionActionWrapper({
    super.key,
    required this.transaction,
    required this.currentUserId,
    required this.onDelete,
  });

  void _openEdit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          existingTransaction: transaction,
        ),
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TransactionActionSheet(
        transaction: transaction,
        onDelete: () => _confirmDelete(context),
        onEdit: () => _openEdit(context),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete transaction?',
            style:
                TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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
            onPressed: () async {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close action sheet
              await onDelete();
            },
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showActionSheet(context),
      behavior: HitTestBehavior.opaque,
      child: TransactionListItem(
        key: ValueKey(transaction.transactionId),
        transaction: transaction,
        currentUserId: currentUserId,
      ),
    );
  }
}

class _TransactionActionSheet extends StatelessWidget {
  final TransactionEntity transaction;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TransactionActionSheet({
    required this.transaction,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.type == 'income';
    final Color typeColor =
        isIncome ? AppColors.income : AppColors.expense;
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
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.2),
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
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isIncome
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
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
                            fontWeight: FontWeight.w700,
                            fontSize: 15),
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
                            color: theme
                                .colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${isIncome ? '+' : '-'}₹'
                  '${transaction.amount.toStringAsFixed(0)}',
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
              color: theme.colorScheme.outlineVariant
                  .withValues(alpha: 0.3),
            ),
          ),
          _ActionTile(
            icon: Icons.edit_outlined,
            label: 'Edit transaction',
            color: theme.colorScheme.onSurface,
            onTap: () {
              Navigator.pop(context); // close sheet
              onEdit(); // open edit screen
            },
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
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
