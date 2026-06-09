import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:synccash/app/router/route_constants.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _login() async {
    // 1. Fully normalize and cleanse all character inputs
    final cleanEmail = _emailController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '') 
        .toLowerCase();                 
    
    final cleanPassword = _passwordController.text.trim();

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all layout credentials.')),
      );
      return;
    }

    // 2. Extra safety pass for web browser email format validation
    final emailRegex = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
    if (!emailRegex.hasMatch(cleanEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local Validation Error: Check email layout syntax.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      // Print the outgoing payload to verify the string is perfectly clean
      print("AUTH DEPLOY ---> Attempting login for: '$cleanEmail'");
      
      await ref.read(authRepositoryProvider).signInWithEmail(
        cleanEmail,
        cleanPassword,
      );
    } catch (e) {
      final errorMessage = e.toString();
      print("AUTH FAILURE LOG ---> Raw Exception details: $errorMessage");
      
      String friendlyMessage = 'Authentication failed. Please verify credentials or create a profile.';
      
      // Map obscure system errors into clear action steps
      if (errorMessage.contains('invalid-credential') || 
          errorMessage.contains('wrong-password') || 
          errorMessage.contains('user-not-found')) {
        friendlyMessage = 'Invalid email address or password combination.';
      } else if (errorMessage.contains('invalid-email') || 
                 errorMessage.contains('badly formatted') || 
                 errorMessage.contains('channel-error')) {
        friendlyMessage = 'Network authentication format loop detected. Try logging in once more or use signup below.';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SyncCash', style: Theme.of(context).textTheme.displayLarge)
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .slideY(begin: 0.3, end: 0),
              const SizedBox(height: 8),
              const Text('Shared Real-time Ledger for Businesses', 
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 48),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email Address', 
                  filled: true,
                  hintText: 'name@example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Password', 
                  filled: true,
                ),
                onSubmitted: (_) => _isLoading ? null : _login(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('Access Account', 
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.push(RouteConstants.signup),
                child: const Text('Create a Corporate Ledger Partner Profile', 
                    style: TextStyle(color: AppColors.secondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}