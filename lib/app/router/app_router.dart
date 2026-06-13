import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:synccash/app/router/route_constants.dart';
import 'package:synccash/core/navigation/navigation_service.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/auth/presentation/screens/login_screen.dart';
import 'package:synccash/features/auth/presentation/screens/signup_screen.dart';
import 'package:synccash/features/cashbook/presentation/screens/pairing_screen.dart';
import 'package:synccash/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:synccash/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:synccash/features/transactions/presentation/screens/transaction_history_screen.dart';

// Reusable fade transition — lightweight on iOS PWA (no JIT)
CustomTransitionPage<void> _fadePage({
  required GoRouterState state,
  required Widget child,
  Duration duration = const Duration(milliseconds: 250),
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: child,
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: NavigationService.navigatorKey,
    initialLocation: RouteConstants.splash,

    redirect: (BuildContext context, GoRouterState state) {
      final user = authState.maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );

      final loggedIn = user != null;

      final isAuthRoute =
          state.matchedLocation == RouteConstants.login ||
          state.matchedLocation == RouteConstants.signup;

      if (!loggedIn && !isAuthRoute) return RouteConstants.login;

      if (loggedIn && isAuthRoute) {
        final hasCashbook = user.currentCashbookId != null;
        return hasCashbook
            ? RouteConstants.dashboard
            : RouteConstants.pairing;
      }

      if (loggedIn && state.matchedLocation == RouteConstants.splash) {
        final hasCashbook = user.currentCashbookId != null;
        return hasCashbook
            ? RouteConstants.dashboard
            : RouteConstants.pairing;
      }

      return null;
    },

    routes: [
      GoRoute(
        path: RouteConstants.splash,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          duration: const Duration(milliseconds: 150),
        ),
      ),
      GoRoute(
        path: RouteConstants.login,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: RouteConstants.signup,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: const SignupScreen(),
        ),
      ),
      GoRoute(
        path: RouteConstants.pairing,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: const PairingScreen(),
        ),
      ),
      GoRoute(
        path: RouteConstants.dashboard,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: const DashboardScreen(),
        ),
      ),
      GoRoute(
        path: RouteConstants.addTransaction,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: const AddTransactionScreen(),
        ),
      ),
      GoRoute(
        path: RouteConstants.history,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: const TransactionHistoryScreen(),
        ),
      ),
    ],
  );
});