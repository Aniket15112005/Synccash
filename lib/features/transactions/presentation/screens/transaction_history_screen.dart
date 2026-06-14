// lib/features/transactions/presentation/screens/transaction_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider, currentUserIdProvider;
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/dashboard/presentation/widgets/synccash_filter_sheet.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_list_item.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Date helpers
// ─────────────────────────────────────────────────────────────────────────────

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _kDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _dayLabel(DateTime d) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day   = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${_kDays[d.weekday - 1]}, ${_kMonths[d.month - 1]} ${d.day}';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Filter helpers
// ─────────────────────────────────────────────────────────────────────────────

enum _TypeFilter { all, income, expense }

List<dynamic> _applyFilters(
  List<dynamic> txs,
  _TypeFilter typeFilter,
  String query,
) {
  final q = query.trim().toLowerCase();
  return txs.where((tx) {
    if (typeFilter == _TypeFilter.income  && tx.type != 'income')  return false;
    if (typeFilter == _TypeFilter.expense && tx.type != 'expense') return false;
    if (q.isNotEmpty) {
      final desc = (tx.description as String).toLowerCase();
      final cat  = (tx.category   as String).toLowerCase();
      if (!desc.contains(q) && !cat.contains(q)) return false;
    }
    return true;
  }).toList();
}

double _sumIncome(List<dynamic> txs) => txs
    .where((tx) => tx.type == 'income')
    .fold(0.0, (sum, tx) => sum + (tx.amount as double));

double _sumExpense(List<dynamic> txs) => txs
    .where((tx) => tx.type == 'expense')
    .fold(0.0, (sum, tx) => sum + (tx.amount as double));

String _fmt(double v) => NumberFormat('#,##,##0', 'en_IN').format(v);

// ─────────────────────────────────────────────────────────────────────────────
//  Flat-list items
// ─────────────────────────────────────────────────────────────────────────────

sealed class _ListItem {}

final class _GroupHeader extends _ListItem {
  final String dateLabel;
  final int    count;
  _GroupHeader({required this.dateLabel, required this.count});
}

final class _TxEntry extends _ListItem {
  final dynamic transaction;
  final int     globalIndex;
  _TxEntry({required this.transaction, required this.globalIndex});
}

List<_ListItem> _buildFlatList(List<dynamic> txs) {
  final grouped = <String, List<dynamic>>{};
  for (final tx in txs) {
    final date = (tx.createdAt as DateTime).toLocal();
    grouped.putIfAbsent(_dayKey(date), () => []).add(tx);
  }
  final flat    = <_ListItem>[];
  var globalIdx = 0;
  for (final entry in grouped.entries) {
    final parts = entry.key.split('-');
    final date  = DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]),
    );
    flat.add(_GroupHeader(
      dateLabel: _dayLabel(date),
      count:     entry.value.length,
    ));
    for (final tx in entry.value) {
      flat.add(_TxEntry(transaction: tx, globalIndex: globalIdx++));
    }
  }
  return flat;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen>
    with SingleTickerProviderStateMixin {

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  _TypeFilter _typeFilter  = _TypeFilter.all;
  bool        _showSearch  = false;
  String      _searchQuery = '';

  final TextEditingController _searchCtrl = TextEditingController();

  List<_ListItem>? _cachedFlat;
  Object?          _cacheKey;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _searchCtrl.addListener(() {
      final t = _searchCtrl.text;
      if (t != _searchQuery) setState(() => _searchQuery = t);
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_ListItem> _getFlat(List<dynamic> filtered) {
    final key = Object.hash(
        filtered.length, _typeFilter, _searchQuery,
        filtered.isEmpty ? 0 : filtered.first.hashCode);
    if (key != _cacheKey) {
      _cacheKey   = key;
      _cachedFlat = _buildFlatList(filtered);
    }
    return _cachedFlat!;
  }

  // Tapping the already-active chip resets to All
  void _onChipTap(_TypeFilter tapped) {
    HapticFeedback.selectionClick();
    setState(() {
      if (tapped == _TypeFilter.all) {
        _typeFilter = _TypeFilter.all;
      } else {
        _typeFilter = (_typeFilter == tapped) ? _TypeFilter.all : tapped;
      }
    });
  }

  void _clearFilters() {
    HapticFeedback.lightImpact();
    setState(() {
      _typeFilter  = _TypeFilter.all;
      _searchQuery = '';
      _searchCtrl.clear();
      _showSearch  = false;
    });
  }

  bool get _hasActiveFilter =>
      _typeFilter != _TypeFilter.all || _searchQuery.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cashbookId    = ref.watch(currentCashbookIdProvider);
    final currentUserId = ref.watch(currentUserIdProvider.select((id) => id));

    final txAsync = cashbookId == null
        ? const AsyncValue<List<dynamic>>.data([])
       : ref.watch(allFilteredTransactionsProvider(cashbookId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            _HistoryAppBar(
              showSearch:      _showSearch,
              hasActiveFilter: _hasActiveFilter,
              searchCtrl:      _searchCtrl,
              onBack: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              onToggleSearch: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchCtrl.clear();
                    _searchQuery = '';
                  }
                });
              },
              onClearAll: _hasActiveFilter ? _clearFilters : null,
            ),

            txAsync.when(
              data: (allTxs) {
                final filtered =
                    _applyFilters(allTxs, _typeFilter, _searchQuery);
                final flatList = _getFlat(filtered);

                return SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _FilterChipsRow(
                        selected:  _typeFilter,
                        onChipTap: _onChipTap,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SummaryStrip(
                        total:   filtered.length,
                        income:  _sumIncome(filtered),
                        expense: _sumExpense(filtered),
                      ),
                    ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _hasActiveFilter
                            ? _NoResultsState(onClear: _clearFilters)
                            : const _EmptyState(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                        sliver: SliverList.builder(
                          itemCount: flatList.length,
                          addAutomaticKeepAlives: false,
                          itemBuilder: (context, i) {
                            final item = flatList[i];
                            if (item is _GroupHeader) {
                              return _DateSectionHeader(
                                label: item.dateLabel,
                                count: item.count,
                              );
                            }
                            final entry = item as _TxEntry;
                            return RepaintBoundary(
                              child: _TxRow(
                                key:           ValueKey(
                                    entry.transaction.transactionId),
                                transaction:   entry.transaction,
                                currentUserId: currentUserId,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: _LoadingState(),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(message: e.toString()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  App bar
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryAppBar extends StatelessWidget {
  final bool                  showSearch;
  final bool                  hasActiveFilter;
  final TextEditingController searchCtrl;
  final VoidCallback          onBack;
  final VoidCallback          onToggleSearch;
  final VoidCallback?         onClearAll;

  const _HistoryAppBar({
    required this.showSearch,
    required this.hasActiveFilter,
    required this.searchCtrl,
    required this.onBack,
    required this.onToggleSearch,
    this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor:        AppColors.background,
      surfaceTintColor:       Colors.transparent,
      pinned:                 true,
      elevation:              0,
      scrolledUnderElevation: 0,
      expandedHeight:         showSearch ? 110 : 60,
      collapsedHeight:        60,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Center(
          child: GestureDetector(
            onTap: onBack,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(11),
                border:       Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size:  15,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
      leadingWidth: 62,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: showSearch
            ? const SizedBox.shrink()
            : const Text(
                'All Transactions',
                key: ValueKey('title'),
                style: TextStyle(
                  color:         AppColors.textPrimary,
                  fontSize:      18,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
      ),
      actions: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: (!showSearch && hasActiveFilter)
              ? GestureDetector(
                  key:   const ValueKey('clear'),
                  onTap: onClearAll,
                  child: Container(
                    margin:  const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color:        const Color(0x1AF87171),
                      borderRadius: BorderRadius.circular(9),
                      border:       Border.all(color: const Color(0x3DF87171)),
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                        color:      AppColors.expense,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-clear')),
        ),
        GestureDetector(
          onTap: onToggleSearch,
          child: AnimatedContainer(
            duration:     const Duration(milliseconds: 160),
            width:        38,
            height:       38,
            margin:       const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: showSearch
                  ? const Color(0x26FFFFFF)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: showSearch
                    ? const Color(0x40FFFFFF)
                    : AppColors.border,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  showSearch ? Icons.close_rounded : Icons.search_rounded,
                  size:  17,
                  color: showSearch
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                if (!showSearch && hasActiveFilter)
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: showSearch
            ? Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: _SearchBar(controller: searchCtrl),
                ),
              )
            : null,
        collapseMode: CollapseMode.pin,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: AppColors.border),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Search bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border:       Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 13),
          child: Icon(Icons.search_rounded,
              size: 17, color: AppColors.textSecondary),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus:  true,
            style: const TextStyle(
              color:      AppColors.textPrimary,
              fontSize:   15,
              fontWeight: FontWeight.w500,
            ),
            decoration: const InputDecoration(
              hintText: 'Search description or category…',
              hintStyle: TextStyle(
                color:    AppColors.textMuted,
                fontSize: 14,
              ),
              border:         InputBorder.none,
              isDense:        true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ]),
    )
        .animate()
        .fadeIn(duration: 160.ms)
        .slideY(begin: -0.05, end: 0, curve: Curves.easeOut, duration: 160.ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Filter chips row
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  final _TypeFilter               selected;
  final ValueChanged<_TypeFilter> onChipTap;

  const _FilterChipsRow({
    required this.selected,
    required this.onChipTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(children: [
        const SyncCashFilterPanel(),
        const SizedBox(width: 10),
        // Segmented pill group
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(13),
            border:       Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _PillChip(
              label: 'All',
              active: selected == _TypeFilter.all,
              onTap:  () => onChipTap(_TypeFilter.all),
            ),
            _PillChip(
              label:       'Income',
              active:      selected == _TypeFilter.income,
              activeColor: AppColors.income,
              onTap:       () => onChipTap(_TypeFilter.income),
            ),
            _PillChip(
              label:       'Expense',
              active:      selected == _TypeFilter.expense,
              activeColor: AppColors.expense,
              onTap:       () => onChipTap(_TypeFilter.expense),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PillChip extends StatelessWidget {
  final String       label;
  final bool         active;
  final Color?       activeColor;
  final VoidCallback onTap;

  const _PillChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.textPrimary;
    return GestureDetector(
      onTap:    onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve:    Curves.easeInOut,
        padding:  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.35) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize:      14,
            fontWeight:    active ? FontWeight.w700 : FontWeight.w500,
            color:         active ? color : AppColors.textSecondary,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Summary strip
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int    total;
  final double income;
  final double expense;

  const _SummaryStrip({
    required this.total,
    required this.income,
    required this.expense,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          _SummaryCell(
            label:      'ENTRIES',
            value:      '$total',
            valueColor: AppColors.textPrimary,
            align:      CrossAxisAlignment.start,
            leftPad:    18,
          ),
          const VerticalDivider(
              width: 1, thickness: 0.5,
              color: AppColors.border, indent: 12, endIndent: 12),
          _SummaryCell(
            label:      'INCOME',
            value:      '₹${_fmt(income)}',
            valueColor: AppColors.income,
            align:      CrossAxisAlignment.center,
          ),
          const VerticalDivider(
              width: 1, thickness: 0.5,
              color: AppColors.border, indent: 12, endIndent: 12),
          _SummaryCell(
            label:      'EXPENSE',
            value:      '₹${_fmt(expense)}',
            valueColor: AppColors.expense,
            align:      CrossAxisAlignment.end,
            rightPad:   18,
          ),
        ]),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String             label;
  final String             value;
  final Color              valueColor;
  final CrossAxisAlignment align;
  final double             leftPad;
  final double             rightPad;

  const _SummaryCell({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.align,
    this.leftPad  = 0,
    this.rightPad = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(leftPad, 16, rightPad, 16),
        child: Column(
          crossAxisAlignment: align,
          children: [
            Text(label,
                style: const TextStyle(
                  fontSize:      10,
                  fontWeight:    FontWeight.w700,
                  color:         AppColors.textMuted,
                  letterSpacing: 1.0,
                )),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                  fontSize:      17,
                  fontWeight:    FontWeight.w800,
                  color:         valueColor,
                  letterSpacing: -0.5,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Transaction row wrapper  (larger vertical rhythm)
// ─────────────────────────────────────────────────────────────────────────────

class _TxRow extends StatelessWidget {
  final dynamic  transaction;
  final String?  currentUserId;

  const _TxRow({
    super.key,
    required this.transaction,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: AppColors.border),
      ),
      child: TransactionListItem(
        transaction:   transaction,
        currentUserId: currentUserId,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Date section header  (larger)
// ─────────────────────────────────────────────────────────────────────────────

class _DateSectionHeader extends StatelessWidget {
  final String label;
  final int    count;

  const _DateSectionHeader({
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 3, height: 16,
          decoration: BoxDecoration(
            color:        AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize:      14,
            fontWeight:    FontWeight.w700,
            color:         AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color:        AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize:   11,
              fontWeight: FontWeight.w700,
              color:      AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Divider(
              height: 1, thickness: 0.5, color: AppColors.border),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  No results
// ─────────────────────────────────────────────────────────────────────────────

class _NoResultsState extends StatelessWidget {
  final VoidCallback onClear;
  const _NoResultsState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size:  28,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No matches found',
              style: TextStyle(
                fontSize:      17,
                fontWeight:    FontWeight.w700,
                color:         AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Try a different keyword or remove a filter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color:    AppColors.textSecondary,
                height:   1.5,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color:        AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'Clear filters',
                  style: TextStyle(
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                    color:      AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ).animate().fadeIn(delay: 80.ms, duration: 260.ms),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading skeleton
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            decoration: BoxDecoration(
              color:        AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: AppColors.border),
            ),
          ).animate().shimmer(
              duration: 1000.ms, color: Colors.white.withValues(alpha: 0.03)),
          const SizedBox(height: 12),
          Container(
            height: 70,
            decoration: BoxDecoration(
              color:        AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: AppColors.border),
            ),
          ).animate().shimmer(
              duration: 1100.ms, color: Colors.white.withValues(alpha: 0.03)),
          const SizedBox(height: 24),
          ...List.generate(6, (i) => _SkeletonRow(index: i)),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final int index;
  const _SkeletonRow({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      height:  76,
      margin:  const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color:        AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:  MainAxisAlignment.center,
            children: [
              Container(
                height: 11,
                decoration: BoxDecoration(
                  color:        AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 7),
              Container(
                height: 9,
                width:  80,
                decoration: BoxDecoration(
                  color:        AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          height: 13,
          width:  58,
          decoration: BoxDecoration(
            color:        AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ]),
    )
        .animate(delay: Duration(milliseconds: index * 40))
        .fadeIn(duration: 200.ms)
        .then()
        .shimmer(
          duration: 1000.ms,
          color:    Colors.white.withValues(alpha: 0.03),
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border:       Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size:  30,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'No transactions yet',
              style: TextStyle(
                fontSize:      17,
                fontWeight:    FontWeight.w700,
                color:         AppColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Entries you log will be grouped\nby date and shown here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color:    AppColors.textSecondary,
                height:   1.55,
              ),
            ),
          ],
        )
            .animate()
            .fadeIn(delay: 80.ms, duration: 300.ms)
            .slideY(begin: 0.04, end: 0, curve: Curves.easeOut),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Error state
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                color:        const Color(0x14F87171),
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(color: const Color(0x2EF87171)),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size:  26,
                color: AppColors.expense,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Could not load transactions',
              style: TextStyle(
                fontSize:      16,
                fontWeight:    FontWeight.w700,
                color:         AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pull down to try again.',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ).animate().fadeIn(duration: 260.ms),
      ),
    );
  }
}
