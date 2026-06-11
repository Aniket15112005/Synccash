// lib/core/navigation/navigation_service.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NavigationService {
  NavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static void goToDashboard() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      GoRouter.of(context).go('/dashboard');
    }
  }
}