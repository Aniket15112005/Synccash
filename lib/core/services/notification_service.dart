import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;

  static Future<void> initialize() async {
    try {
      NotificationSettings settings =
          await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus ==
          AuthorizationStatus.authorized) {

        // Get FCM Token
        String? token = await _messaging.getToken();

        if (kDebugMode) {
          print('========================');
          print('FCM TOKEN:');
          print(token);
          print('========================');
        }

        // Foreground notifications
        FirebaseMessaging.onMessage.listen(
          (RemoteMessage message) {
            if (kDebugMode) {
              print(
                'Received foreground notification: '
                '${message.notification?.title}',
              );

              print(
                'Notification body: '
                '${message.notification?.body}',
              );

              print(
                'Notification data: '
                '${message.data}',
              );
            }
          },
        );

        // App opened from notification
        FirebaseMessaging.onMessageOpenedApp.listen(
          (RemoteMessage message) {
            if (kDebugMode) {
              print(
                'Notification clicked: '
                '${message.notification?.title}',
              );
            }

            // TODO:
            // Navigate to transaction screen
            // or cashbook screen
          },
        );

        // App launched from terminated state
        RemoteMessage? initialMessage =
            await _messaging.getInitialMessage();

        if (initialMessage != null) {
          if (kDebugMode) {
            print(
              'App opened from terminated state '
              'via notification',
            );
          }
        }

      } else {
        if (kDebugMode) {
          print('Notification permission denied');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          'Error initializing notifications: $e',
        );
      }
    }
  }

  static Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting FCM token: $e');
      }
      return null;
    }
  }

  static Future<void> refreshTokenListener() async {
    _messaging.onTokenRefresh.listen(
      (String newToken) {
        if (kDebugMode) {
          print('FCM Token Refreshed:');
          print(newToken);
        }

        // TODO:
        // Update Firestore with new token
      },
    );
  }
}