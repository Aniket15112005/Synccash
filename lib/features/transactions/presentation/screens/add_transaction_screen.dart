// lib/features/transactions/presentation/screens/add_transaction_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  
  String _type = 'expense';
  String _category = 'Retail';
  bool _isSubmitting = false;

  late AnimationController _bgAnimationController;

  @override
  void initState() {
    super.initState();
    _bgAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    _bgAnimationController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final user = ref.read(authProvider).value;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      final tx = TransactionEntity(
        transactionId: '',
        cashbookId: user.currentCashbookId!,
        createdBy: user.uid,
        creatorName: user.displayName,
        createdAt: DateTime.now(),
        amount: double.parse(_amountController.text.trim()),
        type: _type,
        category: _category.toLowerCase(),
        description: _descController.text.trim(),
      );

      await ref.read(transactionRepositoryProvider).addTransaction(tx);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ledger Commit Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF453A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF07080A);       
    const surfaceColor = Color(0xFF121316);          
    const borderDefault = Color(0xFF222428);         
    const textPrimary = Color(0xFFF1F2F4);           
    const textSecondary = Color(0xFF7E848C);         

    const neonGreenActive = Color(0xFF32D74B);
    const neonRedActive = Color(0xFFFF453A);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // --- Ambient Ledger Record Tape Background ---
          AnimatedBuilder(
            animation: _bgAnimationController,
            builder: (context, child) {
              return CustomPaint(
                painter: _LedgerRecordTapePainter(
                  progress: _bgAnimationController.value,
                  type: _type,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: textSecondary),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          backgroundColor: surfaceColor,
                          side: BorderSide(color: borderDefault.withOpacity(0.8)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'New Ledger Entry',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      padding: const EdgeInsets.all(28.0),
                      decoration: BoxDecoration(
                        color: surfaceColor.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: borderDefault.withOpacity(0.6)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // --- Neon High-Glow Selection Block ---
                            Row(
                              children: [
                                _buildUltraGlowTypeButton(
                                  label: 'INCOME',
                                  isActive: _type == 'income',
                                  activeColor: neonGreenActive,
                                  icon: Icons.arrow_downward_rounded,
                                  onTap: () => setState(() => _type = 'income'),
                                ),
                                const SizedBox(width: 16),
                                _buildUltraGlowTypeButton(
                                  label: 'EXPENSE',
                                  isActive: _type == 'expense',
                                  activeColor: neonRedActive,
                                  icon: Icons.arrow_upward_rounded,
                                  onTap: () => setState(() => _type = 'expense'),
                                ),
                              ],
                            ).animate().fadeIn(duration: 400.ms),

                            const SizedBox(height: 28),

                            // --- Amount Input Module ---
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Transaction Total (INR)',
                                  style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _amountController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textInputAction: TextInputAction.next,
                                  cursorColor: textPrimary,
                                  style: const TextStyle(color: textPrimary, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                                  decoration: _buildGreyInputDecoration(
                                    hint: '0.00',
                                    prefixIcon: Icons.currency_rupee_rounded,
                                    borderDefault: borderDefault,
                                    textSecondary: textSecondary,
                                    surfaceColor: backgroundColor,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter a transactional execution total';
                                    }
                                    if (double.tryParse(value.trim()) == null) {
                                      return 'Please enter a valid numeric value';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                            const SizedBox(height: 24),

                            // --- Category Segment ---
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Category',
                                  style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: backgroundColor,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: borderDefault),
                                  ),
                                  child: Row(
                                    children: [
                                      _buildPremiumCategoryCapsule(
                                        label: 'Retail',
                                        isSelected: _category == 'Retail',
                                        borderDefault: borderDefault,
                                        surfaceColor: surfaceColor,
                                        textPrimary: textPrimary,
                                        textSecondary: textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      _buildPremiumCategoryCapsule(
                                        label: 'Wholesale',
                                        isSelected: _category == 'Wholesale',
                                        borderDefault: borderDefault,
                                        surfaceColor: surfaceColor,
                                        textPrimary: textPrimary,
                                        textSecondary: textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ).animate().fadeIn(delay: 180.ms, duration: 400.ms),

                            const SizedBox(height: 24),

                            // --- Description Input Module ---
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Audit Memo / Description',
                                  style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _descController,
                                  textInputAction: TextInputAction.done,
                                  maxLines: 3,
                                  cursorColor: textPrimary,
                                  style: const TextStyle(color: textPrimary, fontSize: 14),
                                  decoration: _buildGreyInputDecoration(
                                    hint: 'Describe the operational purpose of this ledger entry...',
                                    prefixIcon: Icons.description_outlined,
                                    borderDefault: borderDefault,
                                    textSecondary: textSecondary,
                                    surfaceColor: backgroundColor,
                                  ),
                                  onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
                                ),
                              ],
                            ).animate().fadeIn(delay: 260.ms, duration: 400.ms),

                            const SizedBox(height: 36),

                            // --- Dynamically Morphed Submit Button ---
                            ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _type == 'income' ? neonGreenActive : neonRedActive,
                                foregroundColor: Colors.black,
                                disabledBackgroundColor: textSecondary.withOpacity(0.2),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                shadowColor: (_type == 'income' ? neonGreenActive : neonRedActive).withOpacity(0.4),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: _isSubmitting
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.black,
                                        ),
                                      )
                                    : Text(
                                        _type == 'income' ? 'Add Income Entry' : 'Add Expense Entry',
                                        key: ValueKey<String>(_type),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900, // FIXED: Changed from FontWeight.black to FontWeight.w900
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                              ),
                            ).animate().fadeIn(delay: 340.ms, duration: 400.ms),
                          ],
                        ),
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

  /// Neon Ultra Glow Segment Selector Engine
  Widget _buildUltraGlowTypeButton({
    required String label,
    required bool isActive,
    required Color activeColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.15) : const Color(0xFF0F1012),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? activeColor : const Color(0xFF1B1D21),
              width: isActive ? 2.0 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 2),
                    ),
                    // FIXED: Removed the invalid custom inner shadow block parameter here
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: AnimatedOpacity( // FIXED: Upgraded from static Opacity to AnimatedOpacity
            duration: const Duration(milliseconds: 200),
            opacity: isActive ? 1.0 : 0.35,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isActive ? activeColor : const Color(0xFF7E848C),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF7E848C),
                    fontWeight: FontWeight.w900, // FIXED: Changed from FontWeight.black to FontWeight.w900
                    fontSize: 14,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Modern Inline Capsule Item View Builder
  Widget _buildPremiumCategoryCapsule({
    required String label,
    required bool isSelected,
    required Color borderDefault,
    required Color surfaceColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _category = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? surfaceColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? borderDefault : Colors.transparent,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? textPrimary : textSecondary.withOpacity(0.7),
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Universal Input Spec Sheet Component
  InputDecoration _buildGreyInputDecoration({
    required String hint,
    required IconData prefixIcon,
    required Color borderDefault,
    required Color textSecondary,
    required Color surfaceColor,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: textSecondary.withOpacity(0.3), fontSize: 14, fontWeight: FontWeight.normal),
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Icon(prefixIcon, size: 18, color: textSecondary.withOpacity(0.6)),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      filled: true,
      fillColor: surfaceColor,
      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFFF453A)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderDefault.withOpacity(0.7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF484A50), width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF453A), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF453A), width: 1.2),
      ),
    );
  }
}

/// --- Custom Background Painter for Ambient, Flowing Record Ledger Matrices ---
class _LedgerRecordTapePainter extends CustomPainter {
  final double progress;
  final String type;
  _LedgerRecordTapePainter({required this.progress, required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;
    
    final baseColor = type == 'income' ? const Color(0xFF32D74B) : const Color(0xFFFF453A);

    final centerGlow = Offset(size.width * 0.5, size.height * 0.3);
    final centerGradient = RadialGradient(
      center: Alignment.center,
      radius: 1.4,
      colors: [
        baseColor.withOpacity(0.08),
        const Color(0xFF07080A).withOpacity(0.0),
      ],
    );

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = centerGradient.createShader(Rect.fromCircle(center: centerGlow, radius: size.width * 0.8));
    canvas.drawCircle(centerGlow, size.width * 0.8, fillPaint);

    paint.color = baseColor.withOpacity(0.04);
    paint.strokeWidth = 1.0;

    final double waveSpacing = size.height / 7;
    for (int i = 0; i < 6; i++) {
      final Path path = Path();
      final double yPos = waveSpacing * (i + 1);
      
      path.moveTo(0, yPos);
      for (double x = 0; x <= size.width; x += 20) {
        final double lacing = (x / size.width) * 2 * math.pi + (progress * 2 * math.pi);
        final double yDelta = math.sin(lacing + i) * 15;
        path.lineTo(x, yPos + yDelta);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LedgerRecordTapePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.type != type;
}