// lib/core/services/notification_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_stub.dart' as web_notify;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const _kChannelId   = 'synccash_transactions';
  static const _kChannelName = 'SyncCash Transactions';
  static const _kChannelDesc =
      'Income and expense alerts from your shared cashbook.';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    _kChannelId,
    _kChannelName,
    description:     _kChannelDesc,
    importance:      Importance.high,
    enableVibration: true,
    playSound:       true,
  );

  // ─── Public API ─────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      // Background messages are handled by firebase-messaging-sw.js.
      // Foreground messages (PWA is open) are handled here via JS Notification API.
      FirebaseMessaging.onMessage.listen(_onForegroundMessageWeb);
      if (kDebugMode) debugPrint('✅ NotificationService initialized (web/PWA)');
      return;
    }

    // ── Android: create the high-importance notification channel ──────────────
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // ── Initialize flutter_local_notifications ────────────────────────────────
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permissions are requested by FCMService.initFCM() — not here.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (kDebugMode) {
          debugPrint('🔔 Notification tapped — payload: ${response.payload}');
        }
        // TODO: navigate to cashbook using response.payload (cashbookId)
      },
    );

    // ── Foreground messages while app is open ─────────────────────────────────
    FirebaseMessaging.onMessage.listen(_onForegroundMessageMobile);

    if (kDebugMode) debugPrint('✅ NotificationService initialized (mobile)');
  }

  // ─── Web foreground handler ──────────────────────────────────────────────────
  // Called when the PWA is open and in focus.
  // The browser suppresses service-worker notifications when the page is focused,
  // so we call the JS Notification API directly via the platform shim.
  // Background messages (PWA minimised / closed) are handled by the SW.
  static void _onForegroundMessageWeb(RemoteMessage message) {
    final title = message.data['title'] ??
        message.notification?.title ??
        'SyncCash';
    final body = message.data['body'] ??
        message.notification?.body ??
        '';

    if (kDebugMode) debugPrint('🔔 [Web foreground] $title — $body');

    // Show a real OS notification via the JS Notification API.
    // The Firestore real-time stream in your cashbook provider will also
    // automatically refresh the transaction list — no extra action needed.
    web_notify.showWebNotification(title, body);
  }

  // ─── Mobile foreground handler ───────────────────────────────────────────────
  // Called on Android / iOS native when the app is open and in the foreground.
  // Background messages are handled by firebaseMessagingBackgroundHandler
  // in fcm_service.dart (separate isolate).
  static void _onForegroundMessageMobile(RemoteMessage message) {
    final title = message.data['title'] ?? message.notification?.title;
    final body  = message.data['body']  ?? message.notification?.body;
    if (title == null) return;

    _plugin.show(
      message.hashCode,
      title,
      body,
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