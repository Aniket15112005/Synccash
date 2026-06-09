import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_list_item.dart';

class TransactionHistoryScreen extends ConsumerWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Complete Ledger History')),
      body: transactionsAsync.when(
        data: (txs) => txs.isEmpty
            ? const Center(child: Text('No historical transaction logs found.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: txs.length,
                itemBuilder: (context, index) => TransactionListItem(transaction: txs[index]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}