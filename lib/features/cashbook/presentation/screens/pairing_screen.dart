import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/cashbook/presentation/providers/cashbook_provider.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  void _createLedger() async {
    setState(() => _isLoading = true);
    final user = ref.read(authProvider).value;
    if (user != null) {
      await ref.read(cashbookRepositoryProvider).createCashbook(user.uid);
    }
  }

  void _joinLedger() async {
    if (_codeController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authProvider).value;
      await ref.read(cashbookRepositoryProvider).joinCashbook(user!.uid, _codeController.text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure Sync Coupling')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text('Initialize New Financial Network Node', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _createLedger,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      child: const Text('Generate Sync Node Key', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: Text('OR CONNECT VIA PIPELINE')),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(labelText: 'Enter 6-Digit Secure Invite Token', filled: true),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _joinLedger,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                      child: const Text('Establish Connection Matrix', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}