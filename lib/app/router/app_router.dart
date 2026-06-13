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
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

// ── Step 1: A ChangeNotifier that wraps the auth stream ──────────────────────
// GoRouter's refreshListenable only re-runs the redirect — it does NOT
// recreate the router. This is the correct pattern.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    // Listen to the auth stream and notify GoRouter to re-evaluate redirects.
    _ref.listen<AsyncValue<dynamic>>(
      authProvider,
      (_, __) => notifyListeners(),
    );
  }
  final Ref _ref;
}

final _authNotifierProvider = Provider<_AuthNotifier>((ref) {
  return _AuthNotifier(ref);
});

// ── Step 2: Router is created ONCE and never recreated ───────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_authNotifierProvider);

  return GoRouter(
    navigatorKey: NavigationService.navigatorKey,
    initialLocation: RouteConstants.splash,
    refreshListenable: notifier,  // re-runs redirect only, no router rebuild

    redirect: (BuildContext context, GoRouterState state) {
      final authState = ref.read(authProvider);

      // ── CRITICAL FIX: Do NOT redirect while auth is still loading ──────────
      // Without this, unauthenticated redirect fires before Firebase resolves
      // the persisted session, causing a visible flash to /login on every open.
      if (authState.isLoading) return null;

      final user = authState.asData?.value;
      final loggedIn = user != null;

      final isAuthRoute =
          state.matchedLocation == RouteConstants.login ||
          state.matchedLocation == RouteConstants.signup;

      if (!loggedIn && !isAuthRoute) return RouteConstants.login;

      if (loggedIn && isAuthRoute) {
        return user.currentCashbookId != null
            ? RouteConstants.dashboard
            : RouteConstants.pairing;
      }

      if (loggedIn && state.matchedLocation == RouteConstants.splash) {
        return user.currentCashbookId != null
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
            backgroundColor: Color(0xFF080a0e),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF4f6ef7)),
            ),
          ),
          duration: const Duration(milliseconds: 150),
        ),
      ),
      GoRoute(
        path: RouteConstants.login,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const LoginScreen()),
      ),
      GoRoute(
        path: RouteConstants.signup,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const SignupScreen()),
      ),
      GoRoute(
        path: RouteConstants.pairing,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const PairingScreen()),
      ),
      GoRoute(
        path: RouteConstants.dashboard,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const DashboardScreen()),
      ),
      GoRoute(
        path: RouteConstants.addTransaction,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const AddTransactionScreen()),
      ),
      GoRoute(
        path: RouteConstants.history,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const TransactionHistoryScreen()),
      ),
    ],
  );
});