import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/router/app_router.dart';
import 'package:synccash/app/theme/app_theme.dart';
import 'package:synccash/core/services/fcm_provider.dart'; // ← ADD import


class SyncCashApp extends ConsumerWidget {
  const SyncCashApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(fcmInitProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'SyncCash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}