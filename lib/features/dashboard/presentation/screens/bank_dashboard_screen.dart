// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show authProvider, authRepositoryProvider, currentCashbookIdProvider, currentUserIdProvider;
import 'package:synccash/features/settings/presentation/screens/settings_screen.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_list_item.dart';
import 'package:synccash/features/dashboard/presentation/screens/cb_dashboard_screen.dart';
import 'package:synccash/features/dashboard/presentation/screens/upi_dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _bankGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String _bankInitial(String? name) {
  final s = name?.trim();
  return (s == null || s.isEmpty) ? 'U' : s[0].toUpperCase();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bank Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class BankDashboardScreen extends ConsumerWidget {
  const BankDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookId = ref.watch(currentCashbookIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          strokeWidth: 1.5,
          onRefresh: () async {
            if (cashbookId != null) {
              ref.invalidate(bankTransactionsStreamProvider(cashbookId));
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              const SliverToBoxAdapter(
                child: RepaintBoundary(child: _BankHeader()),
              ),
              if (cashbookId != null) ...[
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _BankBalanceSection(cashbookId: cashbookId),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _BankSectionHeader(cashbookId: cashbookId),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                _BankRecentSliver(cashbookId: cashbookId),
              ] else
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No cashbook',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
      floatingActionButton: _BankFAB(cashbookId: cashbookId),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header  (greeting + "Cash" pill + settings + avatar)
// ─────────────────────────────────────────────────────────────────────────────

class _BankHeader extends ConsumerWidget {
  const _BankHeader();

  void _openSettings(BuildContext ctx) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const SettingsSheet(),
    );
  }

  Future<void> _confirmLogout(BuildContext ctx, WidgetRef ref) {
    return showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext ctx, WidgetRef ref) {
    final user = ref.read(authProvider).asData?.value;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BankProfileSheet(
        initial: _bankInitial(user?.displayName),
        displayName: user?.displayName,
        email: user?.email,
        onLogout: () {
          Navigator.pop(ctx);
          _confirmLogout(ctx, ref);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(
      authProvider.select((a) => a.asData?.value?.displayName),
    );
    final firstName = displayName?.split(' ').first ?? 'Welcome';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          // ── Greeting + name ──────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bankGreeting(),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  firstName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
          // ── "Cash" pill — taps to pop back to normal dashboard ───────
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16213A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A3F68)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wallet_rounded,
                      size: 14, color: Color(0xFF60A5FA)),
                  SizedBox(width: 6),
                  Text(
                    'Cash',
                    style: TextStyle(
                      color: Color(0xFF60A5FA),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── "UPI" pill — taps to UPI dashboard ──────────────────────
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UpiDashboardScreen()),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0E35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3D1D8A)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_balance_wallet_rounded,
                      size: 14, color: Color(0xFFA78BFA)),
                  SizedBox(width: 6),
                  Text(
                    'UPI',
                    style: TextStyle(
                      color: Color(0xFFA78BFA),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── "CB" pill — taps to CB dashboard ──────────────────────────
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const CbDashboardScreen()),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1200),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3D2800)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.book_rounded, size: 14, color: Color(0xFFFBBF24)),
                  SizedBox(width: 6),
                  Text(
                    'CB',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ── Settings button ──────────────────────────────────────────
          GestureDetector(
            onTap: () => _openSettings(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF111316),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF202228)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.settings_rounded,
                  size: 18, color: Color(0xFF9CA3AF)),
            ),
          ),
          const SizedBox(width: 10),
          // ── Avatar ───────────────────────────────────────────────────
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _openProfile(context, ref);
            },
            behavior: HitTestBehavior.opaque,
            child: _BankAvatar(initial: _bankInitial(displayName)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Balance section — computed client-side from bank transactions
// ─────────────────────────────────────────────────────────────────────────────

class _BankBalanceSection extends ConsumerWidget {
  final String cashbookId;
  const _BankBalanceSection({required this.cashbookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bankTransactionsStreamProvider(cashbookId));
    return async.when(
      data: (txs) {
        final income = txs
            .where((t) => t.type == 'income')
            .fold(0.0, (s, t) => s + t.amount);
        final expense = txs
            .where((t) => t.type == 'expense')
            .fold(0.0, (s, t) => s + t.amount);
        final balance = income - expense;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _BankBalanceCard(
              income: income, expense: expense, balance: balance),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
        )
            .animate()
            .shimmer(
                delay: 200.ms,
                duration: 1200.ms,
                color: Colors.white.withValues(alpha: 0.03)),
      ),
      error: (_, __) =>
          const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 0)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bank Balance Card
// ─────────────────────────────────────────────────────────────────────────────

class _BankBalanceCard extends StatefulWidget {
  final double income;
  final double expense;
  final double balance;
  const _BankBalanceCard(
      {required this.income, required this.expense, required this.balance});

  @override
  State<_BankBalanceCard> createState() => _BankBalanceCardState();
}

class _BankBalanceCardState extends State<_BankBalanceCard> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    final positive = widget.balance >= 0;
    final balColor = positive ? AppColors.income : AppColors.expense;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061526), Color(0xFF091D35), Color(0xFF0B1E3A)],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.5), width: 1.0),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 32,
              offset: const Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF34D399).withValues(alpha: 0.06),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header row ────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(children: [
                        _BankPulseDot(),
                        SizedBox(width: 7),
                        Text('BANK',
                            style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6)),
                      ]),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF34D399).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF34D399)
                                  .withValues(alpha: 0.20)),
                        ),
                        child: const Text('LIVE',
                            style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // ── Balance row ───────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Bank Balance',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2)),
                            const SizedBox(height: 6),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                          begin: const Offset(0, 0.15),
                                          end: Offset.zero)
                                      .animate(anim),
                                  child: child,
                                ),
                              ),
                              child: Text(
                                _hide
                                    ? '••••••'
                                    : '₹${CurrencyFormatter.format(widget.balance)}',
                                key: ValueKey<bool>(_hide),
                                style: TextStyle(
                                    color: balColor,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.0,
                                    height: 1.0),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _hide = !_hide);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: _hide
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                                width: 0.5),
                          ),
                          child: Icon(
                              _hide
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: Colors.white54,
                              size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.07)),
                  const SizedBox(height: 16),
                  // ── Income / Expense tiles ────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _BankMetricTile(
                            label: 'Income',
                            value: widget.income,
                            icon: Icons.south_rounded,
                            color: AppColors.income,
                            hide: _hide),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BankMetricTile(
                            label: 'Expense',
                            value: widget.expense,
                            icon: Icons.north_rounded,
                            color: AppColors.expense,
                            hide: _hide),
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

class _BankMetricTile extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool hide;
  const _BankMetricTile(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      required this.hide});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: color.withValues(alpha: 0.16), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    hide
                        ? '••••'
                        : '₹${CurrencyFormatter.format(value)}',
                    key: ValueKey<bool>(hide),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        overflow: TextOverflow.ellipsis),
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

class _BankPulseDot extends StatefulWidget {
  const _BankPulseDot();

  @override
  State<_BankPulseDot> createState() => _BankPulseDotState();
}

class _BankPulseDotState extends State<_BankPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
              const Color(0xFF34D399), const Color(0xFF10B981), _ctrl.value),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section header ("Recent" + filter button + "See all")
// ─────────────────────────────────────────────────────────────────────────────

class _BankSectionHeader extends ConsumerWidget {
  final String cashbookId;
  const _BankSectionHeader({required this.cashbookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: Text(
            'Recent',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const _BankFilterButton(),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => BankHistoryScreen(cashbookId: cashbookId)),
            );
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See all',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: -0.1)),
                SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded,
                    size: 14, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Filter button (reads active-filter count for badge)
// ─────────────────────────────────────────────────────────────────────────────

class _BankFilterButton extends ConsumerWidget {
  const _BankFilterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFilter   = ref.watch(bankDateFilterProvider);
    final typeFilter   = ref.watch(bankTypeFilterProvider);
    final amountFilter = ref.watch(bankAmountFilterProvider);
    final descFilter   = ref.watch(bankDescFilterProvider);

    final count = (dateFilter != null ? 1 : 0) +
        (typeFilter != null ? 1 : 0) +
        (amountFilter != null ? 1 : 0) +
        ((descFilter != null && descFilter.isNotEmpty) ? 1 : 0);
    final hasActive = count > 0;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _BankFilterSheet(),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasActive
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasActive
                ? Colors.transparent
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: 18,
                color: hasActive
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface),
            if (hasActive) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimary,
                    shape: BoxShape.circle),
                child: Center(
                  child: Text('$count',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Recent transactions sliver (max 5)
// ─────────────────────────────────────────────────────────────────────────────

class _BankRecentSliver extends ConsumerWidget {
  final String cashbookId;
  const _BankRecentSliver({required this.cashbookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async         = ref.watch(filteredBankTransactionsProvider(cashbookId));
    final currentUserId = ref.watch(currentUserIdProvider.select((id) => id));

    return async.when(
      data: (txs) {
        if (txs.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _BankEmptyState(),
            ),
          );
        }
        final count = txs.length > 5 ? 5 : txs.length;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: count,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(bottom: i < count - 1 ? 8 : 0),
              child: RepaintBoundary(
                child: TransactionListItem(
                  key: ValueKey(txs[i].transactionId),
                  transaction: txs[i],
                  currentUserId: currentUserId,
                )
                    .animate(delay: Duration(milliseconds: 40 + i * 35))
                    .fadeIn(duration: 260.ms)
                    .slideY(
                        begin: 0.035,
                        end: 0,
                        curve: Curves.easeOut,
                        duration: 260.ms),
              ),
            ),
          ),
        );
      },
      loading: () => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _BankListSkeleton(),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Error: $e',
              style:
                  const TextStyle(color: AppColors.expense, fontSize: 13)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FAB
// ─────────────────────────────────────────────────────────────────────────────

class _BankFAB extends StatelessWidget {
  final String? cashbookId;
  const _BankFAB({this.cashbookId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
          builder: (_) => const AddTransactionScreen(
            initialCategory: 'Bank',
            categoryLocked: true,
          ),
          ),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: const Color(0xFF059669),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF059669).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Add Transaction',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bank Filter Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _BankFilterSheet extends ConsumerStatefulWidget {
  const _BankFilterSheet();

  @override
  ConsumerState<_BankFilterSheet> createState() => _BankFilterSheetState();
}

class _BankFilterSheetState extends ConsumerState<_BankFilterSheet> {
  final _descCtrl = TextEditingController();
  final _minCtrl  = TextEditingController();
  final _maxCtrl  = TextEditingController();
  Timer? _debounce;
  String _dateLabel = '';

  @override
  void initState() {
    super.initState();
    final desc   = ref.read(bankDescFilterProvider);
    final amount = ref.read(bankAmountFilterProvider);
    if (desc != null) _descCtrl.text = desc;
    if (amount?.minAmount != null) {
      _minCtrl.text = amount!.minAmount!.toStringAsFixed(0);
    }
    if (amount?.maxAmount != null) {
      _maxCtrl.text = amount!.maxAmount!.toStringAsFixed(0);
    }
    _dateLabel = _labelFrom(ref.read(bankDateFilterProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _descCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  String _labelFrom(TransactionDateFilter? f) {
    final s = f?.startDate;
    final e = f?.endDate;
    if (s == null || e == null) return '';
    final now = DateTime.now();
    final ws  = now.subtract(Duration(days: now.weekday - 1));
    if (s == DateTime(now.year, now.month, now.day))   return 'Today';
    if (s == DateTime(ws.year,  ws.month,  ws.day))    return 'This Week';
    if (s == DateTime(now.year, now.month, 1))          return 'This Month';
    if (s == DateTime(now.year, 1, 1))                  return 'This Year';
    if (s.year == e.year && s.month == e.month && s.day == e.day) {
      return 'Single Date';
    }
    return 'Custom';
  }

  void _onDateChip(String label) {
    if (_dateLabel == label) {
      setState(() => _dateLabel = '');
      ref.read(bankDateFilterProvider.notifier).setFilter(null);
      return;
    }
    if (label == 'Single Date') { _pickSingle(); return; }
    if (label == 'Custom')      { _pickRange();  return; }
    setState(() => _dateLabel = label);
    final now = DateTime.now();
    final ws  = now.subtract(Duration(days: now.weekday - 1));
    final map = {
      'Today':      TransactionDateFilter(startDate: DateTime(now.year, now.month, now.day), endDate: now),
      'This Week':  TransactionDateFilter(startDate: DateTime(ws.year,  ws.month,  ws.day),  endDate: now),
      'This Month': TransactionDateFilter(startDate: DateTime(now.year, now.month, 1),        endDate: now),
      'This Year':  TransactionDateFilter(startDate: DateTime(now.year, 1, 1),                endDate: now),
    };
    ref.read(bankDateFilterProvider.notifier).setFilter(map[label]);
  }

  Future<void> _pickSingle() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() => _dateLabel = 'Single Date');
    ref.read(bankDateFilterProvider.notifier).setFilter(TransactionDateFilter(
      startDate: DateTime(picked.year, picked.month, picked.day),
      endDate:   DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
    ));
  }

  Future<void> _pickRange() async {
    final cur = ref.read(bankDateFilterProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange:
          (cur?.startDate != null && cur?.endDate != null)
              ? DateTimeRange(start: cur!.startDate!, end: cur.endDate!)
              : null,
    );
    if (!mounted || picked == null) return;
    setState(() => _dateLabel = 'Custom');
    ref.read(bankDateFilterProvider.notifier).setFilter(TransactionDateFilter(
      startDate: picked.start,
      endDate:
          DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
    ));
  }

  void _clearAll() {
    _debounce?.cancel();
    _descCtrl.clear();
    _minCtrl.clear();
    _maxCtrl.clear();
    setState(() => _dateLabel = '');
    ref.read(bankDateFilterProvider.notifier).setFilter(null);
    ref.read(bankTypeFilterProvider.notifier).setFilter(null);
    ref.read(bankAmountFilterProvider.notifier).setFilter(null);
    ref.read(bankDescFilterProvider.notifier).setFilter(null);
  }

  void _apply() {
    _debounce?.cancel();
    final min = double.tryParse(_minCtrl.text.trim());
    final max = double.tryParse(_maxCtrl.text.trim());
    ref.read(bankAmountFilterProvider.notifier).setFilter(
        (min == null && max == null)
            ? null
            : BankAmountFilter(minAmount: min, maxAmount: max));
    ref.read(bankDescFilterProvider.notifier).setFilter(
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final typeFilter = ref.watch(bankTypeFilterProvider);
    final mq         = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // Title + Clear
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filter Bank Transactions',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  TextButton(
                    onPressed: _clearAll,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear all',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Date range ────────────────────────────────────────────
            _BKLabel('DATE RANGE', theme),
            const SizedBox(height: 10),
            _BKChipRow(
              chips: const [
                'Today', 'This Week', 'This Month',
                'This Year', 'Single Date', 'Custom',
              ],
              selected: _dateLabel,
              onTap: _onDateChip,
            ),
            const SizedBox(height: 20),

            // ── Type ──────────────────────────────────────────────────
            _BKLabel('TYPE', theme),
            const SizedBox(height: 10),
            _BKChipRow(
              chips: const ['Income', 'Expense'],
              selected: typeFilter != null
                  ? typeFilter[0].toUpperCase() + typeFilter.substring(1)
                  : '',
              onTap: (t) {
                HapticFeedback.selectionClick();
                final lower = t.toLowerCase();
                ref
                    .read(bankTypeFilterProvider.notifier)
                    .setFilter(typeFilter == lower ? null : lower);
                setState(() {});
              },
            ),
            const SizedBox(height: 20),

            // ── Amount range ──────────────────────────────────────────
            _BKLabel('AMOUNT RANGE', theme),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _BKField(
                        ctrl: _minCtrl,
                        hint: 'Min amount',
                        icon: Icons.arrow_downward_rounded,
                        keyboard: TextInputType.number),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BKField(
                        ctrl: _maxCtrl,
                        hint: 'Max amount',
                        icon: Icons.arrow_upward_rounded,
                        keyboard: TextInputType.number),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Description search ────────────────────────────────────
            _BKLabel('SEARCH', theme),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _BKField(
                  ctrl: _descCtrl,
                  hint: 'Search by description',
                  icon: Icons.notes_rounded),
            ),
            const SizedBox(height: 24),

            // ── Apply button ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Apply Filters',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bank History Screen  (pushed from "See All")
// ─────────────────────────────────────────────────────────────────────────────

class BankHistoryScreen extends ConsumerStatefulWidget {
  final String cashbookId;
  const BankHistoryScreen({super.key, required this.cashbookId});

  @override
  ConsumerState<BankHistoryScreen> createState() => _BankHistoryScreenState();
}

class _BankHistoryScreenState extends ConsumerState<BankHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  // Local quick-filters (no extra providers needed)
  String _localType  = 'all'; // 'all' | 'income' | 'expense'
  String _localQuery = '';
  bool   _showSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260))
      ..forward();
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _searchCtrl.addListener(() {
      final t = _searchCtrl.text;
      if (t != _localQuery) setState(() => _localQuery = t);
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<TransactionEntity> _filter(List<TransactionEntity> txs) {
    return txs.where((tx) {
      if (_localType == 'income'  && tx.type != 'income')  return false;
      if (_localType == 'expense' && tx.type != 'expense') return false;
      final q = _localQuery.trim().toLowerCase();
      if (q.isNotEmpty &&
          !tx.description.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        ref.watch(currentUserIdProvider.select((id) => id));
    final async =
        ref.watch(filteredBankTransactionsProvider(widget.cashbookId));
    final fmt = NumberFormat('#,##,##0', 'en_IN');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── App bar ────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    size: 18, color: AppColors.textPrimary),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
              ),
              title: const Text('Bank History',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3)),
              actions: [
                const _BankFilterButton(),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                      _showSearch
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      size: 20,
                      color: AppColors.textSecondary),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) {
                        _searchCtrl.clear();
                        _localQuery = '';
                      }
                    });
                  },
                ),
                const SizedBox(width: 4),
              ],
              bottom: _showSearch
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(56),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Search description…',
                            prefixIcon: const Icon(Icons.search_rounded,
                                size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),

            async.when(
              data: (all) {
                final filtered = _filter(all);
                final income =
                    filtered.where((t) => t.type == 'income').fold(
                        0.0, (s, t) => s + t.amount);
                final expense =
                    filtered.where((t) => t.type == 'expense').fold(
                        0.0, (s, t) => s + t.amount);

                return SliverMainAxisGroup(
                  slivers: [
                    // Type chips
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Row(
                          children: ['All', 'Income', 'Expense'].map((l) {
                            final active = (l == 'All' &&
                                    _localType == 'all') ||
                                _localType == l.toLowerCase();
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _localType =
                                      l == 'All' ? 'all' : l.toLowerCase());
                                },
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? const Color(0xFF059669)
                                        : AppColors.surface,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                        color: active
                                            ? Colors.transparent
                                            : AppColors.border,
                                        width: 0.5),
                                  ),
                                  child: Text(l,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: active
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: active
                                              ? Colors.white
                                              : AppColors.textSecondary)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    // Summary strip
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 10, 20, 4),
                        child: Row(
                          children: [
                            Text('${filtered.length} entries',
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12)),
                            const SizedBox(width: 10),
                            Text('+₹${fmt.format(income.toInt())}',
                                style: const TextStyle(
                                    color: AppColors.income,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 6),
                            Text('−₹${fmt.format(expense.toInt())}',
                                style: const TextStyle(
                                    color: AppColors.expense,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_balance_rounded,
                                  size: 48,
                                  color: AppColors.textMuted
                                      .withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              const Text('No bank transactions',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 6, 20, 40),
                        sliver: SliverList.builder(
                          itemCount: filtered.length,
                          addAutomaticKeepAlives: false,
                          itemBuilder: (_, i) => Padding(
                            padding: EdgeInsets.only(
                                bottom: i < filtered.length - 1 ? 8 : 0),
                            child: RepaintBoundary(
                              child: TransactionListItem(
                                key: ValueKey(
                                    filtered[i].transactionId),
                                transaction: filtered[i],
                                currentUserId: currentUserId,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => SliverFillRemaining(
                hasScrollBody: false,
                child: _BankListSkeleton(),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: Text('Error: $e',
                        style: const TextStyle(
                            color: AppColors.expense))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Micro widgets
// ─────────────────────────────────────────────────────────────────────────────

class _BankEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.account_balance_rounded,
              size: 32, color: AppColors.textSecondary),
          SizedBox(height: 14),
          Text('No bank transactions',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2)),
          SizedBox(height: 5),
          Text('Tap the button below to add a bank entry.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5)),
        ],
      ),
    );
  }
}

class _BankListSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (i) => Container(
          height: 72,
          margin: EdgeInsets.only(bottom: i < 2 ? 8 : 0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
        )
            .animate(delay: Duration(milliseconds: i * 60))
            .fadeIn(duration: 220.ms)
            .then()
            .shimmer(
                duration: 1000.ms,
                color: Colors.white.withValues(alpha: 0.03)),
      ),
    );
  }
}

class _BankAvatar extends StatelessWidget {
  final String initial;
  const _BankAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A5F), Color(0xFF2563EB)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      ),
    );
  }
}

class _BankProfileSheet extends StatelessWidget {
  final String initial;
  final String? displayName;
  final String? email;
  final VoidCallback onLogout;
  const _BankProfileSheet(
      {required this.initial,
      this.displayName,
      this.email,
      required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 24),
          _BankAvatar(initial: initial),
          const SizedBox(height: 16),
          Text(displayName ?? 'User',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (email != null) ...[
            const SizedBox(height: 4),
            Text(email!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  side: BorderSide(
                      color: Colors.red.shade400.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Filter sheet micro-widgets ─────────────────────────────────────────────

class _BKLabel extends StatelessWidget {
  final String text;
  final ThemeData theme;
  const _BKLabel(this.text, this.theme);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.5),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                fontSize: 10,
              )),
        ),
      );
}

class _BKChipRow extends StatelessWidget {
  final List<String> chips;
  final String selected;
  final ValueChanged<String> onTap;
  const _BKChipRow(
      {required this.chips,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onTap(chips[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected == chips[i]
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected == chips[i]
                      ? Colors.transparent
                      : theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
              child: Text(chips[i],
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected == chips[i]
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: selected == chips[i]
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface)),
            ),
          ),
        ),
      ),
    );
  }
}

class _BKField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final TextInputType keyboard;
  const _BKField(
      {required this.ctrl,
      required this.hint,
      required this.icon,
      this.keyboard = TextInputType.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: 0.45),
            fontSize: 14),
        prefixIcon: Icon(icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: 0.55)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant
                    .withValues(alpha: 0.3),
                width: 0.5)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant
                    .withValues(alpha: 0.25),
                width: 0.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
                width: 1.2)),
      ),
    );
  }
}
