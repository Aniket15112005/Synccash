// lib/features/transactions/presentation/screens/add_transaction_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';

class _C {
  static const bg       = Color(0xFF08090B);
  static const surface  = Color(0xFF111316);
  static const surface2 = Color(0xFF18191E);
  static const border   = Color(0xFF202228);
  static const border2  = Color(0xFF2A2C33);
  static const textPri  = Color(0xFFF0F1F3);
  static const textSec  = Color(0xFF6B7280);
  static const textMut  = Color(0xFF3D4149);
  static const income   = Color(0xFF22C55E);
  static const expense  = Color(0xFFF43F5E);
}

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen>
    with SingleTickerProviderStateMixin {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();

  String   _type         = 'expense';
  String   _category     = 'Retail';
  bool     _submitting   = false;
  DateTime _selectedDate = DateTime.now();

  late final AnimationController _btnCtrl;
  late final Animation<double>   _btnScale;

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _btnScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _btnCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  Color get _accentColor => _type == 'income' ? _C.income : _C.expense;

  void _switchType(String type) {
    if (_type == type) return;
    HapticFeedback.selectionClick();
    setState(() => _type = type);
  }

  void _switchCategory(String cat) {
    if (_category == cat) return;
    HapticFeedback.selectionClick();
    setState(() => _category = cat);
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: _accentColor,
              onPrimary: Colors.black,
              surface: const Color(0xFF161922),
              onSurface: _C.textPri,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF111316),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        // Preserve today's time if same day, otherwise use midnight
        final now = DateTime.now();
        if (picked.year == now.year &&
            picked.month == now.month &&
            picked.day == now.day) {
          _selectedDate = now;
        } else {
          _selectedDate = DateTime(
              picked.year, picked.month, picked.day, 12, 0, 0);
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authProvider).value;
    if (user == null) return;

    await _btnCtrl.forward();
    await _btnCtrl.reverse();

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);

    try {
      final tx = TransactionEntity(
        transactionId: '',
        cashbookId:    user.currentCashbookId!,
        createdBy:     user.uid,
        creatorName:   user.displayName,
        createdAt:     _selectedDate,
        amount:        double.parse(_amountCtrl.text.trim()),
        type:          _type,
        category:      _category.toLowerCase(),
        description:   _descCtrl.text.trim(),
      );
      await ref.read(transactionRepositoryProvider).addTransaction(tx);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: _C.expense,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: _AmbientGlow(accent: _accentColor)),
          SafeArea(
            child: Column(
              children: [
                _AppBar(onBack: () => Navigator.pop(context))
                    .animate()
                    .fadeIn(duration: 240.ms)
                    .slideY(begin: -0.06, end: 0, curve: Curves.easeOut),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TypeToggle(type: _type, onSwitch: _switchType)
                              .animate()
                              .fadeIn(delay: 60.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 28),
                          const _FieldLabel('Amount (INR)'),
                          const SizedBox(height: 8),
                          _AmountField(controller: _amountCtrl, accent: _accentColor)
                              .animate()
                              .fadeIn(delay: 110.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 24),
                          const _FieldLabel('Category'),
                          const SizedBox(height: 8),
                          _CategoryToggle(selected: _category, onSwitch: _switchCategory)
                              .animate()
                              .fadeIn(delay: 160.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 24),
                          const _FieldLabel('Description'),
                          const SizedBox(height: 8),
                          _DescriptionField(controller: _descCtrl)
                              .animate()
                              .fadeIn(delay: 210.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 24),
                          const _FieldLabel('Date'),
                          const SizedBox(height: 8),
                          _DatePickerField(
                            selectedDate: _selectedDate,
                            accent: _accentColor,
                            onTap: _pickDate,
                          )
                              .animate()
                              .fadeIn(delay: 245.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 36),
                          ScaleTransition(
                            scale: _btnScale,
                            child: _SubmitButton(
                              type:       _type,
                              accent:     _accentColor,
                              submitting: _submitting,
                              onTap:      _submit,
                            ),
                          )
                              .animate()
                              .fadeIn(delay: 280.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                        ],
                      ),
                    ),
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

// ─── Date picker field ────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final DateTime selectedDate;
  final Color accent;
  final VoidCallback onTap;

  const _DatePickerField({
    required this.selectedDate,
    required this.accent,
    required this.onTap,
  });

  bool get _isToday {
    final now = DateTime.now();
    return selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final label = _isToday
        ? 'Today'
        : DateFormat('dd MMM yyyy').format(selectedDate);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _C.textPri,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    DateFormat('EEEE').format(selectedDate),
                    style: const TextStyle(
                      color: _C.textSec,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _C.textSec.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ambient glow ─────────────────────────────────────────────────────────────

class _AmbientGlow extends StatelessWidget {
  final Color accent;
  const _AmbientGlow({required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.6),
          radius: 1.2,
          colors: [accent.withValues(alpha: 0.07), _C.bg.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}

// ─── App bar ──────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final VoidCallback onBack;
  const _AppBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          _IconBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
          const SizedBox(width: 14),
          const Text(
            'New Entry',
            style: TextStyle(
              color: _C.textPri,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: Icon(icon, size: 15, color: _C.textSec),
      ),
    );
  }
}

// ─── Type toggle ──────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  final String type;
  final void Function(String) onSwitch;
  const _TypeToggle({required this.type, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: [
          _TypeChip(
            label: 'Income', icon: Icons.south_rounded,
            active: type == 'income', activeColor: _C.income,
            onTap: () => onSwitch('income'),
          ),
          const SizedBox(width: 4),
          _TypeChip(
            label: 'Expense', icon: Icons.north_rounded,
            active: type == 'expense', activeColor: _C.expense,
            onTap: () => onSwitch('expense'),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label, required this.icon, required this.active,
    required this.activeColor, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? activeColor.withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: active ? activeColor.withValues(alpha: 0.18) : _C.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 14,
                    color: active ? activeColor : _C.textSec),
              ),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  color: active ? activeColor : _C.textSec,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Amount field ─────────────────────────────────────────────────────────────

class _AmountField extends StatefulWidget {
  final TextEditingController controller;
  final Color accent;
  const _AmountField({required this.controller, required this.accent});

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? widget.accent.withValues(alpha: 0.5) : _C.border,
          width: _focused ? 1.5 : 1.0,
        ),
        boxShadow: _focused
            ? [BoxShadow(
                color: widget.accent.withValues(alpha: 0.08),
                blurRadius: 12, spreadRadius: 0)]
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        cursorColor: widget.accent,
        cursorWidth: 1.5,
        style: const TextStyle(
          color: _C.textPri, fontSize: 28,
          fontWeight: FontWeight.w700, letterSpacing: -0.8,
        ),
        decoration: InputDecoration(
          hintText: '0.00',
          hintStyle: const TextStyle(
            color: _C.textMut, fontSize: 28,
            fontWeight: FontWeight.w700, letterSpacing: -0.8,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: _focused ? widget.accent : _C.textSec,
                fontSize: 20, fontWeight: FontWeight.w600,
              ),
              child: const Text('₹'),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: InputBorder.none,
          errorBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          errorStyle: const TextStyle(fontSize: 11, color: _C.expense, height: 0.1),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Enter an amount';
          if (double.tryParse(v.trim()) == null) return 'Invalid number';
          if (double.parse(v.trim()) <= 0) return 'Amount must be greater than 0';
          return null;
        },
      ),
    );
  }
}

// ─── Category toggle ──────────────────────────────────────────────────────────

class _CategoryToggle extends StatelessWidget {
  final String selected;
  final void Function(String) onSwitch;
  const _CategoryToggle({required this.selected, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: ['Retail', 'Wholesale'].map((cat) {
          final active = selected == cat;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSwitch(cat),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active ? _C.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active ? _C.border2 : Colors.transparent,
                  ),
                ),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: active ? _C.textPri : _C.textSec,
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: -0.1,
                    ),
                    child: Text(cat),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Description field ────────────────────────────────────────────────────────

class _DescriptionField extends StatefulWidget {
  final TextEditingController controller;
  const _DescriptionField({required this.controller});

  @override
  State<_DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends State<_DescriptionField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? const Color(0xFF4B5563) : _C.border,
          width: _focused ? 1.5 : 1.0,
        ),
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        maxLines: 3,
        cursorColor: _C.textPri,
        cursorWidth: 1.5,
        style: const TextStyle(color: _C.textPri, fontSize: 14, height: 1.6),
        decoration: InputDecoration(
          hintText: 'What was this for?',
          hintStyle: const TextStyle(color: _C.textMut, fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8, top: 14),
            child: Icon(Icons.notes_rounded, size: 17,
                color: _focused ? _C.textSec : _C.textMut),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 52),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

// ─── Submit button ────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final String type;
  final Color accent;
  final bool submitting;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.type, required this.accent,
    required this.submitting, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: submitting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        height: 56,
        decoration: BoxDecoration(
          color: submitting ? _C.border2 : accent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: submitting
              ? null
              : [BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: submitting
                ? const SizedBox(
                    key: ValueKey('loader'),
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _C.textSec),
                  )
                : Row(
                    key: ValueKey<String>(type),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type == 'income'
                            ? Icons.south_rounded
                            : Icons.north_rounded,
                        size: 16, color: Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        type == 'income' ? 'Save Income' : 'Save Expense',
                        style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: Colors.black87, letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Field label ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12, color: _C.textSec,
        fontWeight: FontWeight.w600, letterSpacing: 0.2,
      ),
    );
  }
}
