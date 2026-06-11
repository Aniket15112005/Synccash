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

  // 2. Firestore offline persistence
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes:     Settings.CACHE_SIZE_UNLIMITED,
    );
  } else {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }

  // 3. Notifications: permission + Android channel + foreground handler
  //    Safe to call before login — does NOT touch tokens.
  if (!kIsWeb) {
    await NotificationService.initialize();
  }

  // 4. FCM token lifecycle — only after the user is confirmed logged in.
  //    Guard prevents calling initFCM() more than once per session.
  bool fcmReady = false;
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null && !fcmReady) {
      fcmReady = true;
      if (kDebugMode) print('👤 Logged in: ${user.uid} — initializing FCM…');
      await FCMService.initFCM();
    }
    if (user == null) {
      fcmReady = false; // reset so next login re-initializes
    }
  });

  // 5. Lock to portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 6. Status/nav bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor:                   Colors.transparent,
      statusBarIconBrightness:          Brightness.light,
      statusBarBrightness:              Brightness.dark,
      systemNavigationBarColor:         Color(0xFF0A0E17),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: _RootApp()));
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