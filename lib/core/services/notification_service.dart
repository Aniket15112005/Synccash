// lib/core/services/notification_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const _kChannelId   = 'synccash_transactions';
  static const _kChannelName = 'SyncCash Transactions';
  static const _kChannelDesc =
      'Income and expense alerts from your shared cashbook.';

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    _kChannelId,
    _kChannelName,
    description:     _kChannelDesc,
    importance:      Importance.high,
    enableVibration: true,
    playSound:       true,
  );

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request permission on ALL platforms including web / iOS PWA
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Android: create high-priority notification channel
    if (!kIsWeb) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          if (kDebugMode) {
            print('🔔 Notification tapped, payload: ${response.payload}');
          }
        },
      );

      // Foreground heads-up banner (mobile only — SW handles web)
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    }

    if (kDebugMode) print('✅ NotificationService initialized');
  }

  static void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;

    _plugin.show(
      message.hashCode,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDesc,
          importance:         Importance.high,
          priority:           Priority.high,
          enableVibration:    true,
          playSound:          true,
          styleInformation:   BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['cashbookId'],
    );
  }
}