// lib/features/dashboard/presentation/widgets/balance_card.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _BalanceCardState extends State<BalanceCard>
    with SingleTickerProviderStateMixin {
  bool _hideBalance = true;

  late final AnimationController _revealCtrl;
  late final Animation<double> _revealAnim;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _revealAnim = CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _revealCtrl.dispose();
    super.dispose();
  }

  void _toggleBalance() {
    HapticFeedback.selectionClick();
    setState(() => _hideBalance = !_hideBalance);
    if (_hideBalance) {
      _revealCtrl.reverse();
    } else {
      _revealCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cashbook = widget.cashbook;
    final bool positiveBalance = cashbook.totalBalance >= 0;
    final Color balanceColor =
        positiveBalance ? AppColors.income : AppColors.expense;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0C1628),
            Color(0xFF0F1E35),
            Color(0xFF121F3A),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // ── Decorative glow ──────────────────────────────────────────
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      balanceColor.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Main content ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ── Header row ─────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Live pulse label
                      Row(
                        children: [
                          _PulseDot(color: AppColors.income),
                          const SizedBox(width: 7),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ],
                      ),
                      // Invite code badge
                      _InviteCodeBadge(code: cashbook.inviteCode),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ── Balance row ────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Balance',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Animated reveal on tap
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.15),
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: Text(
                                _hideBalance
                                    ? '••••••'
                                    : '₹${CurrencyFormatter.format(cashbook.totalBalance)}',
                                key: ValueKey<bool>(_hideBalance),
                                style: TextStyle(
                                  color: balanceColor,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.0,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Hide / show toggle ─────────────────────────────
                      GestureDetector(
                        onTap: _toggleBalance,
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: _hideBalance
                                ? Colors.white.withOpacity(0.06)
                                : Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                              width: 0.5,
                            ),
                          ),
                          child: Icon(
                            _hideBalance
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Divider ────────────────────────────────────────────
                  Container(
                    height: 0.5,
                    color: Colors.white.withOpacity(0.07),
                  ),

                  const SizedBox(height: 16),

                  // ── Income / Expense metric tiles ──────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          label: 'Income',
                          value: cashbook.totalIncome,
                          icon: Icons.south_rounded,
                          color: AppColors.income,
                          hideAmount: _hideBalance,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricTile(
                          label: 'Expense',
                          value: cashbook.totalExpense,
                          icon: Icons.north_rounded,
                          color: AppColors.expense,
                          hideAmount: _hideBalance,
                        ),
                      ),
                    ],
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Metric tile
// ─────────────────────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool hideAmount;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.hideAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.16),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color.withOpacity(0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    hideAmount
                        ? '₹*****'
                        : '₹${CurrencyFormatter.format(value)}',
                    key: ValueKey<bool>(hideAmount),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: -0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pulsing live dot — wrapped in RepaintBoundary so its animation
//  never triggers repaints in the card above it
// ─────────────────────────────────────────────────────────────────────────────

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
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.5, end: 1.0).animate(
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
    return RepaintBoundary(
      child: ScaleTransition(
        scale: _scale,
        child: FadeTransition(
          opacity: _opacity,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Invite code badge
// ─────────────────────────────────────────────────────────────────────────────

class _InviteCodeBadge extends StatelessWidget {
  final String code;
  const _InviteCodeBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.groups_rounded,
            color: Colors.white54,
            size: 12,
          ),
          const SizedBox(width: 5),
          Text(
            code,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}