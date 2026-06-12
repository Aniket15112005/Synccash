// lib/core/services/fcm_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Key used to persist the last saved token across app restarts
  static const _kPrefKey = 'fcm_last_token';

  static bool _initialized = false;

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Public API ──────────────────────────────────────────────────────────

  static Future<void> initFCM() async {
    if (_initialized) return;

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

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

    if (!kIsWeb) {
      try {
        await _messaging
            .getAPNSToken()
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Simulator or missing entitlement — safe to ignore
      }
    }

    final token = await _getToken();
    if (kDebugMode) {
      debugPrint('================================');
      debugPrint('FCM TOKEN (${kIsWeb ? "web" : "mobile"}): $token');
      debugPrint('================================');
    }
    if (token != null) await _saveToken(token);

    _initialized = true;

    // When FCM issues a new token, remove the old one first
    _messaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) debugPrint('🔄 FCM token refreshed');
      await _replaceToken(newToken);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (kDebugMode) {
        debugPrint('🔔 Opened from notification: ${message.data}');
      }
    });

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

      final prefs = await SharedPreferences.getInstance();

      await Future.wait([
        _firestore.collection('users').doc(user.uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }),
        _messaging.deleteToken(),
      ]);

      await prefs.remove(_kPrefKey);
      _initialized = false;
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

  /// Called on first init — removes the previously saved token (from last
  /// session) before adding the new one, so stale tokens never accumulate.
  static Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs    = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_kPrefKey);

      final userRef = _firestore.collection('users').doc(user.uid);

      // Remove the previous token for this device if it changed
      if (oldToken != null && oldToken != token) {
        await userRef.update({
          'fcmTokens': FieldValue.arrayRemove([oldToken]),
        });
        if (kDebugMode) {
          debugPrint('🗑️ Removed old token: ${oldToken.substring(0, 20)}...');
        }
      }

      // Save the fresh token
      await userRef.set(
        {
          'fcmTokens':       FieldValue.arrayUnion([token]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Persist so we can remove it next session
      await prefs.setString(_kPrefKey, token);

      if (kDebugMode) debugPrint('✅ FCM token saved for ${user.uid}');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._saveToken error: $e');
    }
  }

  /// Called when FCM refreshes the token mid-session (onTokenRefresh).
  static Future<void> _replaceToken(String newToken) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs    = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_kPrefKey);

      final userRef = _firestore.collection('users').doc(user.uid);

      if (oldToken != null && oldToken != newToken) {
        await userRef.update({
          'fcmTokens': FieldValue.arrayRemove([oldToken]),
        });
      }

      await userRef.set(
        {
          'fcmTokens':       FieldValue.arrayUnion([newToken]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await prefs.setString(_kPrefKey, newToken);

      if (kDebugMode) debugPrint('✅ FCM token replaced for ${user.uid}');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._replaceToken error: $e');
    }
  }
}
