import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:synccash/app/app.dart';
import 'package:synccash/core/services/notification_service.dart';
import 'package:synccash/firebase_options.dart';
import 'package:synccash/features/cashbook/presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase core
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Firestore offline persistence (mobile only)
  // FIX: Cap cache at 100 MB to prevent storage exhaustion on low-end devices.
  // CACHE_SIZE_UNLIMITED was removed — Firestore can grow unboundedly with it.
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024, // 100 MB cap
    );
  }

  // 3. Lock to portrait (mobile only)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // 4. Status/nav bar styling (mobile only)
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF0A0E17),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  // FIX: Removed the raw authStateChanges().listen() from here.
  // FCM initialization is now handled inside a Riverpod provider that
  // watches authProvider — no memory leak, no fire-and-forget await.
  // See: lib/core/services/fcm_provider.dart (create this file below).

  runApp(const ProviderScope(child: _RootApp()));

  // 5. Notifications — runs AFTER runApp so splash shows instantly.
  NotificationService.initialize().catchError((e) {
    if (kDebugMode) debugPrint('⚠️ NotificationService init error: $e');
  });
}

class _RootApp extends StatefulWidget {
  const _RootApp();

  @override
  State<_RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<_RootApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashScreen(
          onComplete: () => setState(() => _splashDone = true),
        ),
      );
    }
    return const SyncCashApp();
  }
}