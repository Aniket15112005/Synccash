// lib/core/services/fcm_service.dart

import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synccash/core/services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final title = message.data['title'] ?? message.notification?.title;
  final body  = message.data['body']  ?? message.notification?.body;
  if (title == null) return;

  final plugin = FlutterLocalNotificationsPlugin();

  // Must create the channel in the background isolate too (Android 8+)
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'synccash_transactions',
        'SyncCash Transactions',
        description: 'Income and expense alerts from your shared cashbook.',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ));

  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  await plugin.show(
    message.hashCode,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'synccash_transactions',
        'SyncCash Transactions',
        channelDescription: 'Income and expense alerts from your shared cashbook.',
        importance:      Importance.high,
        priority:        Priority.high,
        enableVibration: true,
        playSound:       true,
      ),
    ),
  );
}

class FCMService {
  FCMService._();

  static const _vapidKey =
      'BK3kZeMAeYrM2tJoSPJq54oP9wtN8JDhNd3tHK8xwXSaazTjSR6ktCqEXLFo7S13dELPG71oifpOv5f6R3IBuKA';

  static const _kPrefKey = 'fcm_last_token';
  static bool _initialized = false;

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore  _firestore = FirebaseFirestore.instance;

  static Future<void> initFCM() async {
    if (_initialized) return;

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    // FIX: Initialize NotificationService here so the Android channel is
    // created and foreground messages are wired up before any notification arrives.
    await NotificationService.initialize();

    NotificationSettings settings;
    try {
      settings = await _messaging.requestPermission(
        alert:         true,
        badge:         true,
        sound:         true,
        announcement:  false,
        carPlay:       false,
        criticalAlert: false,
        provisional:   false,
      ).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      if (kDebugMode) debugPrint('⚠️ FCM: permission request timed out — continuing without notifications');
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ FCM: permission request failed: $e');
      return;
    }

    if (kDebugMode) {
      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');
    }

    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      try {
        await _messaging.getAPNSToken().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    String? token;
    try {
      token = await _getToken().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      if (kDebugMode) debugPrint('⚠️ FCM: getToken timed out — will retry on next launch');
      return;
    }

    if (kDebugMode) {
      debugPrint('================================');
      debugPrint('FCM TOKEN (${kIsWeb ? "web/PWA" : "mobile"}): $token');
      debugPrint('================================');
    }
    if (token != null) await _saveToken(token);

    _initialized = true;

    _messaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) debugPrint('🔄 FCM token refreshed');
      await _replaceToken(newToken);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (kDebugMode) debugPrint('🔔 Opened from notification: ${message.data}');
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

      if (_isIOSOrPWA) {
        _clearReceiverTokensOnCashbook(user.uid).ignore();
      }

      await prefs.remove(_kPrefKey);
      _initialized = false;
      if (kDebugMode) debugPrint('🗑️ FCM token removed');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService.removeToken error: $e');
    }
  }

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

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS || Platform.isMacOS) return 'ios';
    return 'android';
  }

  static bool get _isIOSOrPWA {
    if (kIsWeb) return true;
    return Platform.isIOS || Platform.isMacOS;
  }

  static Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs    = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_kPrefKey);
      final userRef  = _firestore.collection('users').doc(user.uid);

      if (oldToken != null && oldToken != token) {
        await userRef.update({
          'fcmTokens': FieldValue.arrayRemove([oldToken]),
        });
      }

      await userRef.set(
        {
          'fcmTokens':       FieldValue.arrayUnion([token]),
          'platform':        _platform,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await prefs.setString(_kPrefKey, token);

      if (_isIOSOrPWA) {
        _cacheReceiverOnCashbook(user.uid, token).ignore();
      }

      if (kDebugMode) {
        debugPrint('✅ FCM token saved for ${user.uid} (platform: $_platform)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._saveToken error: $e');
    }
  }

  static Future<void> _replaceToken(String newToken) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs    = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_kPrefKey);
      final userRef  = _firestore.collection('users').doc(user.uid);

      if (oldToken != null && oldToken != newToken) {
        await userRef.update({
          'fcmTokens': FieldValue.arrayRemove([oldToken]),
        });
      }

      await userRef.set(
        {
          'fcmTokens':       FieldValue.arrayUnion([newToken]),
          'platform':        _platform,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await prefs.setString(_kPrefKey, token);

      if (_isIOSOrPWA) {
        _cacheReceiverOnCashbook(user.uid, newToken).ignore();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._replaceToken error: $e');
    }
  }

  static Future<void> _cacheReceiverOnCashbook(
      String userId, String token) async {
    try {
      String? cashbookId;
      for (var attempt = 0; attempt < 3; attempt++) {
        cashbookId = await _getCurrentCashbookId(userId);
        if (cashbookId != null) break;
        await Future.delayed(Duration(seconds: attempt + 1));
      }
      if (cashbookId == null) return;

      await _firestore.collection('cashbooks').doc(cashbookId).set(
        {
          'iosReceiverId':     userId,
          'iosReceiverTokens': [token],
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._cacheReceiverOnCashbook error: $e');
    }
  }

  static Future<void> _clearReceiverTokensOnCashbook(String userId) async {
    try {
      final cashbookId = await _getCurrentCashbookId(userId);
      if (cashbookId == null) return;
      await _firestore
          .collection('cashbooks')
          .doc(cashbookId)
          .update({'iosReceiverTokens': []});
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCMService._clearReceiverTokensOnCashbook error: $e');
    }
  }

  static Future<String?> _getCurrentCashbookId(String userId) async {
    try {
      final snap = await _firestore.collection('users').doc(userId).get();
      final id   = snap.data()?['currentCashbookId'] as String?;
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }
}