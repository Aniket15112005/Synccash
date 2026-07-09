import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:synccash/app/router/route_constants.dart';
import 'package:synccash/core/navigation/navigation_service.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/auth/presentation/screens/login_screen.dart';
import 'package:synccash/features/auth/presentation/screens/signup_screen.dart';
import 'package:synccash/features/cashbook/presentation/screens/pairing_screen.dart';
import 'package:synccash/features/cashbook/presentation/screens/splash_screen.dart';
import 'package:synccash/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:synccash/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:synccash/features/transactions/presentation/screens/transaction_history_screen.dart';
import 'package:synccash/features/chatbot/presentation/screens/chat_screen.dart';

// ── Page transition helper ────────────────────────────────────────────────────

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

// ── Splash notifier ───────────────────────────────────────────────────────────
// Tracks whether the splash animation has finished.
// GoRouter waits for this before redirecting away from '/'.

class _SplashNotifier extends ChangeNotifier {
  bool _done = false;
  bool get done => _done;

  void complete() {
    if (_done) return;
    _done = true;
    notifyListeners(); // triggers GoRouter to re-evaluate redirect
  }
}

final _splashNotifierProvider = Provider<_SplashNotifier>((ref) {
  return _SplashNotifier();
});

// ── Auth notifier ─────────────────────────────────────────────────────────────

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
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

// ── Router ────────────────────────────────────────────────────────────────────

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier  = ref.watch(_authNotifierProvider);
  final splashNotifier = ref.watch(_splashNotifierProvider);

  return GoRouter(
    navigatorKey: NavigationService.navigatorKey,
    initialLocation: RouteConstants.splash,

    // Both auth changes AND splash completion trigger redirect re-evaluation
    refreshListenable: Listenable.merge([authNotifier, splashNotifier]),

    redirect: (BuildContext context, GoRouterState state) {
      // ── Wait for splash animation to finish first ────────────────────────
      // This prevents the redirect from firing mid-animation even if auth
      // resolves quickly (e.g. cached session on reload).
      if (!splashNotifier.done) return null;

      final authState = ref.read(authProvider);

      // ── Wait for auth to resolve ─────────────────────────────────────────
      if (authState.isLoading) return null;

      final user     = authState.asData?.value;
      final loggedIn = user != null;

      final isAuthRoute =
          state.matchedLocation == RouteConstants.login ||
          state.matchedLocation == RouteConstants.signup;

      // Not logged in → always go to login
      if (!loggedIn && !isAuthRoute) return RouteConstants.login;

      // Logged in but on auth screen → go to dashboard or pairing
      if (loggedIn && isAuthRoute) {
        return user.currentCashbookId != null
            ? RouteConstants.dashboard
            : RouteConstants.pairing;
      }

      // Logged in and still on splash → go to dashboard or pairing
      if (loggedIn && state.matchedLocation == RouteConstants.splash) {
        return user.currentCashbookId != null
            ? RouteConstants.dashboard
            : RouteConstants.pairing;
      }

      return null;
    },

    routes: [
      // ── Splash ─────────────────────────────────────────────────────────────
      GoRoute(
        path: RouteConstants.splash,
        pageBuilder: (context, state) => _fadePage(
          state: state,
          child: SplashScreen(
            // When animation ends, mark splash done → redirect fires
            onComplete: () => ref.read(_splashNotifierProvider).complete(),
          ),
          duration: const Duration(milliseconds: 0), // no fade over splash
        ),
      ),

      // ── Auth ────────────────────────────────────────────────────────────────
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

      // ── App ─────────────────────────────────────────────────────────────────
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
  path: RouteConstants.chat,
  builder: (context, state) => const ChatScreen(),
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