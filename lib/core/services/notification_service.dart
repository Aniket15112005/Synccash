import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          if (kDebugMode) {
            print('Received foreground notification: ${message.notification?.title}');
          }
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error initializing tracking notifications: $e');
    }
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }
}