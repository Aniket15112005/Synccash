import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';

class BalanceCard extends StatelessWidget {
  final CashbookEntity cashbook;

  const BalanceCard({
    super.key,
    required this.cashbook,
  });

  @override
  Widget build(BuildContext context) {
    final bool positiveBalance = cashbook.totalBalance >= 0;

    return Container(
      height: 270,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
    Color(0xFF050B18),
    Color(0xFF0B1224),
    Color(0xFF111C35),
  ],
),
        boxShadow: const [],
      ),
      child: Stack(
        children: [

        

          // Main Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                              color: AppColors.income,
                              shape: BoxShape.circle,
                              boxShadow: const [],
),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              "LIVE LEDGER",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          "Current Balance",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),

                    _InviteCodeBadge(
                      code: cashbook.inviteCode,
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: -0.15),

                const Spacer(),

                // Balance Amount
                Text(
                  "₹${_formatAmount(cashbook.totalBalance)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 35,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.9,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 150.ms)
                    .scale(
                      begin: const Offset(0.9, 0.9),
                      duration: 500.ms,
                    ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      Icon(
                        positiveBalance
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: Colors.white,
                        size: 16,
                      ),

                      const SizedBox(width: 6),

                      Text(
                        positiveBalance
                            ? "Positive Cash Position"
                            : "Negative Cash Position",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(delay: 250.ms)
                    .slideY(begin: 0.2),

                const Spacer(),

                Row(
                  children: [

                    Expanded(
                      child: _FinanceMetricCard(
                        title: "Income",
                        value: cashbook.totalIncome,
                        icon: Icons.arrow_downward_rounded,
                        color: AppColors.income,
                        delay: 350.ms,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _FinanceMetricCard(
                        title: "Expense",
                        value: cashbook.totalExpense,
                        icon: Icons.arrow_upward_rounded,
                        color: AppColors.expense,
                        delay: 450.ms,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount.abs() >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (amount.abs() >= 100000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(2);
  }
}

class _FinanceMetricCard extends StatelessWidget {
  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final Duration delay;

  const _FinanceMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
     decoration: BoxDecoration(
  color: color.withOpacity(0.08),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(
    color: color.withOpacity(0.25),
  ),
),
      child: Row(
        children: [

          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
  title,
  style: TextStyle(
    color: color,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  ),
),

                const SizedBox(height: 4),

                Text(
  "₹${value.toStringAsFixed(0)}",
  style: TextStyle(
    color: color,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  ),
),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: delay)
        .slideY(begin: 0.2);
  }
}

class _InviteCodeBadge extends StatelessWidget {
  final String code;

  const _InviteCodeBadge({
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [

          const Icon(
            Icons.groups_rounded,
            color: Colors.white,
            size: 14,
          ),

          const SizedBox(width: 6),

          Text(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}