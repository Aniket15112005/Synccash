// lib/features/auth/presentation/screens/signup_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Controller for ambient background motion matrix
  late AnimationController _bgAnimationController;

  @override
  void initState() {
    super.initState();
    _bgAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _bgAnimationController.dispose();
    super.dispose();
  }

  void _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).signUpWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _nameController.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration Failed: ${e.toString()}'),
            backgroundColor: const Color(0xFFE5484D), 
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0B0C0E);       
    const surfaceColor = Color(0xFF16171A);          
    const borderDefault = Color(0xFF2A2C30);         
    const textPrimary = Color(0xFFEDEEF0);           
    const textSecondary = Color(0xFF8A8E93);         
    const primaryAccent = Color(0xFFF3F4F6);         

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgAnimationController,
            builder: (context, child) {
              return CustomPaint(
                painter: _AmbientBackgroundPainter(
                  progress: _bgAnimationController.value,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(32.0),
                  decoration: BoxDecoration(
                    color: surfaceColor.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderDefault.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: textSecondary),
                              onPressed: () => context.pop(),
                              style: IconButton.styleFrom(
                                backgroundColor: backgroundColor,
                                side: BorderSide(color: borderDefault.withOpacity(0.6)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.all(10),
                              ),
                            ),
                          ],
                        ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0),

                        const SizedBox(height: 20),
                        
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Register Operator',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.8,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Initialize a secure corporate ledger account wrapper.',
                              style: TextStyle(
                                fontSize: 13,
                                color: textSecondary,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        )
                        .animate()
                        .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),

                        const SizedBox(height: 28),

                        // --- Field 1: Name ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Operator Name',
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: textPrimary, fontSize: 14),
                              cursorColor: textPrimary,
                              decoration: _buildGreyInputDecoration(
                                hint: 'e.g., ANIKET',
                                prefixIcon: Icons.badge_outlined, // FIXED COMPILATION ERROR HERE
                                borderDefault: borderDefault,
                                textSecondary: textSecondary,
                                surfaceColor: backgroundColor,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please specify an operator label name';
                                }
                                return null;
                              },
                            ),
                          ],
                        )
                        .animate()
                        .fadeIn(delay: 100.ms, duration: 400.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),

                        const SizedBox(height: 18),

                        // --- Field 2: Email ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Email Address',
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: textPrimary, fontSize: 14),
                              cursorColor: textPrimary,
                              decoration: _buildGreyInputDecoration(
                                hint: 'name@company.com',
                                prefixIcon: Icons.mail_outline_rounded,
                                borderDefault: borderDefault,
                                textSecondary: textSecondary,
                                surfaceColor: backgroundColor,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please specify your registration email';
                                }
                                if (!value.contains('@') || !value.contains('.')) {
                                  return 'Invalid corporate syntax structure framework';
                                }
                                return null;
                              },
                            ),
                          ],
                        )
                        .animate()
                        .fadeIn(delay: 180.ms, duration: 400.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),

                        const SizedBox(height: 18),

                        // --- Field 3: Password ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Secure System Password',
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(color: textPrimary, fontSize: 14),
                              cursorColor: textPrimary,
                              onFieldSubmitted: (_) => _isLoading ? null : _signup(),
                              decoration: _buildGreyInputDecoration(
                                hint: '••••••••••••',
                                prefixIcon: Icons.lock_outline_rounded,
                                borderDefault: borderDefault,
                                textSecondary: textSecondary,
                                surfaceColor: backgroundColor,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword 
                                        ? Icons.visibility_off_outlined 
                                        : Icons.visibility_outlined,
                                    size: 18,
                                    color: textSecondary,
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Password compilation string is missing';
                                }
                                if (value.length < 6) {
                                  return 'Must be at least 6 characters length';
                                }
                                return null;
                              },
                            ),
                          ],
                        )
                        .animate()
                        .fadeIn(delay: 260.ms, duration: 400.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),

                        const SizedBox(height: 32),

                        ElevatedButton(
                          onPressed: _isLoading ? null : _signup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryAccent,
                            foregroundColor: backgroundColor,
                            disabledBackgroundColor: primaryAccent.withOpacity(0.3),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: backgroundColor,
                                    ),
                                  )
                                : const Text(
                                    'Initialize Registration',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                          ),
                        )
                        .animate()
                        .fadeIn(delay: 340.ms, duration: 400.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
                        
                      ],
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

  InputDecoration _buildGreyInputDecoration({
    required String hint,
    required IconData prefixIcon,
    required Color borderDefault,
    required Color textSecondary,
    required Color surfaceColor,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: textSecondary.withOpacity(0.35), fontSize: 14),
      prefixIcon: Icon(prefixIcon, size: 18, color: textSecondary.withOpacity(0.7)),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: surfaceColor,
      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFE5484D)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderDefault.withOpacity(0.7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF686E76), width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1.2),
      ),
    );
  }
}

class _AmbientBackgroundPainter extends CustomPainter {
  final double progress;
  _AmbientBackgroundPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final double radians = progress * 2 * math.pi;
    final double dx = math.sin(radians) * 40;
    final double dy = math.cos(radians) * 30;

    final centerGlow = Offset(size.width * 0.5 + dx, size.height * 0.4 + dy);
    final centerGradient = RadialGradient(
      center: Alignment.center,
      radius: 1.2,
      colors: [
        const Color(0xFF1F2124).withOpacity(0.35),
        const Color(0xFF0B0C0E).withOpacity(0.0),
      ],
    );

    paint.shader = centerGradient.createShader(
      Rect.fromCircle(center: centerGlow, radius: size.width * 0.9),
    );
    canvas.drawCircle(centerGlow, size.width * 0.9, paint);

    final cornerGlow = Offset(size.width * 0.15 - dx, size.height * 0.85 - dy);
    final cornerGradient = RadialGradient(
      center: Alignment.center,
      radius: 0.8,
      colors: [
        const Color(0xFF2E3136).withOpacity(0.18),
        const Color(0xFF0B0C0E).withOpacity(0.0),
      ],
    );

    paint.shader = cornerGradient.createShader(
      Rect.fromCircle(center: cornerGlow, radius: size.width * 0.5),
    );
    canvas.drawCircle(cornerGlow, size.width * 0.5, paint);
  }

  @override
  bool shouldRepaint(covariant _AmbientBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress;
}