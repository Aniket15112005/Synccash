// lib/core/services/fcm_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    debugPrint('📩 Background FCM: ${message.notification?.title}');
  }
}

class FCMService {
  FCMService._();

  static const _vapidKey =
      'BK3kZeMAeYrM2tJoSPJq54oP9wtN8JDhNd3tHK8xwXSaazTjSR6ktCqEXLFo7S13dELPG71oifpOv5f6R3IBuKA';

  static bool _initialized = false;

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Public API ──────────────────────────────────────────────────────────

  static Future<void> initFCM() async {
    if (_initialized) return; // guard against double-init

    // Register background handler on mobile only (web uses service worker)
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    // Request permission (required on iOS & web; no-op on Android)
    final settings = await _messaging.requestPermission(
      alert:         true,
      badge:         true,
      sound:         true,
      announcement:  false,
      carPlay:       false,
      criticalAlert: false,
      provisional:   false,
    );
    if (kDebugMode) {
      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');
    }

    // iOS: obtain APNs token first (skip gracefully on simulator / timeout)
    if (!kIsWeb) {
      try {
        await _messaging
            .getAPNSToken()
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Simulator or entitlement missing — safe to ignore
      }
    }

    // Fetch FCM token
    final token = await _getToken();
    if (kDebugMode) {
      debugPrint('================================');
      debugPrint('FCM TOKEN (${kIsWeb ? "web" : "mobile"}): $token');
      debugPrint('================================');
    }
    if (token != null) await _saveToken(token);

    // Attach listeners only once
    _initialized = true;

    _messaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) debugPrint('🔄 FCM token refreshed');
      await _saveToken(newToken);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (kDebugMode) {
        debugPrint('🔔 Opened from notification: ${message.data}');
      }
    });

    // Handle cold-start notification
    final initial = await _messaging.getInitialMessage();
    if (initial != null && kDebugMode) {
      debugPrint('🚀 Launched via notification: ${initial.data}');
    }
  }

  static Future<void> removeToken() async {
    try {
      final user  = FirebaseAuth.instance.currentUser;
      final token = await _getToken();
      if (user == null || token == null) return;

      await Future.wait([
        _firestore.collection('users').doc(user.uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }),
        _messaging.deleteToken(),
      ]);

      _initialized = false; // allow re-init on next login
      if (kDebugMode) debugPrint('🗑️ FCM token removed');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService.removeToken error: $e');
    }
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  static Future<String?> _getToken() async {
    try {
      return kIsWeb
          ? await _messaging.getToken(vapidKey: _vapidKey)
          : await _messaging.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._getToken error: $e');
      return null;
    }
  }

  static Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).set(
        {
          'fcmTokens':       FieldValue.arrayUnion([token]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (kDebugMode) debugPrint('✅ FCM token saved for ${user.uid}');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._saveToken error: $e');
    }
  }
}