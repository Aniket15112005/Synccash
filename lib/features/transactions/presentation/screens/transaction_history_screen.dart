import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider, currentUserIdProvider;
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_list_item.dart';

class TransactionHistoryScreen extends ConsumerWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    final currentUserId = ref.watch(currentUserIdProvider.select((id) => id));

    final transactionsAsync = cashbookId == null
        ? const AsyncValue<List<dynamic>>.data([])
        : ref.watch(transactionsStreamProvider(cashbookId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Complete Ledger History'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: transactionsAsync.when(
        data: (txs) => txs.isEmpty
            ? const Center(
                child: Text(
                  'No historical transaction logs found.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                cacheExtent: 600,
                itemCount: txs.length,
                itemBuilder: (context, index) {
                  final tx = txs[index];
                  return TransactionListItem(
                    key: ValueKey(tx.transactionId),
                    transaction: tx,
                    currentUserId: currentUserId,
                  );
                },
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.expense),
            ),
          ),
        ),
      ),
    );
  }
}