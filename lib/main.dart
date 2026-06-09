import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/app/app.dart';
import 'package:synccash/core/services/notification_service.dart';
import 'package:synccash/firebase_options.dart'; // Safe multi-platform compilation config

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Dynamically inject platform configuration parameters to satisfy both Mobile and Web layers
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Isolate mobile-only persistence optimizations to prevent Web (IndexedDB) initialization faults
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    // Initialize push notifications on native hardware platforms
    await NotificationService.initialize();
  } else {
    // Standard web safe initialization profile
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }

  // Force upright orientation standard across phone devices
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Establish a premium translucent edge-to-edge UI overlay layout
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0A0E17), // Matches AppColors.background
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    const ProviderScope(
      child: SyncCashApp(),
    ),
  );
}