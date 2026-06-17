// lib/features/dashboard/presentation/screens/upi_dashboard_screen.dart
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
import 'package:synccash/features/dashboard/presentation/screens/bank_dashboard_screen.dart';
import 'package:synccash/features/dashboard/presentation/screens/cb_dashboard_screen.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

// ── UPI theme colours ─────────────────────────────────────────────────────────
const _kUpiPrimary    = Color(0xFFA78BFA);  // purple 400
const _kUpiDark       = Color(0xFF7C3AED);  // purple 600
const _kUpiDimBg      = Color(0xFF1A0E35);
const _kUpiBorder     = Color(0xFF3D1D8A);
const _kUpiGlowStart  = Color(0xFF0D0820);
const _kUpiGlowMid    = Color(0xFF120D2E);
const _kUpiGlowEnd    = Color(0xFF13103A);

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _upiGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String _upiInitial(String? name) {
  final s = name?.trim();
  return (s == null || s.isEmpty) ? 'U' : s[0].toUpperCase();
}

// ─────────────────────────────────────────────────────────────────────────────
//  UPI Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class UpiDashboardScreen extends ConsumerWidget {
  const UpiDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookId = ref.watch(currentCashbookIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: _kUpiPrimary,
          backgroundColor: AppColors.surface,
          strokeWidth: 1.5,
          onRefresh: () async {
            if (cashbookId != null) {
              ref.invalidate(upiTransactionsStreamProvider(cashbookId));
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              const SliverToBoxAdapter(
                child: RepaintBoundary(child: _UpiHeader()),
              ),
              if (cashbookId != null) ...[
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _UpiBalanceSection(cashbookId: cashbookId),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _UpiSectionHeader(cashbookId: cashbookId),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                _UpiRecentSliver(cashbookId: cashbookId),
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
      floatingActionButton: _UpiFAB(cashbookId: cashbookId),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header  (greeting + "Cash" pill + "Bank" pill + settings + avatar)
// ─────────────────────────────────────────────────────────────────────────────

class _UpiHeader extends ConsumerWidget {
  const _UpiHeader();

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
      builder: (_) => _UpiProfileSheet(
        initial: _upiInitial(user?.displayName),
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
          const Spacer(),
          // ── "Cash" pill — taps back to normal dashboard ──────────────
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
                  Icon(Icons.wallet_rounded, size: 14, color: Color(0xFF60A5FA)),
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
          if (kIsWeb || (!kIsWeb && Platform.isIOS)) ...[
            const SizedBox(width: 8),
            // ── "Bank" pill — taps to Bank dashboard ────────────────────
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const BankDashboardScreen()),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E2A1F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1B4D35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_rounded,
                        size: 14, color: Color(0xFF34D399)),
                    SizedBox(width: 6),
                    Text(
                      'Bank',
                      style: TextStyle(
                        color: Color(0xFF34D399),
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
          ],
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
            child: _UpiAvatar(initial: _upiInitial(displayName)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Balance section — computed client-side from UPI transactions
// ─────────────────────────────────────────────────────────────────────────────

class _UpiBalanceSection extends ConsumerWidget {
  final String cashbookId;
  const _UpiBalanceSection({required this.cashbookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upiTransactionsStreamProvider(cashbookId));
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
          child: _UpiBalanceCard(
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
//  UPI Balance Card
// ─────────────────────────────────────────────────────────────────────────────

class _UpiBalanceCard extends StatefulWidget {
  final double income;
  final double expense;
  final double balance;
  const _UpiBalanceCard(
      {required this.income, required this.expense, required this.balance});

  @override
  State<_UpiBalanceCard> createState() => _UpiBalanceCardState();
}

class _UpiBalanceCardState extends State<_UpiBalanceCard> {
  bool _hide = false;

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
          colors: [_kUpiGlowStart, _kUpiGlowMid, _kUpiGlowEnd],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
            color: _kUpiBorder.withValues(alpha: 0.5), width: 1.0),
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
                    _kUpiPrimary.withValues(alpha: 0.08),
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
                    children: [
                      const _UpiPulseDot(),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'UPI',
                            style: TextStyle(
                              color: _kUpiPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kUpiPrimary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _kUpiPrimary.withValues(alpha: 0.20)),
                        ),
                        child: const Text('LIVE',
                            style: TextStyle(
                                color: _kUpiPrimary,
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
                            const Text('UPI Balance',
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
                        child: _UpiMetricTile(
                            label: 'Income',
                            value: widget.income,
                            icon: Icons.south_rounded,
                            color: AppColors.income,
                            hide: _hide),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _UpiMetricTile(
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

class _UpiMetricTile extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool hide;
  const _UpiMetricTile(
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

class _UpiPulseDot extends StatefulWidget {
  const _UpiPulseDot();

  @override
  State<_UpiPulseDot> createState() => _UpiPulseDotState();
}

class _UpiPulseDotState extends State<_UpiPulseDot>
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
          color: Color.lerp(_kUpiPrimary, _kUpiDark, _ctrl.value),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section header ("Recent" + filter button + "See all")
// ─────────────────────────────────────────────────────────────────────────────

class _UpiSectionHeader extends ConsumerWidget {
  final String cashbookId;
  const _UpiSectionHeader({required this.cashbookId});

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
        const _UpiFilterButton(),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => UpiHistoryScreen(cashbookId: cashbookId)),
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
//  Filter button (badge count)
// ─────────────────────────────────────────────────────────────────────────────

class _UpiFilterButton extends ConsumerWidget {
  const _UpiFilterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFilter   = ref.watch(upiDateFilterProvider);
    final typeFilter   = ref.watch(upiTypeFilterProvider);
    final amountFilter = ref.watch(upiAmountFilterProvider);
    final descFilter   = ref.watch(upiDescFilterProvider);

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
          builder: (_) => const _UpiFilterSheet(),
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

class _UpiRecentSliver extends ConsumerWidget {
  final String cashbookId;
  const _UpiRecentSliver({required this.cashbookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async         = ref.watch(filteredUpiTransactionsProvider(cashbookId));
    final currentUserId = ref.watch(currentUserIdProvider.select((id) => id));

    return async.when(
      data: (txs) {
        if (txs.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _UpiEmptyState(),
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
          child: _UpiListSkeleton(),
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

class _UpiFAB extends StatelessWidget {
  final String? cashbookId;
  const _UpiFAB({this.cashbookId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AddTransactionScreen(
              initialCategory: 'UPI',
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
          color: _kUpiDark,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kUpiDark.withValues(alpha: 0.35),
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
//  UPI Filter Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _UpiFilterSheet extends ConsumerStatefulWidget {
  const _UpiFilterSheet();

  @override
  ConsumerState<_UpiFilterSheet> createState() => _UpiFilterSheetState();
}

class _UpiFilterSheetState extends ConsumerState<_UpiFilterSheet> {
  final _descCtrl = TextEditingController();
  final _minCtrl  = TextEditingController();
  final _maxCtrl  = TextEditingController();
  Timer? _debounce;
  String _dateLabel = '';

  @override
  void initState() {
    super.initState();
    final desc   = ref.read(upiDescFilterProvider);
    final amount = ref.read(upiAmountFilterProvider);
    if (desc != null) _descCtrl.text = desc;
    if (amount?.minAmount != null) {
      _minCtrl.text = amount!.minAmount!.toStringAsFixed(0);
    }
    if (amount?.maxAmount != null) {
      _maxCtrl.text = amount!.maxAmount!.toStringAsFixed(0);
    }
    _dateLabel = _labelFrom(ref.read(upiDateFilterProvider));
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
      ref.read(upiDateFilterProvider.notifier).setFilter(null);
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
    ref.read(upiDateFilterProvider.notifier).setFilter(map[label]);
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
    ref.read(upiDateFilterProvider.notifier).setFilter(TransactionDateFilter(
      startDate: DateTime(picked.year, picked.month, picked.day),
      endDate:   DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
    ));
  }

  Future<void> _pickRange() async {
    final cur = ref.read(upiDateFilterProvider);
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
    ref.read(upiDateFilterProvider.notifier).setFilter(TransactionDateFilter(
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
    ref.read(upiDateFilterProvider.notifier).setFilter(null);
    ref.read(upiTypeFilterProvider.notifier).setFilter(null);
    ref.read(upiAmountFilterProvider.notifier).setFilter(null);
    ref.read(upiDescFilterProvider.notifier).setFilter(null);
  }

  void _apply() {
    _debounce?.cancel();
    final min = double.tryParse(_minCtrl.text.trim());
    final max = double.tryParse(_maxCtrl.text.trim());
    ref.read(upiAmountFilterProvider.notifier).setFilter(
        (min == null && max == null)
            ? null
            : BankAmountFilter(minAmount: min, maxAmount: max));
    ref.read(upiDescFilterProvider.notifier).setFilter(
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final typeFilter = ref.watch(upiTypeFilterProvider);
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
                  Text('Filter UPI Transactions',
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
            _UKLabel('DATE RANGE', theme),
            const SizedBox(height: 10),
            _UKChipRow(
              chips: const [
                'Today', 'This Week', 'This Month',
                'This Year', 'Single Date', 'Custom',
              ],
              selected: _dateLabel,
              onTap: _onDateChip,
            ),
            const SizedBox(height: 20),

            // ── Type ──────────────────────────────────────────────────
            _UKLabel('TYPE', theme),
            const SizedBox(height: 10),
            _UKChipRow(
              chips: const ['Income', 'Expense'],
              selected: typeFilter != null
                  ? typeFilter[0].toUpperCase() + typeFilter.substring(1)
                  : '',
              onTap: (t) {
                HapticFeedback.selectionClick();
                final lower = t.toLowerCase();
                ref
                    .read(upiTypeFilterProvider.notifier)
                    .setFilter(typeFilter == lower ? null : lower);
                setState(() {});
              },
            ),
            const SizedBox(height: 20),

            // ── Amount range ──────────────────────────────────────────
            _UKLabel('AMOUNT RANGE', theme),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _UKField(
                        ctrl: _minCtrl,
                        hint: 'Min amount',
                        icon: Icons.arrow_downward_rounded,
                        keyboard: TextInputType.number),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _UKField(
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
            _UKLabel('SEARCH', theme),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _UKField(
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
//  UPI History Screen
// ─────────────────────────────────────────────────────────────────────────────

class UpiHistoryScreen extends ConsumerStatefulWidget {
  final String cashbookId;
  const UpiHistoryScreen({super.key, required this.cashbookId});

  @override
  ConsumerState<UpiHistoryScreen> createState() => _UpiHistoryScreenState();
}

class _UpiHistoryScreenState extends ConsumerState<UpiHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  String _localType  = 'all';
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
        ref.watch(filteredUpiTransactionsProvider(widget.cashbookId));
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
              title: const Text('UPI History',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3)),
              actions: [
                const _UpiFilterButton(),
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
                                        ? _kUpiDark
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
                              Icon(Icons.account_balance_wallet_rounded,
                                  size: 48,
                                  color: AppColors.textMuted
                                      .withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              const Text('No UPI transactions',
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
                child: _UpiListSkeleton(),
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

class _UpiEmptyState extends StatelessWidget {
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
          Icon(Icons.account_balance_wallet_rounded,
              size: 32, color: AppColors.textSecondary),
          SizedBox(height: 14),
          Text('No UPI transactions',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2)),
          SizedBox(height: 5),
          Text('Tap the button below to add a UPI entry.',
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

class _UpiListSkeleton extends StatelessWidget {
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

class _UpiAvatar extends StatelessWidget {
  final String initial;
  const _UpiAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4C1D95), _kUpiDark],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _UpiProfileSheet extends StatelessWidget {
  final String initial;
  final String? displayName;
  final String? email;
  final VoidCallback onLogout;

  const _UpiProfileSheet({
    required this.initial,
    required this.displayName,
    required this.email,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                height: 100,
                margin: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4C1D95), _kUpiDark, Color(0xFF6D28D9)],
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_kUpiPrimary, _kUpiDark],
                    ),
                    border:
                        Border.all(color: theme.colorScheme.surface, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: _kUpiDark.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 52),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  displayName ?? 'User',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mail_outline_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6)),
                      const SizedBox(width: 5),
                      Text(
                        email ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.logout_rounded,
                          color: Colors.red.shade400, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sign out',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade400)),
                          Text('You will need to log in again',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.3)),
                  ],
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

// ── Filter sheet micro widgets ─────────────────────────────────────────────────

class _UKLabel extends StatelessWidget {
  final String text;
  final ThemeData theme;
  const _UKLabel(this.text, this.theme);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                fontSize: 10,
              )),
        ),
      );
}

class _UKChipRow extends StatelessWidget {
  final List<String> chips;
  final String selected;
  final ValueChanged<String> onTap;
  const _UKChipRow(
      {required this.chips, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: chips.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _UKChip(
              label: chips[i],
              isSelected: selected == chips[i],
              onTap: () => onTap(chips[i]),
            ),
          ),
        ),
      );
}

class _UKChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _UKChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            )),
      ),
    );
  }
}

class _UKField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final TextInputType keyboard;
  const _UKField(
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
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            fontSize: 14),
        prefixIcon: Icon(icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
              width: 1.2),
        ),
      ),
    );
  }
}
