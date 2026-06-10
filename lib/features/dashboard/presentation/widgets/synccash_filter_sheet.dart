import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';

class SyncCashFilterPanel extends ConsumerStatefulWidget {
  const SyncCashFilterPanel({super.key});

  @override
  ConsumerState<SyncCashFilterPanel> createState() =>
      _SyncCashFilterPanelState();
}

class _SyncCashFilterPanelState extends ConsumerState<SyncCashFilterPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  String _selectedDateRange = '';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _hidePopover();
    _animationController.dispose();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedDateRange.isNotEmpty) count++;
    if (_nameController.text.isNotEmpty) count++;
    if (_descController.text.isNotEmpty) count++;
    count += _selectedCategories.length;
    return count;
  }

  void _toggleFilterView(BuildContext context) {
    final bool isDesktop = kIsWeb || MediaQuery.of(context).size.width > 768;
    if (isDesktop) {
      if (_overlayEntry == null) {
        _showPopover();
      } else {
        _hidePopover();
      }
    } else {
      _showBottomSheet(context);
    }
  }

  void _showPopover() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    _animationController.forward();
    setState(() {});
  }

  void _hidePopover() {
    if (_overlayEntry != null) {
      _animationController.reverse().then((_) {
        _overlayEntry?.remove();
        _overlayEntry = null;
        if (mounted) setState(() {});
      });
    }
  }

  void _clearAllFilters() {
    setState(() {
      _selectedDateRange = '';
      _nameController.clear();
      _descController.clear();
      _selectedCategories.clear();
    });
    ref.read(selectedCategoryFilterProvider.notifier).setFilter(null);
    ref.read(selectedNameFilterProvider.notifier).setFilter(null);
    ref.read(selectedDescriptionFilterProvider.notifier).setFilter(null);
    ref.read(selectedDateFilterProvider.notifier).setFilter(null);
  }

  void _applyFilters() {
    ref.read(selectedNameFilterProvider.notifier).setFilter(
          _nameController.text.trim().isEmpty
              ? null
              : _nameController.text.trim(),
        );
    ref.read(selectedDescriptionFilterProvider.notifier).setFilter(
          _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
        );
    ref.read(selectedCategoryFilterProvider.notifier).setFilter(
          _selectedCategories.isEmpty ? null : _selectedCategories.first,
        );
    _hidePopover();
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: _hidePopover,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
          Positioned(
            width: 360,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(-250, 52),
              child: ScaleTransition(
                scale: _scaleAnimation,
                alignment: Alignment.topRight,
                child: FadeTransition(
                  opacity: _animationController,
                  child: Material(
                    elevation: 0,
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withOpacity(0.35),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 24,
                            spreadRadius: 0,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: _buildFilterContent(isDesktop: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
        reverseDuration: const Duration(milliseconds: 280),
      )..forward(),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return AnimatedPadding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildFilterContent(
                    isDesktop: false,
                    updateState: setModalState,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _getActiveFilterCount();
    final isOpen = _overlayEntry != null;

    return CompositedTransformTarget(
      link: _layerLink,
      child: _FilterButton(
        isOpen: isOpen,
        activeFilterCount: activeCount,
        onPressed: () => _toggleFilterView(context),
      ),
    );
  }

  Widget _buildFilterContent(
      {required bool isDesktop, StateSetter? updateState}) {
    final localSetState = updateState ?? setState;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Filters',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            if (!isDesktop)
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),

        // ── Date range ────────────────────────────────────────────────────
        _FilterSectionLabel(label: 'Date range', theme: theme),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Today'].map((range) {
            final isSelected = _selectedDateRange == range;
            return _SyncCashChoiceChip(
              label: range,
              isSelected: isSelected,
              onSelected: (selected) {
                localSetState(() {
                  _selectedDateRange = selected ? range : '';
                });
                DateTime? filterDate;
                if (selected && range == 'Today') {
                  filterDate = DateTime.now();
                }
                ref
                    .read(selectedDateFilterProvider.notifier)
                    .setFilter(filterDate);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 18),

        // ── Search fields ─────────────────────────────────────────────────
        _SyncCashTextField(
          controller: _nameController,
          label: 'User / Creator',
          hint: 'e.g. Alex Carter',
          icon: Icons.person_outline_rounded,
          onChanged: (_) => localSetState(() {}),
        ),
        const SizedBox(height: 12),
        _SyncCashTextField(
          controller: _descController,
          label: 'Description / Notes',
          hint: 'e.g. Invoice checkout...',
          icon: Icons.notes_rounded,
          onChanged: (_) => localSetState(() {}),
        ),
        const SizedBox(height: 18),

        // ── Category ──────────────────────────────────────────────────────
        _FilterSectionLabel(label: 'Category', theme: theme),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Retail', 'Wholesale'].map((category) {
            final isSelected = _selectedCategories.contains(category);
            return _SyncCashChoiceChip(
              label: category,
              isSelected: isSelected,
              onSelected: (selected) {
                localSetState(() {
                  if (selected) {
                    _selectedCategories.clear();
                    _selectedCategories.add(category);
                  } else {
                    _selectedCategories.clear();
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // ── Actions ───────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _clearAllFilters();
                  if (!isDesktop) Navigator.pop(context);
                  else localSetState(() {});
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                    width: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () {
                  if (!isDesktop) {
                    _applyFilters();
                    Navigator.pop(context);
                  } else {
                    _applyFilters();
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Apply',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Filter section label ──────────────────────────────────────────────────────

class _FilterSectionLabel extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _FilterSectionLabel({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Filter button ─────────────────────────────────────────────────────────────

class _FilterButton extends StatefulWidget {
  final bool isOpen;
  final int activeFilterCount;
  final VoidCallback onPressed;

  const _FilterButton({
    required this.isOpen,
    required this.activeFilterCount,
    required this.onPressed,
  });

  @override
  State<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<_FilterButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActive = widget.activeFilterCount > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isOpen
                ? theme.colorScheme.primary
                : (_isHovered
                    ? theme.colorScheme.surfaceContainerHigh
                    : theme.colorScheme.surfaceContainer),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isOpen
                  ? Colors.transparent
                  : theme.colorScheme.outlineVariant.withOpacity(0.4),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isHovered ? 0.06 : 0.03),
                blurRadius: _isHovered ? 10 : 4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => RotationTransition(
                  turns: child.key == const ValueKey('close')
                      ? Tween<double>(begin: 0.75, end: 1.0).animate(anim)
                      : Tween<double>(begin: 0.25, end: 1.0).animate(anim),
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: widget.isOpen
                    ? Icon(
                        Icons.close_rounded,
                        key: const ValueKey('close'),
                        color: theme.colorScheme.onPrimary,
                        size: 18,
                      )
                    : Icon(
                        Icons.tune_rounded,
                        key: const ValueKey('tune'),
                        color: theme.colorScheme.onSurface,
                        size: 18,
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                'Filters',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: widget.isOpen
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: hasActive
                    ? Container(
                        key: ValueKey('badge-${widget.activeFilterCount}'),
                        margin: const EdgeInsets.only(left: 7),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: widget.isOpen
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${widget.activeFilterCount}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: widget.isOpen
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Choice chip ───────────────────────────────────────────────────────────────

class _SyncCashChoiceChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final Function(bool) onSelected;

  const _SyncCashChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  State<_SyncCashChoiceChip> createState() => _SyncCashChoiceChipState();
}

class _SyncCashChoiceChipState extends State<_SyncCashChoiceChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        child: ChoiceChip(
          label: Text(widget.label),
          selected: widget.isSelected,
          onSelected: widget.onSelected,
          labelStyle: TextStyle(
            fontSize: 12,
            color: widget.isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight:
                widget.isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
          backgroundColor: _isHovered
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surfaceContainerLow,
          selectedColor:
              theme.colorScheme.primaryContainer.withOpacity(0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: BorderSide(
            color: widget.isSelected
                ? theme.colorScheme.primary.withOpacity(0.6)
                : theme.colorScheme.outlineVariant.withOpacity(0.4),
            width: 0.5,
          ),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
    );
  }
}

// ── Text field ────────────────────────────────────────────────────────────────

class _SyncCashTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _SyncCashTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.45),
            ),
            prefixIcon: Icon(
              icon,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                width: 0.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                width: 0.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withOpacity(0.7),
                width: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}