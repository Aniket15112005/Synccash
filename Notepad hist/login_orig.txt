import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:synccash/app/router/route_constants.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

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
    _emailController.dispose();
    _passwordController.dispose();
    _bgAnimationController.dispose();
    super.dispose();
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;

    final cleanEmail = _emailController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();

    final cleanPassword = _passwordController.text.trim();

    setState(() => _isLoading = true);

    try {
      if (kDebugMode) {
        print("AUTH DEPLOY ---> Attempting login for: '$cleanEmail'");
      }
      await ref.read(authRepositoryProvider).signInWithEmail(
            cleanEmail,
            cleanPassword,
          );
    } catch (e) {
      final errorMessage = e.toString();
      if (kDebugMode) {
        print("AUTH FAILURE LOG ---> Raw Exception details: $errorMessage");
      }

      String friendlyMessage =
          'Authentication failed. Please verify credentials or create a profile.';

      if (errorMessage.contains('invalid-credential') ||
          errorMessage.contains('wrong-password') ||
          errorMessage.contains('user-not-found')) {
        friendlyMessage = 'Invalid email address or password combination.';
      } else if (errorMessage.contains('invalid-email') ||
          errorMessage.contains('badly formatted') ||
          errorMessage.contains('channel-error')) {
        friendlyMessage =
            'Network authentication format loop detected. Try logging in once more or use signup below.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: const Color(0xFFE5484D),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    color: surfaceColor.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderDefault.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
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
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 52,
                              width: 52,
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderDefault),
                              ),
                              child: const Icon(
                                Icons.blur_on_rounded,
                                size: 28,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'SyncCash',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.8,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Shared Real-time Ledger for Businesses',
                              style: TextStyle(
                                fontSize: 13,
                                color: textSecondary,
                                letterSpacing: -0.1,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                            .animate()
                            .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                            .slideY(
                                begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                        const SizedBox(height: 36),

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
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(
                                  color: textPrimary, fontSize: 14),
                              cursorColor: textPrimary,
                              decoration: _buildGreyInputDecoration(
                                hint: 'name@example.com',
                                prefixIcon: Icons.mail_outline_rounded,
                                borderDefault: borderDefault,
                                textSecondary: textSecondary,
                                surfaceColor: backgroundColor,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your email address';
                                }
                                final emailRegex = RegExp(
                                  r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                                );
                                if (!emailRegex.hasMatch(
                                    value.trim().replaceAll(' ', ''))) {
                                  return 'Check email structure format style syntax.';
                                }
                                return null;
                              },
                            ),
                          ],
                        )
                            .animate()
                            .fadeIn(
                                delay: 150.ms,
                                duration: 400.ms,
                                curve: Curves.easeOut)
                            .slideY(
                                begin: 0.05,
                                end: 0,
                                curve: Curves.easeOutCubic),

                        const SizedBox(height: 20),

                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Password',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(
                                  color: textPrimary, fontSize: 14),
                              cursorColor: textPrimary,
                              onFieldSubmitted: (_) =>
                                  _isLoading ? null : _login(),
                              decoration: _buildGreyInputDecoration(
                                hint: '••••••••',
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
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                          ],
                        )
                            .animate()
                            .fadeIn(
                                delay: 250.ms,
                                duration: 400.ms,
                                curve: Curves.easeOut)
                            .slideY(
                                begin: 0.05,
                                end: 0,
                                curve: Curves.easeOutCubic),

                        const SizedBox(height: 32),

                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryAccent,
                            foregroundColor: backgroundColor,
                            disabledBackgroundColor:
                                primaryAccent.withValues(alpha: 0.3),
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
                                    'Access Account',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                          ),
                        )
                            .animate()
                            .fadeIn(
                                delay: 350.ms,
                                duration: 400.ms,
                                curve: Curves.easeOut)
                            .slideY(
                                begin: 0.04,
                                end: 0,
                                curve: Curves.easeOutCubic),

                        const SizedBox(height: 24),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account? ",
                              style:
                                  TextStyle(fontSize: 13, color: textSecondary),
                            ),
                            GestureDetector(
                              onTap: () => context.push(RouteConstants.signup),
                              child: const Text(
                                'Create Profile',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ).animate().fadeIn(delay: 450.ms, duration: 300.ms),
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
      hintStyle:
          TextStyle(color: textSecondary.withValues(alpha: 0.35), fontSize: 14),
      prefixIcon:
          Icon(prefixIcon, size: 18, color: textSecondary.withValues(alpha: 0.7)),
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
        borderSide: BorderSide(color: borderDefault.withValues(alpha: 0.7)),
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
        const Color(0xFF1F2124).withValues(alpha: 0.35),
        const Color(0xFF0B0C0E).withValues(alpha: 0.0),
      ],
    );

    paint.shader = centerGradient.createShader(
      Rect.fromCircle(center: centerGlow, radius: size.width * 0.9),
    );
    canvas.drawCircle(centerGlow, size.width * 0.9, paint);

    final cornerGlow = Offset(size.width * 0.85 - dx, size.height * 0.15 - dy);
    final cornerGradient = RadialGradient(
      center: Alignment.center,
      radius: 0.8,
      colors: [
        const Color(0xFF2E3136).withValues(alpha: 0.18),
        const Color(0xFF0B0C0E).withValues(alpha: 0.0),
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
