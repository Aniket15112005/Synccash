// lib/core/services/notification_service_web.dart
// Used only on web builds. Shows a system notification via the JS Notification API
// when the PWA is in the foreground (the SW handles background automatically).

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

void showWebNotification(String title, String body) {
  if (_JsNotification.permission == 'granted') {
    _JsNotification(
      title,
      _JsNotificationOptions(body: body, icon: '/icons/Icon-192.png'),
    );
  }
}