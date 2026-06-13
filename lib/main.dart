import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:synccash/app/app.dart';
import 'package:synccash/core/services/notification_service.dart';
import 'package:synccash/core/services/fcm_service.dart';
import 'package:synccash/firebase_options.dart';
import 'package:synccash/features/cashbook/presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase core
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Firestore offline persistence (mobile only)
  // Web: Firebase handles IndexedDB persistence automatically
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // 3. FCM token lifecycle — only after user is confirmed logged in
  bool fcmReady = false;
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null && !fcmReady) {
      fcmReady = true;
      if (kDebugMode) print('👤 Logged in: ${user.uid} — initializing FCM…');
      await FCMService.initFCM();
    }
    if (user == null) {
      fcmReady = false;
    }
  });

  // 4. Lock to portrait (mobile only)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);
  }

  // 5. Status/nav bar styling (mobile only)
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

  runApp(const ProviderScope(child: _RootApp()));

  // 6. Notifications — runs AFTER runApp so splash shows instantly
  // Never blocks the UI. Runs in background on all platforms.
  NotificationService.initialize().catchError((_) {});
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