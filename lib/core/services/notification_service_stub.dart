// lib/core/services/notification_service_stub.dart
// No-op stub used on Android / iOS native builds.
// The mobile foreground handler in NotificationService uses flutter_local_notifications
// directly, so this function intentionally does nothing.

void showWebNotification(String title, String body) {}