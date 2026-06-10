import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_details_sheet.dart';

class TransactionListItem extends ConsumerWidget {
  final TransactionEntity transaction;

  const TransactionListItem({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authProvider).value;

    final bool isCurrentUser =
        transaction.createdBy == currentUser?.uid;

    final bool isIncome =
        transaction.type.toLowerCase() == 'income';

    final Color badgeColor = isCurrentUser
        ? AppColors.userABadge
        : AppColors.userBBadge;

    final Color transactionColor =
        isIncome ? AppColors.income : AppColors.expense;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.transparent,
  builder: (_) => TransactionDetailsSheet(
    transaction: transaction,
  ),
);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: 7,
          ),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: transactionColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: transactionColor.withOpacity(0.18),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: transactionColor.withOpacity(0.05),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // ICON

              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: transactionColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isIncome
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: transactionColor,
                  size: 24,
                ),
              ),

              const SizedBox(width: 14),

              // CENTER CONTENT

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                badgeColor.withOpacity(0.15),
                            borderRadius:
                                BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  badgeColor.withOpacity(
                                      0.35),
                            ),
                          ),
                          child: Text(
                            transaction.creatorName
                                .toUpperCase(),
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                AppColors.surfaceVariant,
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                          child: Text(
                            transaction.category
                                .toUpperCase(),
                            style: const TextStyle(
                              color:
                                  AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      transaction.description.isEmpty
                          ? transaction.category
                              .toUpperCase()
                          : transaction.description,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: transactionColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      DateFormat(
                        'hh:mm a • MMM dd',
                      ).format(transaction.createdAt),
                      style: const TextStyle(
                        color:
                            AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // AMOUNT

              Column(
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncome ? "+" : "-"}₹${CurrencyFormatter.format(transaction.amount)}',
                    style: TextStyle(
                      color: transactionColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: transactionColor
                          .withOpacity(0.10),
                      borderRadius:
                          BorderRadius.circular(6),
                    ),
                    child: Text(
                      isIncome
                          ? 'INCOME'
                          : 'EXPENSE',
                      style: TextStyle(
                        color: transactionColor,
                        fontSize: 9,
                        fontWeight:
                            FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}