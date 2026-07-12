// lib/features/daily/presentation/screens/daily_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/cashbook/presentation/providers/cashbook_provider.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';
import 'package:synccash/features/daily/presentation/screens/daily_add_screen.dart';
import 'package:synccash/features/daily/cards/presentation/screens/daily_cards_screen.dart';
import 'package:synccash/features/daily/presentation/screens/daily_history_screen.dart';
import 'package:synccash/features/daily/presentation/widgets/daily_filter_sheet.dart';
import 'package:synccash/features/daily/presentation/widgets/daily_list_item.dart'
    show showDailyEntryActions;

// ── Palette ──────────────────────────────────────────────────────────────────
const _kAccent   = Color(0xFF8B5CF6);
const _kText     = Color(0xFF111827);
const _kTextSub  = Color(0xFF9CA3AF);
const _kCard     = Color(0xFFFFFFFF);
const _kCardSub  = Color(0xFFF3F4F6); // light gray for pills / dividers
const _kIncome   = Color(0xFF16A34A);
const _kIncBg    = Color(0xFFDCFCE7);
const _kExpense  = Color(0xFFDC2626);
const _kExpBg    = Color(0xFFFEE2E2);
const _kDark     = Color(0xFF111827); // FAB

// Gradient background colours
const _kGradTop  = Color(0xFFEDEAF4);
const _kGradBot  = Color(0xFFDDD9EC);

final _dateFmt   = DateFormat('dd MMM yyyy · hh:mm a');

class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookId    = ref.watch(currentCashbookIdProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final asyncCashbook = ref.watch(cashbookStreamProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kGradTop, _kGradBot],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: cashbookId == null
              ? const Center(
                  child: Text('No active cashbook',
                      style: TextStyle(color: _kTextSub)),
                )
              : CustomScrollView(
                  slivers: [
                    // ── Header ────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: _DailyHeader(),
                    ),

                    // ── Cards entry button ─────────────────────────────
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      sliver: SliverToBoxAdapter(
                        child: _CardsButton(),
                      ),
                    ),

                    // ── Balance card ──────────────────────────────────
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      sliver: SliverToBoxAdapter(
                        child: asyncCashbook.when(
                          loading: () => _BalancePlaceholder(),
                          error:   (_, __) => _BalancePlaceholder(),
                          data: (cashbook) {
                            final summary =
                                ref.watch(dailySummaryProvider(cashbookId));
                            final income = summary.whenOrNull(
                                  data: (s) => s.totalIncome) ??
                                0.0;
                            final expense = summary.whenOrNull(
                                  data: (s) => s.totalExpense) ??
                                0.0;
                            final balance = income - expense;
                            return _BalanceCard(
                              cashbookCode: cashbook.inviteCode.isNotEmpty
                                  ? cashbook.inviteCode
                                  : cashbook.id.substring(0, 6).toUpperCase(),
                              balance: balance,
                              income: income,
                              expense: expense,
                            );
                          },
                        ),
                      ),
                    ),

                    // ── Recent Entries header ─────────────────────────
                    SliverPadding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Recent Entries',
                              style: TextStyle(
                                color: _kText,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            Row(children: [
                              // filter icon
                              const DailyFilterPanel(),
                              const SizedBox(width: 10),
                              // view all pill
                              _ViewAllButton(cashbookId: cashbookId),
                            ]),
                          ],
                        ),
                      ),
                    ),

                    // ── Entry rows ────────────────────────────────────
                    _HomeEntriesSliver(
                      cashbookId: cashbookId,
                      currentUserId: currentUserId,
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 110)),
                  ],
                ),
        ),
      ),
      floatingActionButton:
          cashbookId == null ? null : _AddFAB(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header
// ─────────────────────────────────────────────────────────────────────────────

class _DailyHeader extends StatelessWidget {
  static const _cardShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 14,
      offset: Offset(0, 2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Row(
        children: [
          // back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(13),
                boxShadow: _cardShadow,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: Color(0xFF374151),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // bolt circle
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: _kDark,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily',
                  style: TextStyle(
                      color: _kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4)),
              Text('Your personal income & expense tracker',
                  style: TextStyle(color: _kTextSub, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cards entry button
// ─────────────────────────────────────────────────────────────────────────────

class _CardsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyCardsScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6D5DFB), Color(0xFF2E1F8F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6D5DFB).withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.credit_card_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cards',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                  SizedBox(height: 2),
                  Text('Track income & expenses per card',
                      style: TextStyle(
                          color: Color(0xCCFFFFFF), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Balance card (all-white, hidden amount)
// ─────────────────────────────────────────────────────────────────────────────

class _BalanceCard extends StatefulWidget {
  final String cashbookCode;
  final double balance;
  final double income;
  final double expense;
  const _BalanceCard({
    required this.cashbookCode,
    required this.balance,
    required this.income,
    required this.expense,
  });

  @override
  State<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<_BalanceCard> {
  bool _visible = false;

  static const _shadow = [
    BoxShadow(
      color: Color(0x14643CB4),
      blurRadius: 16,
      offset: Offset(0, 3),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final balStr = CurrencyFormatter.format(widget.balance.abs());
    final incStr = CurrencyFormatter.format(widget.income);
    final expStr = CurrencyFormatter.format(widget.expense);

    return Column(
      children: [
        // ── Main balance tile ────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(22),
            boxShadow: _shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // green dot + cashbook code
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kCardSub,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.cashbookCode,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // label
              const Center(
                child: Text(
                  'Total Balance',
                  style: TextStyle(
                      color: _kTextSub,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 10),
              // amount / dots row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_visible)
                    Text(
                      '₹$balStr',
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    )
                  else
                    Row(
                      children: List.generate(
                        6,
                        (_) => Container(
                          width: 8,
                          height: 8,
                          margin:
                              const EdgeInsets.symmetric(horizontal: 3),
                          decoration: const BoxDecoration(
                            color: Color(0xFFD1D5DB),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setState(() => _visible = !_visible),
                    child: Icon(
                      _visible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: _kTextSub,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Income / Expense mini cards ──────────────────────
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                label: 'Income',
                value: incStr,
                isVisible: _visible,
                isIncome: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStatCard(
                label: 'Expense',
                value: expStr,
                isVisible: _visible,
                isIncome: false,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool   isVisible;
  final bool   isIncome;
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.isVisible,
    required this.isIncome,
  });

  static const _shadow = [
    BoxShadow(
      color: Color(0x14643CB4),
      blurRadius: 14,
      offset: Offset(0, 2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? _kIncome : _kExpense;
    final bg    = isIncome ? _kIncBg  : _kExpBg;
    final icon  = isIncome
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: _kText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          if (isVisible)
            Text('₹$value',
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5))
          else
            Row(
              children: List.generate(
                4,
                (_) => Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD1D5DB),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BalancePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: _kAccent),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  View-all button
// ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('View all',
                style: TextStyle(
                    color: _kText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right_rounded,
                size: 17, color: _kText),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Home entries — avatar style, inside a single white card
// ─────────────────────────────────────────────────────────────────────────────

class _HomeEntriesSliver extends ConsumerWidget {
  final String  cashbookId;
  final String? currentUserId;
  const _HomeEntriesSliver(
      {required this.cashbookId, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Capped "recent" window — this preview only ever shows 5 rows, so it
    // doesn't need to pull the entire Daily history. Full, unbounded data
    // is still available on the History screen.
    final asyncEntries =
        ref.watch(dailyRecentFilteredEntriesProvider(cashbookId));

    return asyncEntries.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
              child: CircularProgressIndicator(color: _kAccent)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('Error: $e',
                style: const TextStyle(color: _kTextSub)),
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
                    Icon(Icons.receipt_long_outlined,
                        color: Color(0xFFC8C6C2), size: 40),
                    SizedBox(height: 12),
                    Text('No Daily entries yet',
                        style: TextStyle(
                            color: _kTextSub, fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        }

        final recent = entries.take(5).toList();

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14643CB4),
                    blurRadius: 16,
                    offset: Offset(0, 3),
                  ),
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  for (var i = 0; i < recent.length; i++) ...[
                    _HomeEntryRow(
                      entry: recent[i],
                      currentUserId: currentUserId,
                    ),
                    if (i < recent.length - 1)
                      const Divider(
                          height: 1,
                          indent: 18,
                          endIndent: 18,
                          color: Color(0xFFF3F4F6)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeEntryRow extends ConsumerWidget {
  final DailyEntryEntity entry;
  final String?          currentUserId;
  const _HomeEntryRow(
      {required this.entry, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome  = entry.type.toLowerCase() == 'income';
    final title     = entry.description.isEmpty
        ? 'Daily entry'
        : entry.description;
    final initial   = title.trim().substring(0, 1).toUpperCase();
    final amountStr =
        '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(entry.amount)}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDailyEntryActions(context, ref, entry,
          currentUserId: currentUserId),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          // avatar circle
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isIncome ? _kIncBg : _kExpBg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: isIncome ? _kIncome : _kExpense,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // type + partner tags + name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _Tag(
                    label: isIncome ? 'INCOME' : 'EXPENSE',
                    bg: isIncome ? _kIncBg : _kExpBg,
                    fg: isIncome ? _kIncome : _kExpense,
                  ),
                  const SizedBox(width: 6),
                  _Tag(
                    label: entry.creatorName.toUpperCase(),
                    bg: _kCardSub,
                    fg: const Color(0xFF6B7280),
                  ),
                ]),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateFmt.format(entry.createdAt),
                  style: const TextStyle(
                      color: _kTextSub, fontSize: 12),
                ),
              ],
            ),
          ),

          // amount
          Text(
            amountStr,
            style: TextStyle(
              color: isIncome ? _kIncome : _kExpense,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color  bg;
  final Color  fg;
  const _Tag(
      {required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FAB
// ─────────────────────────────────────────────────────────────────────────────

class _AddFAB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyAddScreen()),
        );
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        decoration: BoxDecoration(
          color: _kDark,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: _kDark.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text('Add',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
