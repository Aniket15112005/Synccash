import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:synccash/app/router/route_constants.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/cashbook/presentation/providers/cashbook_provider.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:synccash/features/transactions/presentation/widgets/transaction_list_item.dart';
import 'package:synccash/features/dashboard/presentation/widgets/balance_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookAsync = ref.watch(cashbookStreamProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SyncCash Matrix'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          )
        ],
      ),
      body: cashbookAsync.when(
        data: (cashbook) => RefreshIndicator(
          onRefresh: () async => {},
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BalanceCard(cashbook: cashbook),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Live Broadcast Stream', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    TextButton(
                      onPressed: () => context.push(RouteConstants.history),
                      child: const Text('Complete Audits', style: TextStyle(color: AppColors.secondary)),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                transactionsAsync.when(
                  data: (txs) => txs.isEmpty 
                      ? const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('No active transmissions logged today')))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: txs.length > 5 ? 5 : txs.length,
                          itemBuilder: (context, index) => TransactionListItem(transaction: txs[index]),
                        ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Stream Decryption Error: $e'),
                )
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fatal Connection Drop: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RouteConstants.addTransaction),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Log Ledger Event', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}