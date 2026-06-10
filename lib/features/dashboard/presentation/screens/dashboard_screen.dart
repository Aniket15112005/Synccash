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
import 'package:synccash/features/dashboard/presentation/widgets/synccash_filter_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashbookAsync = ref.watch(cashbookStreamProvider);

    // FIX: safe Riverpod usage
    final user = ref.watch(authProvider).asData?.value;

    final cashbookId = user?.currentCashbookId;

    final filteredTxs = cashbookId == null
        ? const AsyncValue.data([])
        : ref.watch(filteredTransactionsProvider(cashbookId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('SyncCash Matrix'),
        actions: [
          IconButton(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Text(
                _getInitial(user?.displayName),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            onPressed: () => _showProfileSheet(context, ref),
          ),
        ],
      ),
      body: cashbookAsync.when(
        data: (cashbook) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(cashbookStreamProvider);

            if (cashbookId != null) {
              ref.invalidate(filteredTransactionsProvider(cashbookId));
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BalanceCard(cashbook: cashbook),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerRight,
                  child: SyncCashFilterPanel(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Live Broadcast Stream',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push(RouteConstants.history),
                      child: const Text(
                        'Complete Audits',
                        style: TextStyle(color: AppColors.secondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                filteredTxs.when(
                  data: (txs) => txs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text('No active transmissions logged today'),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: txs.length > 5 ? 5 : txs.length,
                          itemBuilder: (context, index) =>
                              TransactionListItem(transaction: txs[index]),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Stream Decryption Error: $e'),
                ),
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
        label: const Text(
          'Log Ledger Event',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // FIX: safe reusable avatar initial
  String _getInitial(String? name) {
    final safe = name?.trim();
    if (safe == null || safe.isEmpty) return 'U';
    return safe[0].toUpperCase();
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showProfileSheet(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).asData?.value;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary,
                child: Text(
                  _getInitial(user?.displayName),
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user?.displayName ?? 'User',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                user?.email ?? '',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showLogoutDialog(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
