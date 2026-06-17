import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';

class SyncCashFilterPanel extends ConsumerWidget {
  const SyncCashFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFilter = ref.watch(selectedDateFilterProvider);
    final nameFilter = ref.watch(selectedNameFilterProvider);
    final descFilter = ref.watch(selectedDescriptionFilterProvider);
    final categoryFilter = ref.watch(selectedCategoryFilterProvider);

    final activeCount = (dateFilter != null ? 1 : 0) +
        (nameFilter != null && nameFilter.isNotEmpty ? 1 : 0) +
        (descFilter != null && descFilter.isNotEmpty ? 1 : 0) +
        (categoryFilter != null ? 1 : 0);

    return _FilterIconButton(
      activeCount: activeCount,
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _FilterSheet(),
        );
      },
    );
  }
}

// ── Icon button with active badge ─────────────────────────────────────────────

class _FilterIconButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  const _FilterIconButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActive = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
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
            Icon(
              Icons.tune_rounded,
              size: 18,
              color: hasActive
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
            if (hasActive) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onPrimary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$activeCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet — self-contained, never causes dashboard rebuilds ─────────────

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Timer? _debounce;
  String _selectedDateLabel = '';

  @override
  void initState() {
    super.initState();
    final name = ref.read(selectedNameFilterProvider);
    final desc = ref.read(selectedDescriptionFilterProvider);
    if (name != null) _nameCtrl.text = name;
    if (desc != null) _descCtrl.text = desc;
    _selectedDateLabel = _labelFromFilter(ref.read(selectedDateFilterProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _labelFromFilter(TransactionDateFilter? f) {
    if (f == null) return '';
    final s = f.startDate;
    final e = f.endDate;
    if (s == null || e == null) return '';
    final now = DateTime.now();
    final ws = now.subtract(Duration(days: now.weekday - 1));
    if (s == DateTime(now.year, now.month, now.day)) return 'Today';
    if (s == DateTime(ws.year, ws.month, ws.day)) return 'This Week';
    if (s == DateTime(now.year, now.month, 1)) return 'This Month';
    if (s == DateTime(now.year, 1, 1)) return 'This Year';
    if (s.year == e.year && s.month == e.month && s.day == e.day) return 'Single Date';
    return 'Custom';
  }

  void _debounced(VoidCallback fn) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), fn);
  }

  void _onDateChip(String label, bool selected) {
    if (!selected) {
      setState(() => _selectedDateLabel = '');
      ref.read(selectedDateFilterProvider.notifier).setFilter(null);
      return;
    }
    if (label == 'Single Date') { _pickSingleDate(); return; }
    if (label == 'Custom') { _pickDateRange(); return; }

    setState(() => _selectedDateLabel = label);
    final now = DateTime.now();
    final ws = now.subtract(Duration(days: now.weekday - 1));
    final filterMap = {
      'Today': TransactionDateFilter(
        startDate: DateTime(now.year, now.month, now.day), endDate: now),
      'This Week': TransactionDateFilter(
        startDate: DateTime(ws.year, ws.month, ws.day), endDate: now),
      'This Month': TransactionDateFilter(
        startDate: DateTime(now.year, now.month, 1), endDate: now),
      'This Year': TransactionDateFilter(
        startDate: DateTime(now.year, 1, 1), endDate: now),
    };
    final f = filterMap[label];
    if (f != null) ref.read(selectedDateFilterProvider.notifier).setFilter(f);
  }

  Future<void> _pickSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: ref.read(selectedDateFilterProvider)?.startDate ?? DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedDateLabel = 'Single Date');
    ref.read(selectedDateFilterProvider.notifier).setFilter(TransactionDateFilter(
      startDate: DateTime(picked.year, picked.month, picked.day),
      endDate: DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
    ));
  }

  Future<void> _pickDateRange() async {
    final cur = ref.read(selectedDateFilterProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: (cur?.startDate != null && cur?.endDate != null)
          ? DateTimeRange(start: cur!.startDate!, end: cur.endDate!)
          : null,
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedDateLabel = 'Custom');
    ref.read(selectedDateFilterProvider.notifier).setFilter(TransactionDateFilter(
      startDate: picked.start,
      endDate: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
    ));
  }

  void _onCategoryChip(String cat, bool selected) {
    HapticFeedback.selectionClick();
    setState(() {});
    _debounced(() => ref
        .read(selectedCategoryFilterProvider.notifier)
        .setFilter(selected ? cat : null));
  }

  void _clearAll() {
    _debounce?.cancel();
    _nameCtrl.clear();
    _descCtrl.clear();
    setState(() => _selectedDateLabel = '');
    ref.read(selectedDateFilterProvider.notifier).setFilter(null);
    ref.read(selectedNameFilterProvider.notifier).setFilter(null);
    ref.read(selectedDescriptionFilterProvider.notifier).setFilter(null);
    ref.read(selectedCategoryFilterProvider.notifier).setFilter(null);
  }

  void _apply() {
    _debounce?.cancel();
    ref.read(selectedNameFilterProvider.notifier).setFilter(
        _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim());
    ref.read(selectedDescriptionFilterProvider.notifier).setFilter(
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryFilter = ref.watch(selectedCategoryFilterProvider);
    final mq = MediaQuery.of(context);

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
            // ── Handle ──────────────────────────────────────────────────
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

            // ── Title + Clear all ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filter Transactions',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  TextButton(
                    onPressed: _clearAll,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear all', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Date range ────────────────────────────────────────────────
            _Label('DATE RANGE', theme),
            const SizedBox(height: 10),
            _HChipRow(
              chips: const ['Today', 'This Week', 'This Month', 'This Year', 'Single Date', 'Custom'],
              selected: _selectedDateLabel,
              onTap: (label) => _onDateChip(label, _selectedDateLabel != label),
            ),

            const SizedBox(height: 20),

            // ── Category ──────────────────────────────────────────────────
            _Label('CATEGORY', theme),
            const SizedBox(height: 10),
            _HChipRow(
              chips: const ['Retail', 'Wholesale', 'Bank', 'UPI'],
              selected: categoryFilter ?? '',
              onTap: (cat) => _onCategoryChip(cat, categoryFilter != cat),
            ),

            const SizedBox(height: 20),

            // ── Search fields ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _Field(
                    ctrl: _nameCtrl,
                    hint: 'Search by creator',
                    icon: Icons.person_outline_rounded,
                    onChanged: (v) => _debounced(() =>
                        ref.read(selectedNameFilterProvider.notifier).setFilter(
                            v.trim().isEmpty ? null : v.trim())),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    ctrl: _descCtrl,
                    hint: 'Search by description',
                    icon: Icons.notes_rounded,
                    onChanged: (v) => _debounced(() =>
                        ref.read(selectedDescriptionFilterProvider.notifier).setFilter(
                            v.trim().isEmpty ? null : v.trim())),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Apply button ──────────────────────────────────────────────
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
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Micro widgets ─────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  final ThemeData theme;
  const _Label(this.text, this.theme);

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

class _HChipRow extends StatelessWidget {
  final List<String> chips;
  final String selected;
  final ValueChanged<String> onTap;
  const _HChipRow({required this.chips, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: chips.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Chip(
              label: chips[i],
              isSelected: selected == chips[i],
              onTap: () => onTap(chips[i]),
            ),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.isSelected, required this.onTap});

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

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;
  const _Field({required this.ctrl, required this.hint, required this.icon, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
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
              color: theme.colorScheme.primary.withValues(alpha: 0.7), width: 1.2),
        ),
      ),
    );
  }
}