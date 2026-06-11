import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('🌙 Background message: ${message.notification?.title}');
  }
}

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> initFCM() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    if (!kIsWeb) {
      await _messaging.getAPNSToken();
    }

    final token = await _messaging.getToken();
    if (kDebugMode) {
      print('========================');
      print('FCM TOKEN: $token');
      print('========================');
    }
    if (token != null) await _saveToken(token);

    _messaging.onTokenRefresh.listen((newToken) async {
      await _saveToken(newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      if (kDebugMode) {
        print('📩 Foreground: ${message.notification?.title}');
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (kDebugMode) print('🔔 Notification tapped: ${message.data}');
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null && kDebugMode) {
      print('🚀 Launched from notification: ${initialMessage.data}');
    }
  }

  static Future<void> removeToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await _messaging.getToken();
      if (token == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });

      await _messaging.deleteToken();
      if (kDebugMode) print('🗑️ FCM token removed');
    } catch (e) {
      if (kDebugMode) print('❌ removeToken error: $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (kDebugMode) {
        print('Current user when saving: ${user?.uid ?? "NULL - not logged in"}');
      }

      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (kDebugMode) print('✅ FCM token saved');
    } catch (e) {
      if (kDebugMode) print('❌ _saveToken error: $e');
    }
  }
}