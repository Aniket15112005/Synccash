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
    // Web/PWA: enable persistence AND auto-detect long-polling in a single
    // Settings assignment.
    //
    // IMPORTANT: this used to be two separate steps — a `.settings =`
    // assignment followed by a separate `enablePersistence()` call. As of
    // the current cloud_firestore_web package, `.settings =` alone already
    // configures a cache under the hood (memory cache by default). That
    // means a later `enablePersistence()` call always conflicts with the
    // cache the settings assignment already specified, throwing
    // `[cloud_firestore/failed-precondition] SDK cache is already
    // specified.` — on every launch, not just hot restarts.
    //
    // Passing `persistenceEnabled: true` directly here enables the
    // persistent (IndexedDB) cache as part of that single assignment, so
    // there's no second call left to conflict with. This also fixes the
    // original problem this code was written for: Firestore only ever
    // having an in-memory cache that starts EMPTY on every cold PWA
    // launch, which was causing the app to land on the pairing screen
    // right after login (currentCashbookId looked missing because there
    // was nothing to read it from before the network caught up), and the
    // "client offline" error when submitting a pairing code moments later.
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        webExperimentalAutoDetectLongPolling: true,
      );
    } catch (e) {
      // Can throw if this browser context doesn't support persistence
      // (e.g. private browsing) — safe to ignore, Firestore falls back to
      // an in-memory cache in that case.
      if (kDebugMode) debugPrint('⚠️ Firestore settings failed: $e');
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