import 'package:flutter/material.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';
import 'package:synccash/core/utils/currency_formatter.dart';

class BalanceCard extends StatefulWidget {
  final CashbookEntity cashbook;

  const BalanceCard({
    super.key,
    required this.cashbook,
  });

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard> {
  bool _hideBalance = true;

  @override
  Widget build(BuildContext context) {
    final cashbook = widget.cashbook;
    final bool positiveBalance = cashbook.totalBalance >= 0;
    final balanceColor =
        positiveBalance ? AppColors.income : AppColors.expense;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        // Richer dark gradient — three-stop radial feel via linear
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1628),
            Color(0xFF0D1A30),
            Color(0xFF101F38),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Subtle decorative circle top-right
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
          ),
          // Subtle decorative circle bottom-left
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: balanceColor.withOpacity(0.04),
              ),
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header row ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Live pulse dot
                            _PulseDot(color: AppColors.income),
                            const SizedBox(width: 8),
                            const Text(
                              'LIVE LEDGER',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Current Balance',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    _InviteCodeBadge(code: cashbook.inviteCode),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Balance amount ───────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _hideBalance
                          ? '••••••'
                          : '₹${CurrencyFormatter.format(cashbook.totalBalance)}',
                      style: TextStyle(
                        color: balanceColor,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        height: 1.0,
                      ),
                    ),
                    const Spacer(),
                    // Show/hide toggle — icon-only, clean
                    GestureDetector(
                      onTap: () =>
                          setState(() => _hideBalance = !_hideBalance),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                            width: 0.5,
                          ),
                        ),
                        child: Icon(
                          _hideBalance
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.white60,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Trend label (kept for layout parity, renders empty strings
                // from original logic — zero-height when empty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    positiveBalance ? '' : '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Divider ──────────────────────────────────────────────
                Container(
                  height: 0.5,
                  color: Colors.white.withOpacity(0.08),
                ),

                const SizedBox(height: 20),

                // ── Income / Expense cards ───────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _FinanceMetricCard(
                        title: 'Income',
                        value: cashbook.totalIncome,
                        hideAmount: _hideBalance,
                        icon: Icons.arrow_downward_rounded,
                        color: AppColors.income,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FinanceMetricCard(
                        title: 'Expense',
                        value: cashbook.totalExpense,
                        hideAmount: _hideBalance,
                        icon: Icons.arrow_upward_rounded,
                        color: AppColors.expense,
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
}

// ── Pulsing live dot ──────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ── Finance metric card ───────────────────────────────────────────────────────

class _FinanceMetricCard extends StatelessWidget {
  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final bool hideAmount;

  const _FinanceMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.hideAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color.withOpacity(0.75),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hideAmount
                      ? '₹*****'
                      : '₹${CurrencyFormatter.format(value)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Invite code badge ─────────────────────────────────────────────────────────

class _InviteCodeBadge extends StatelessWidget {
  final String code;
  const _InviteCodeBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.groups_rounded,
            color: Colors.white70,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}