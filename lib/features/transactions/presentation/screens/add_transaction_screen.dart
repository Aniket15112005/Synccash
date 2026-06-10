import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  String _type = 'expense';
  String _category = 'Retail';

  final List<String> _categories = ['Retail','Wholesale'];

  void _submit() async {
    if (_amountController.text.isEmpty) return;
    
    final user = ref.read(authProvider).value;
    if (user == null) return;

    final tx = TransactionEntity(
      transactionId: '',
      cashbookId: user.currentCashbookId!,
      createdBy: user.uid,
      creatorName: user.displayName,
      createdAt: DateTime.now(),
      amount: double.parse(_amountController.text),
      type: _type,
      category: _category.toLowerCase(),
      description: _descController.text.trim(),
    );

    await ref.read(transactionRepositoryProvider).addTransaction(tx);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Structural Ledger Entry')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('INCOME')),
                    selected: _type == 'income',
                    selectedColor: AppColors.income.withOpacity(0.2),
                    onSelected: (val) => setState(() => _type = 'income'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('EXPENSE')),
                    selected: _type == 'expense',
                    selectedColor: AppColors.expense.withOpacity(0.2),
                    onSelected: (val) => setState(() => _type = 'expense'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(labelText: 'Transaction Total (INR)', prefixText: '₹ ', filled: true),
            ),
            const SizedBox(height: 24),
            DropdownButton<String>(
              value: _category,
              items: _categories
                  .map((category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _category = val;
                });
              },
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Audit Memo / Description', filled: true),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Commit Entry to Synchronized State', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}