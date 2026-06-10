import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';

/// ---------------------------------------------------------------------------
/// SyncCash Premium Filter Component
/// ---------------------------------------------------------------------------

class SyncCashFilterPanel extends ConsumerStatefulWidget {
  const SyncCashFilterPanel({
    super.key,
  });

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

  // Local State representing the selected filters
  String _selectedDateRange = '';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
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
          // Dismiss tap-catcher background
          GestureDetector(
            onTap: _hidePopover,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
          Positioned(
            width: 380,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(-250, 70),
              child: ScaleTransition(
                scale: _scaleAnimation,
                alignment: Alignment.bottomRight,
                child: FadeTransition(
                  opacity: _animationController,
                  child: Material(
                    elevation: 12,
                    shadowColor: Colors.black.withAlpha(26),
                    borderRadius: BorderRadius.circular(24),
                    color: Theme.of(context).colorScheme.surface,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withAlpha(102),
                        ),
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
        duration: const Duration(milliseconds: 400),
        reverseDuration: const Duration(milliseconds: 300),
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
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withAlpha(102),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
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
      child: _AnimatedFilterFAB(
        isOpen: isOpen,
        activeFilterCount: activeCount,
        onPressed: () => _toggleFilterView(context),
      ),
    );
  }

  /// Centralized Filter Content layout used for both Mobile & Desktop paradigms
  Widget _buildFilterContent(
      {required bool isDesktop, StateSetter? updateState}) {
    final localSetState = updateState ?? setState;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Filters',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            if (!isDesktop)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              )
          ],
        ),
        const Divider(height: 24, thickness: 0.5),

        // Date Presets Section
        Text('Date Range',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              ['Today'].map((range) {
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
        const SizedBox(height: 16),

        // Search Inputs
        _SyncCashTextField(
          controller: _nameController,
          label: 'Filter by User/Creator',
          hint: 'e.g., Alex Carter',
          icon: Icons.person_outline_rounded,
          onChanged: (_) => localSetState(() {}),
        ),
        const SizedBox(height: 12),
        _SyncCashTextField(
          controller: _descController,
          label: 'Filter by Description/Notes',
          hint: 'e.g., Invoice checkout...',
          icon: Icons.notes_rounded,
          onChanged: (_) => localSetState(() {}),
        ),
        const SizedBox(height: 16),

        // Categories Section
        Text('Category',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Retail', 'Wholesale'].map((category) {
            final isSelected = _selectedCategories.contains(category);
            return FilterChip(
              label: Text(category),
              selected: isSelected,
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              showCheckmark: false,
              selectedColor: theme.colorScheme.primaryContainer.withAlpha(153),
              side: BorderSide(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: 1,
              ),
            );
          }).toList(),
        ),

        const Divider(height: 32, thickness: 0.5),

        // Action Buttons Row
        Row(
          children: [
            TextButton(
              onPressed: () {
                _clearAllFilters();
                if (!isDesktop) {
                  Navigator.pop(context);
                } else {
                  localSetState(() {});
                }
              },
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Clear All'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                if (!isDesktop) {
                  _applyFilters();
                  Navigator.pop(context);
                } else {
                  _applyFilters();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Apply Filters',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        )
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Custom Premium FAB Layout with Micro-Interactions
/// ---------------------------------------------------------------------------
class _AnimatedFilterFAB extends StatefulWidget {
  final bool isOpen;
  final int activeFilterCount;
  final VoidCallback onPressed;

  const _AnimatedFilterFAB({
    required this.isOpen,
    required this.activeFilterCount,
    required this.onPressed,
  });

  @override
  State<_AnimatedFilterFAB> createState() => _AnimatedFilterFABState();
}

class _AnimatedFilterFABState extends State<_AnimatedFilterFAB> {
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: widget.isOpen
                ? theme.colorScheme.primary
                : (_isHovered
                    ? theme.colorScheme.surfaceContainerHigh
                    : theme.colorScheme.surfaceContainer),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isOpen
                  ? Colors.transparent
                  : theme.colorScheme.outlineVariant.withAlpha(128),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(
                    ((_isHovered || widget.isOpen ? 0.12 : 0.05) * 255)
                        .round()),
                blurRadius: _isHovered ? 12 : 6,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dynamic Icon Animation Layer
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => RotationTransition(
                  turns: child.key == const ValueKey('close')
                      ? Tween<double>(begin: 0.75, end: 1.0).animate(anim)
                      : Tween<double>(begin: 0.25, end: 1.0).animate(anim),
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: widget.isOpen
                    ? Icon(Icons.close_rounded,
                        key: const ValueKey('close'),
                        color: theme.colorScheme.onPrimary,
                        size: 20)
                    : Icon(Icons.tune_rounded,
                        key: const ValueKey('tune'),
                        color: theme.colorScheme.onSurface,
                        size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Filters',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: widget.isOpen
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
              // Filter count indicator badge
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: hasActive
                    ? Container(
                        key: ValueKey('badge-${widget.activeFilterCount}'),
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: widget.isOpen
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints:
                            const BoxConstraints(minWidth: 20, minHeight: 20),
                        child: Text(
                          '${widget.activeFilterCount}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: widget.isOpen
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onPrimary,
                          ),
                          textAlign: TextAlign.center,
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

/// ---------------------------------------------------------------------------
/// Shared Custom Premium Sub-Widgets (Notion/Stripe Aesthetic)
/// ---------------------------------------------------------------------------

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
      child: ChoiceChip(
        label: Text(widget.label),
        selected: widget.isSelected,
        onSelected: widget.onSelected,
        labelStyle: TextStyle(
          color: widget.isSelected
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        backgroundColor: _isHovered
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerLow,
        selectedColor: theme.colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(
          color: widget.isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withAlpha(153),
          width: 1,
        ),
        showCheckmark: false,
      ),
    );
  }
}

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
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(128)),
            prefixIcon:
                Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant.withAlpha(153)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
