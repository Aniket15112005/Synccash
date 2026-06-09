import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/router/route_constants.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/auth/presentation/screens/login_screen.dart';
import 'package:synccash/features/auth/presentation/screens/signup_screen.dart';
import 'package:synccash/features/cashbook/presentation/screens/pairing_screen.dart';
import 'package:synccash/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:synccash/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:synccash/features/transactions/presentation/screens/transaction_history_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: RouteConstants.splash,
    redirect: (BuildContext context, GoRouterState state) {
      final loggedIn = authState.value != null;
      final isAuthRoute = state.matchedLocation == RouteConstants.login || 
                          state.matchedLocation == RouteConstants.signup;

      if (!loggedIn && !isAuthRoute) return RouteConstants.login;
      if (loggedIn && isAuthRoute) {
        final hasCashbook = authState.value?.currentCashbookId != null;
        return hasCashbook ? RouteConstants.dashboard : RouteConstants.pairing;
      }
      if (loggedIn && state.matchedLocation == RouteConstants.splash) {
        final hasCashbook = authState.value?.currentCashbookId != null;
        return hasCashbook ? RouteConstants.dashboard : RouteConstants.pairing;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: RouteConstants.splash,
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(
        path: RouteConstants.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteConstants.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: RouteConstants.pairing,
        builder: (context, state) => const PairingScreen(),
      ),
      GoRoute(
        path: RouteConstants.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: RouteConstants.addTransaction,
        builder: (context, state) => const AddTransactionScreen(),
      ),
      GoRoute(
        path: RouteConstants.history,
        builder: (context, state) => const TransactionHistoryScreen(),
      ),
    ],
  );
});