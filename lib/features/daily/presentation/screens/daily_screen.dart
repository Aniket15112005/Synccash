// lib/features/daily/presentation/screens/daily_screen.dart
//
// Main "Daily" screen, opened from Settings. Structurally similar to the
// main DashboardScreen (balance card, recent entries, filters, view all)
// but visually distinguished with a violet accent + a plain app bar
// (instead of the dashboard's greeting header), and entirely powered by
// the isolated Daily providers/entities — it never touches
// transaction_provider.dart or TransactionEntity.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/cashbook/presentation/providers/cashbook_provider.dart';
import 'package:synccash/features/dashboard/presentation/widgets/balance_card.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';
import 'package:synccash/features/daily/presentation/screens/daily_add_screen.dart';
import 'package:synccash/features/daily/presentation/screens/daily_history_screen.dart';
import 'package:synccash/features/daily/presentation/widgets/daily_filter_sheet.dart';
import 'package:synccash/features/daily/presentation/widgets/daily_list_item.dart';

const _kDailyAccent = Color(0xFF8B5CF6);
const _kDailyBg = Color(0xFF0E0B14);

class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final asyncCashbook = ref.watch(cashbookStreamProvider);

    return Scaffold(
      backgroundColor: _kDailyBg,
      body: SafeArea(
        child: cashbookId == null
            ? const Center(
                child: Text('No active cashbook',
                    style: TextStyle(color: Colors.white54)),
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _DailyHeader(),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: asyncCashbook.when(
                        loading: () => const SizedBox(
                          height: 180,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: _kDailyAccent)),
                        ),
                        error: (e, _) => SizedBox(
                          height: 180,
                          child: Center(
                            child: Text('Error: $e',
                                style: const TextStyle(color: Colors.white54)),
                          ),
                        ),
                        data: (cashbook) {
                          final summary =
                              ref.watch(dailySummaryProvider(cashbookId));
                          return summary.when(
                            loading: () => BalanceCard(
                              cashbook: cashbook,
                              incomeOverride: 0,
                              expenseOverride: 0,
                              balanceOverride: 0,
                              categoryLabel: 'DAILY',
                            ),
                            error: (e, _) => BalanceCard(
                              cashbook: cashbook,
                              incomeOverride: 0,
                              expenseOverride: 0,
                              balanceOverride: 0,
                              categoryLabel: 'DAILY',
                            ),
                            data: (s) => BalanceCard(
                              cashbook: cashbook,
                              incomeOverride: s.totalIncome,
                              expenseOverride: s.totalExpense,
                              balanceOverride: s.balance,
                              categoryLabel: 'DAILY',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Entries',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Row(children: [
                            const DailyFilterPanel(),
                            const SizedBox(width: 8),
                            _ViewAllButton(cashbookId: cashbookId),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  _DailyEntriesSliver(
                      cashbookId: cashbookId, currentUserId: currentUserId),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
      ),
      floatingActionButton: cashbookId == null
          ? null
          : _AddFAB(),
    );
  }
}

class _DailyHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: Colors.white70),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kDailyAccent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, color: _kDailyAccent, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              Text('Your personal income & expense tracker',
                  style: TextStyle(color: Colors.white38, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  final String cashbookId;
  const _ViewAllButton({required this.cashbookId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyHistoryScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('View all',
                style: TextStyle(
                    color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _DailyEntriesSliver extends ConsumerWidget {
  final String cashbookId;
  final String? currentUserId;
  const _DailyEntriesSliver({required this.cashbookId, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEntries = ref.watch(dailyFilteredEntriesProvider(cashbookId));

    return asyncEntries.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(color: _kDailyAccent)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('Error: $e', style: const TextStyle(color: Colors.white54)),
          ),
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, color: Colors.white24, size: 36),
                    SizedBox(height: 12),
                    Text('No Daily entries yet',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        }

        final recent = entries.take(5).toList();
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => DailyListItem(
                entry: recent[index],
                currentUserId: currentUserId,
                showTimeline: true,
                isLastInGroup: index == recent.length - 1,
              ),
              childCount: recent.length,
            ),
          ),
        );
      },
    );
  }
}

class _AddFAB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: _kDailyAccent,
      foregroundColor: Colors.white,
      onPressed: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyAddScreen()),
        );
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
