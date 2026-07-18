import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:synccash/app/app.dart';
import 'package:synccash/core/services/firestore_reconnect_service.dart';
import 'package:synccash/core/services/notification_service.dart';
import 'package:synccash/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load .env (API keys)
  await dotenv.load(fileName: 'app.env');

  // 2. Firebase core
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. Firestore settings.
  if (!kIsWeb) {
    // Offline persistence (mobile only).
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024,
    );
  } else {
    // Web/PWA: FORCE long-polling instead of WebChannel streaming.
    // iOS Safari / WKWebView silently kills the streaming WebChannel connection
    // that Firestore uses by default — auto-detect is not reliable enough
    // because iOS drops the connection before the SDK can detect it needs to
    // switch. ForceLongPolling is the only mode that works consistently on
    // iOS PWA (added to Home Screen), fixing the "client offline" error on
    // login and the pairing-screen redirect caused by missing cashbookId.
    FirebaseFirestore.instance.settings = const Settings(
      webExperimentalForceLongPolling: true,
    );
  }

  // 3b. Force Firestore to re-establish its realtime connection whenever
  // the app returns to the foreground after being backgrounded — see
  // FirestoreReconnectService for the full explanation. This is the other
  // half of the fix for screens sometimes getting stuck on loading.
  FirestoreReconnectService.instance.start();

  // 4. Lock to portrait (mobile only)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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

  runApp(const ProviderScope(child: SyncCashApp()));

  // 6. Notifications — runs AFTER runApp so app shows instantly
  NotificationService.initialize().catchError((e) {
    if (kDebugMode) debugPrint('⚠️ NotificationService init error: $e');
  });
}