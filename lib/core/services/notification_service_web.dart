// lib/core/services/notification_service_web.dart
import 'dart:js_interop';

@JS('Notification')
extension type _JsNotification._(JSObject _) implements JSObject {
  external static String get permission;
  external factory _JsNotification(String title, _JsNotificationOptions options);
}

@JS()
extension type _JsNotificationOptions._(JSObject _) implements JSObject {
  external factory _JsNotificationOptions({String body, String icon});
}

// Keep a reference so the browser doesn't GC it before showing.
_JsNotification? _activeNotification;

void showWebNotification(String title, String body) {
  if (_JsNotification.permission == 'granted') {
    _activeNotification = _JsNotification(
      title,
      _JsNotificationOptions(body: body, icon: '/icons/Icon-192.png'),
    );
  }
}