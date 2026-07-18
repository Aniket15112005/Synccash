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
    // Web/PWA: auto-detect when the browser needs long-polling instead of
    // WebChannel streaming. Some networks (corporate proxies, some mobile
    // carriers) and iOS Safari/PWA's WKWebView silently buffer or kill the
    // streaming connection Firestore normally uses, which is one of the
    // causes behind screens (like Bills) getting permanently stuck on
    // their loading spinner. Auto-detect long-polling falls back
    // automatically only when needed, so it's safe to always enable.
    FirebaseFirestore.instance.settings = const Settings(
      webExperimentalAutoDetectLongPolling: true,
    );

    // NOTE: Settings.persistenceEnabled (used above for mobile) has NO
    // effect on Flutter Web — it's silently ignored. Web needs this
    // separate call instead, or Firestore only ever has an in-memory
    // cache that starts EMPTY on every cold PWA launch. That's what was
    // causing the app to land on the pairing screen right after login on
    // iOS PWA (currentCashbookId looked missing because there was nothing
    // to read it from before the network caught up), and the "client
    // offline" error when submitting a pairing code moments later.
    try {
      await FirebaseFirestore.instance.enablePersistence(
        const PersistenceSettings(synchronizeTabs: true),
      );
    } catch (e) {
      // Can throw if persistence was already enabled in another tab, or
      // isn't supported in this browser context — safe to ignore, the app
      // just falls back to in-memory cache in that case.
      if (kDebugMode) debugPrint('⚠️ enablePersistence failed: $e');
    }
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