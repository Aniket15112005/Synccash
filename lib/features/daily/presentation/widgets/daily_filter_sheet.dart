// lib/features/daily/presentation/widgets/daily_filter_sheet.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';

const _kAccent      = Color(0xFF8B5CF6);
const _kText        = Color(0xFF1C1C1A); // warm charcoal
const _kTextSub     = Color(0xFF8A8882); // warm muted gray
const _kCard        = Color(0xFFF5F4F1); // frosted off-white
const _kCardBorder  = Color(0xFFF0EFED);
const _kSheetBg     = Color(0xFFF2F1EE); // sheet slightly warmer than bg

class DailyFilterPanel extends ConsumerWidget {
  const DailyFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFilter = ref.watch(dailyDateFilterProvider);
    final nameFilter = ref.watch(dailyNameFilterProvider);
    final descFilter = ref.watch(dailyDescriptionFilterProvider);
    final typeFilter = ref.watch(dailyTypeFilterProvider);

    final activeCount =
        (dateFilter != null ? 1 : 0) +
        (nameFilter != null && nameFilter.isNotEmpty ? 1 : 0) +
        (descFilter != null && descFilter.isNotEmpty ? 1 : 0) +
        (typeFilter != null ? 1 : 0);

    return _FilterIconButton(
      activeCount: activeCount,
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _DailyFilterSheet(),
        );
      },
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  final int          activeCount;
  final VoidCallback onTap;
  const _FilterIconButton(
      {required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasActive = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasActive ? _kAccent : _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasActive ? Colors.transparent : _kCardBorder,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: hasActive
                  ? _kAccent.withValues(alpha: 0.22)
                  : const Color(0xFF000000).withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: 18,
                color: hasActive ? Colors.white : _kTextSub),
            if (hasActive) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _kAccent),
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

class _DailyFilterSheet extends ConsumerStatefulWidget {
  const _DailyFilterSheet();

  @override
  ConsumerState<_DailyFilterSheet> createState() =>
      _DailyFilterSheetState();
}

class _DailyFilterSheetState extends ConsumerState<_DailyFilterSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Timer? _debounce;
  String _selectedDateLabel = '';

  @override
  void initState() {
    super.initState();
    final name = ref.read(dailyNameFilterProvider);
    final desc = ref.read(dailyDescriptionFilterProvider);
    if (name != null) _nameCtrl.text = name;
    if (desc != null) _descCtrl.text = desc;
    _selectedDateLabel =
        _labelFromFilter(ref.read(dailyDateFilterProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _labelFromFilter(DailyDateFilter? f) {
    if (f == null) return '';
    final s   = f.startDate;
    final e   = f.endDate;
    if (s == null || e == null) return '';
    final now = DateTime.now();
    final ws  = now.subtract(Duration(days: now.weekday - 1));
    if (s == DateTime(now.year, now.month, now.day)) return 'Today';
    if (s == DateTime(ws.year, ws.month, ws.day)) return 'This Week';
    if (s == DateTime(now.year, now.month, 1)) return 'This Month';
    if (s == DateTime(now.year, 1, 1)) return 'This Year';
    if (s.year == e.year && s.month == e.month && s.day == e.day) {
      return 'Single Date';
    }
    return 'Custom';
  }

  void _debounced(VoidCallback fn) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), fn);
  }

  void _onDateChip(String label, bool selected) {
    if (!selected) {
      setState(() => _selectedDateLabel = '');
      ref.read(dailyDateFilterProvider.notifier).setFilter(null);
      return;
    }
    if (label == 'Single Date') { _pickSingleDate(); return; }
    if (label == 'Custom')      { _pickDateRange();  return; }

    setState(() => _selectedDateLabel = label);
    final now = DateTime.now();
    final ws  = now.subtract(Duration(days: now.weekday - 1));
    final filterMap = {
      'Today':      DailyDateFilter(startDate: DateTime(now.year, now.month, now.day), endDate: now),
      'This Week':  DailyDateFilter(startDate: DateTime(ws.year, ws.month, ws.day), endDate: now),
      'This Month': DailyDateFilter(startDate: DateTime(now.year, now.month, 1), endDate: now),
      'This Year':  DailyDateFilter(startDate: DateTime(now.year, 1, 1), endDate: now),
    };
    final f = filterMap[label];
    if (f != null) ref.read(dailyDateFilterProvider.notifier).setFilter(f);
  }

  Future<void> _pickSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate:
          ref.read(dailyDateFilterProvider)?.startDate ?? DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedDateLabel = 'Single Date');
    ref.read(dailyDateFilterProvider.notifier).setFilter(DailyDateFilter(
          startDate: DateTime(picked.year, picked.month, picked.day),
          endDate:
              DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
        ));
  }

  Future<void> _pickDateRange() async {
    final cur    = ref.read(dailyDateFilterProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange:
          (cur?.startDate != null && cur?.endDate != null)
              ? DateTimeRange(start: cur!.startDate!, end: cur.endDate!)
              : null,
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedDateLabel = 'Custom');
    ref.read(dailyDateFilterProvider.notifier).setFilter(DailyDateFilter(
          startDate: picked.start,
          endDate: DateTime(picked.end.year, picked.end.month,
              picked.end.day, 23, 59, 59),
        ));
  }

  void _onTypeChip(String type, bool selected) {
    HapticFeedback.selectionClick();
    setState(() {});
    _debounced(() => ref
        .read(dailyTypeFilterProvider.notifier)
        .setFilter(selected ? type : null));
  }

  void _clearAll() {
    _debounce?.cancel();
    _nameCtrl.clear();
    _descCtrl.clear();
    setState(() => _selectedDateLabel = '');
    ref.read(dailyDateFilterProvider.notifier).setFilter(null);
    ref.read(dailyNameFilterProvider.notifier).setFilter(null);
    ref.read(dailyDescriptionFilterProvider.notifier).setFilter(null);
    ref.read(dailyTypeFilterProvider.notifier).setFilter(null);
  }

  void _apply() {
    _debounce?.cancel();
    ref.read(dailyNameFilterProvider.notifier).setFilter(
        _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim());
    ref.read(dailyDescriptionFilterProvider.notifier).setFilter(
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final typeFilter = ref.watch(dailyTypeFilterProvider);
    final mq         = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: _kSheetBg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.10),
              blurRadius: 40,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // handle
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF000000).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filter Daily Entries',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.4,
                          color: _kText)),
                  TextButton(
                    onPressed: _clearAll,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear all',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const _Label('DATE RANGE'),
            const SizedBox(height: 10),
            _HChipRow(
              chips: const [
                'Today', 'This Week', 'This Month',
                'This Year', 'Single Date', 'Custom'
              ],
              selected: _selectedDateLabel,
              onTap: (label) =>
                  _onDateChip(label, _selectedDateLabel != label),
            ),
            const SizedBox(height: 20),

            const _Label('TYPE'),
            const SizedBox(height: 10),
            _HChipRow(
              chips: const ['income', 'expense'],
              displayLabels: const ['Income', 'Expense'],
              selected: typeFilter ?? '',
              onTap: (t) => _onTypeChip(t, typeFilter != t),
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _Field(
                    ctrl: _nameCtrl,
                    hint: 'Search by creator',
                    icon: Icons.person_outline_rounded,
                    onChanged: (v) => _debounced(() => ref
                        .read(dailyNameFilterProvider.notifier)
                        .setFilter(v.trim().isEmpty ? null : v.trim())),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    ctrl: _descCtrl,
                    hint: 'Search by description',
                    icon: Icons.notes_rounded,
                    onChanged: (v) => _debounced(() => ref
                        .read(dailyDescriptionFilterProvider.notifier)
                        .setFilter(v.trim().isEmpty ? null : v.trim())),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(
                  color: _kTextSub,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  fontSize: 10)),
        ),
      );
}

class _HChipRow extends StatelessWidget {
  final List<String>  chips;
  final List<String>? displayLabels;
  final String        selected;
  final ValueChanged<String> onTap;
  const _HChipRow({
    required this.chips,
    required this.selected,
    required this.onTap,
    this.displayLabels,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: chips.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Chip(
              label: displayLabels != null ? displayLabels![i] : chips[i],
              isSelected: selected == chips[i],
              onTap: () => onTap(chips[i]),
            ),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool   isSelected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.isSelected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? _kAccent : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.transparent : _kCardBorder,
            width: 1,
          ),
          boxShadow: [
            if (!isSelected)
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : _kTextSub,
            )),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String     hint;
  final IconData   icon;
  final ValueChanged<String> onChanged;
  const _Field({
    required this.ctrl,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      style: const TextStyle(color: _kText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: _kTextSub.withValues(alpha: 0.7), fontSize: 14),
        prefixIcon:
            Icon(icon, size: 18, color: _kTextSub.withValues(alpha: 0.7)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: _kCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kCardBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kCardBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kAccent, width: 1.5),
        ),
      ),
    );
  }
}
