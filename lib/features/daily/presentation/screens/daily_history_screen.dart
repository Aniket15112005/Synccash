// lib/features/daily/presentation/screens/daily_history_screen.dart
//
// "View all" screen for Daily entries — mirrors transaction_history_screen.dart's
// structure (type chips, summary strip, grouped-by-day list, toggleable inline
// search bar) but reads only from dailyFilteredEntriesProvider, never from any
// transaction provider. The search box here filters purely client-side by
// creator name / description — it is local UI state, not wired to the shared
// transaction search/filter providers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';
import 'package:synccash/features/daily/presentation/widgets/daily_filter_sheet.dart';
import 'package:synccash/features/daily/presentation/widgets/daily_list_item.dart';

const _kDailyAccent = Color(0xFF8B5CF6);
const _kDailyBg = Color(0xFF111113);

enum _TypeFilter { all, income, expense }

class DailyHistoryScreen extends ConsumerStatefulWidget {
  const DailyHistoryScreen({super.key});

  @override
  ConsumerState<DailyHistoryScreen> createState() => _DailyHistoryScreenState();
}

class _DailyHistoryScreenState extends ConsumerState<DailyHistoryScreen> {
  _TypeFilter _typeFilter = _TypeFilter.all;
  bool _showSearch = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final t = _searchCtrl.text;
      if (t != _searchQuery) setState(() => _searchQuery = t);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    HapticFeedback.lightImpact();
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchCtrl.clear();
        _searchQuery = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    if (cashbookId == null) {
      return const Scaffold(
        backgroundColor: _kDailyBg,
        body: Center(
          child: Text('No active cashbook', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final asyncEntries = ref.watch(dailyFilteredEntriesProvider(cashbookId));

    return Scaffold(
      backgroundColor: _kDailyBg,
      appBar: AppBar(
        backgroundColor: _kDailyBg,
        elevation: 0,
        toolbarHeight: _showSearch ? 0 : kToolbarHeight,
        title: const Text('Daily History',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DailyFilterPanel(),
          ),
          GestureDetector(
            onTap: _toggleSearch,
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: _showSearch
                    ? _kDailyAccent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _showSearch
                      ? _kDailyAccent.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Icon(
                _showSearch ? Icons.close_rounded : Icons.search_rounded,
                size: 17,
                color: _showSearch ? _kDailyAccent : Colors.white70,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_showSearch ? 66 : 0),
          child: _showSearch
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _SearchField(controller: _searchCtrl),
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: asyncEntries.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: _kDailyAccent)),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.white54)),
        ),
        data: (entries) {
          final query = _searchQuery.toLowerCase().trim();
          final filtered = entries.where((e) {
            switch (_typeFilter) {
              case _TypeFilter.income:
                if (e.type.toLowerCase() != 'income') return false;
                break;
              case _TypeFilter.expense:
                if (e.type.toLowerCase() != 'expense') return false;
                break;
              case _TypeFilter.all:
                break;
            }
            if (query.isEmpty) return true;
            return e.creatorName.toLowerCase().contains(query) ||
                e.description.toLowerCase().contains(query);
          }).toList();

          double income = 0;
          double expense = 0;
          for (final e in filtered) {
            if (e.type.toLowerCase() == 'income') {
              income += e.amount;
            } else {
              expense += e.amount;
            }
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    _TypeChip(
                      label: 'All',
                      selected: _typeFilter == _TypeFilter.all,
                      onTap: () => setState(() => _typeFilter = _TypeFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _TypeChip(
                      label: 'Income',
                      selected: _typeFilter == _TypeFilter.income,
                      color: const Color(0xFF5CB87A),
                      onTap: () =>
                          setState(() => _typeFilter = _TypeFilter.income),
                    ),
                    const SizedBox(width: 8),
                    _TypeChip(
                      label: 'Expense',
                      selected: _typeFilter == _TypeFilter.expense,
                      color: const Color(0xFFD96C6C),
                      onTap: () =>
                          setState(() => _typeFilter = _TypeFilter.expense),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SummaryStrip(
                  count: filtered.length, income: income, expense: expense),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          query.isNotEmpty || _typeFilter != _TypeFilter.all
                              ? 'No matching entries'
                              : 'No entries yet',
                          style: const TextStyle(color: Colors.white38),
                        ),
                      )
                    : _buildGroupedList(filtered, currentUserId),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupedList(List<DailyEntryEntity> entries, String? currentUserId) {
    final dayFmt = DateFormat('EEEE, dd MMM yyyy');
    final groups = <String, List<DailyEntryEntity>>{};
    for (final e in entries) {
      final key = dayFmt.format(e.createdAt);
      groups.putIfAbsent(key, () => []).add(e);
    }

    final items = <Widget>[];
    groups.forEach((day, dayEntries) {
      items.add(_GroupHeader(day));
      for (var i = 0; i < dayEntries.length; i++) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DailyListItem(
            entry: dayEntries[i],
            currentUserId: currentUserId,
            showTimeline: true,
            isLastInGroup: i == dayEntries.length - 1,
          ),
        ));
      }
    });

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: items,
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 13),
          child: Icon(Icons.search_rounded, size: 17, color: Colors.white54),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Search by name or description…',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 14,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ]),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? _kDailyAccent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? activeColor : Colors.white54,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final int count;
  final double income;
  final double expense;
  const _SummaryStrip(
      {required this.count, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SummaryItem(label: 'Entries', value: '$count'),
            _SummaryItem(
                label: 'Income',
                value: '₹${CurrencyFormatter.format(income)}',
                color: const Color(0xFF5CB87A)),
            _SummaryItem(
                label: 'Expense',
                value: '₹${CurrencyFormatter.format(expense)}',
                color: const Color(0xFFD96C6C)),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10.5)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            )),
      ],
    );
  }
}
