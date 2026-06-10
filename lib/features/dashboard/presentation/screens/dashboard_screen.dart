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

    final authState = ref.watch(authProvider);
    final user = authState.asData?.value;
    final cashbookId = user?.currentCashbookId;

    final filteredTxs = cashbookId == null
        ? const AsyncValue.data([])
        : ref.watch(filteredTransactionsProvider(cashbookId));

    final selectedCategory = ref.watch(selectedCategoryFilterProvider);
    final selectedName = ref.watch(selectedNameFilterProvider);
    final selectedDate = ref.watch(selectedDateFilterProvider);

    // ⭐ NEW: DESCRIPTION STATE
    final selectedDescription =
        ref.watch(selectedDescriptionFilterProvider);

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

                // ================= FILTER ROW =================
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text(selectedDate == null
                            ? 'Date'
                            : '${selectedDate.day}/${selectedDate.month}'),
                        selected: selectedDate != null,
                        onSelected: (_) async {
                          if (selectedDate != null) {
                            ref
                                .read(selectedDateFilterProvider.notifier)
                                .state = null;
                          } else {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: DateTime.now(),
                            );
                            if (picked != null) {
                              ref
                                  .read(selectedDateFilterProvider.notifier)
                                  .state = picked;
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 8),

                      FilterChip(
                        label: Text(selectedName == null
                            ? 'Name'
                            : selectedName),
                        selected: selectedName != null,
                        onSelected: (_) {
                          if (selectedName != null) {
                            ref
                                .read(selectedNameFilterProvider.notifier)
                                .state = null;
                          } else {
                            _showNameDialog(context, ref);
                          }
                        },
                      ),
                      const SizedBox(width: 8),

                      DropdownButton<String>(
                        hint: const Text("Category"),
                        value: (selectedCategory != null &&
        ["Wholesale", "Retail"].contains(selectedCategory))
    ? selectedCategory
    : null,
                        items: const [
                          DropdownMenuItem(
                              value: "Wholesale", child: Text("Wholesale")),
                          DropdownMenuItem(
                              value: "Retail", child: Text("Retail")),
                        ],
                        onChanged: (val) {
                          ref
                              .read(selectedCategoryFilterProvider.notifier)
                              .state = val;
                        },
                      ),

                      const SizedBox(width: 8),

                      // ⭐ NEW: DESCRIPTION FILTER CHIP
                      FilterChip(
                        label: Text(selectedDescription == null
                            ? 'Description'
                            : selectedDescription),
                        selected: selectedDescription != null,
                        onSelected: (_) {
                          if (selectedDescription != null) {
                            ref
                                .read(selectedDescriptionFilterProvider.notifier)
                                .state = null;
                          } else {
                            _showDescriptionDialog(context, ref);
                          }
                        },
                      ),

                      const SizedBox(width: 8),

                      TextButton(
                        onPressed: () {
                          ref.invalidate(filteredTransactionsProvider);

                          ref
                              .read(selectedCategoryFilterProvider.notifier)
                              .state = null;
                          ref
                              .read(selectedNameFilterProvider.notifier)
                              .state = null;
                          ref
                              .read(selectedDateFilterProvider.notifier)
                              .state = null;

                          // ⭐ NEW RESET
                          ref
                              .read(selectedDescriptionFilterProvider.notifier)
                              .state = null;
                        },
                        child: const Text("Reset"),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ====================================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Live Broadcast Stream',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.push(RouteConstants.history),
                      child: const Text('Complete Audits',
                          style: TextStyle(color: AppColors.secondary)),
                    )
                  ],
                ),

                const SizedBox(height: 8),

                filteredTxs.when(
                  data: (txs) => txs.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text(
                                'No active transmissions logged today'),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: txs.length > 5 ? 5 : txs.length,
                          itemBuilder: (context, index) =>
                              TransactionListItem(
                                  transaction: txs[index]),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Text('Stream Decryption Error: $e'),
                )
              ],
            ),
          ),
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Fatal Connection Drop: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push(RouteConstants.addTransaction),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Log Ledger Event',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showNameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Filter by Name"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              ref.read(selectedNameFilterProvider.notifier).state =
                  controller.text;
              Navigator.pop(context);
            },
            child: const Text("Apply"),
          ),
        ],
      ),
    );
  }

  // ⭐ NEW: DESCRIPTION DIALOG
  void _showDescriptionDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Filter by Description"),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(hintText: "Enter description"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(selectedDescriptionFilterProvider.notifier)
                  .state = controller.text;
              Navigator.pop(context);
            },
            child: const Text("Apply"),
          ),
        ],
      ),
    );
  }
}