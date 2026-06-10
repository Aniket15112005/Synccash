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

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  String _getInitial(String? name) {
    final safe = name?.trim();
    if (safe == null || safe.isEmpty) return 'U';
    return safe[0].toUpperCase();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Sign out',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  void _showProfileSheet(BuildContext context) {
    final user = ref.read(authProvider).asData?.value;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileBottomSheet(
        initial: _getInitial(user?.displayName),
        displayName: user?.displayName,
        email: user?.email,
        onLogout: () {
          Navigator.pop(context);
          _showLogoutDialog(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cashbookAsync = ref.watch(cashbookStreamProvider);
    final user = ref.watch(authProvider).asData?.value;
    final cashbookId = user?.currentCashbookId;

    final filteredTxs = cashbookId == null
        ? const AsyncValue.data([])
        : ref.watch(filteredTransactionsProvider(cashbookId));

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: false,
      body: cashbookAsync.when(
        data: (cashbook) => FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                ref.invalidate(cashbookStreamProvider);
                if (cashbookId != null) {
                  ref.invalidate(filteredTransactionsProvider(cashbookId));
                }
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getGreeting(),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.displayName?.split(' ').first ??
                                    'Welcome',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _showProfileSheet(context),
                            child: _AvatarWidget(
                              initial: _getInitial(user?.displayName),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: BalanceCard(cashbook: cashbook),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: _SectionHeader(
                        title: 'Recent transactions',
                        action: 'View all',
                        onAction: () => context.push(RouteConstants.history),
                        trailing: const SyncCashFilterPanel(),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  _buildTransactionSliver(filteredTxs),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (e, _) => Center(
          child: _ErrorState(message: e.toString()),
        ),
      ),
      floatingActionButton: _AnimatedFab(
        onPressed: () => context.push(RouteConstants.addTransaction),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, dynamic user) {
    return AppBar(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getGreeting(),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            user?.displayName?.split(' ').first ?? 'Welcome',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: GestureDetector(
            onTap: () => _showProfileSheet(context),
            child: _AvatarWidget(initial: _getInitial(user?.displayName)),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionSliver(AsyncValue filteredTxs) {
    return filteredTxs.when(
      data: (txs) {
        if (txs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _EmptyTransactions(),
            ),
          );
        }

        final displayList = txs.length > 5 ? txs.sublist(0, 5) : txs;

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.separated(
            itemCount: displayList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
    TransactionListItem(
      transaction: displayList[index],
    ),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ErrorState(message: e.toString()),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// ── Avatar widget ─────────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  final String initial;

  const _AvatarWidget({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 18),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: Text(
                  action,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (trailing != null) ...[
          const SizedBox(height: 10),
          trailing!,
        ],
      ],
    );
  }
}

// ── Animated list item ────────────────────────────────────────────────────────

class _AnimatedListItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedListItem({required this.index, required this.child});

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350 + widget.index * 60),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ── Animated FAB ──────────────────────────────────────────────────────────────

class _AnimatedFab extends StatefulWidget {
  final VoidCallback onPressed;

  const _AnimatedFab({required this.onPressed});

  @override
  State<_AnimatedFab> createState() => _AnimatedFabState();
}

class _AnimatedFabState extends State<_AnimatedFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FloatingActionButton.extended(
        onPressed: widget.onPressed,
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: const Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 22,
        ),
        label: const Text(
          'Add Transaction',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 26,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the button below to log your first transaction.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.red.shade400, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Something went wrong. Pull to refresh.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile bottom sheet ──────────────────────────────────────────────────────

class _ProfileBottomSheet extends StatelessWidget {
  final String initial;
  final String? displayName;
  final String? email;
  final VoidCallback onLogout;

  const _ProfileBottomSheet({
    required this.initial,
    required this.displayName,
    required this.email,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            displayName ?? 'User',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email ?? '',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 28),
          Divider(color: Colors.grey.shade100, height: 1),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.logout_rounded,
                color: Colors.red.shade400,
                size: 18,
              ),
            ),
            title: Text(
              'Sign out',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.red.shade400,
              ),
            ),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}
