// web/firebase-messaging-sw.js
// Enables background push notifications on Web and iOS PWA (iOS 16.4+)

importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey:            "AIzaSyA8PmfMdBr1jPFrmatUOxDNF3Jqhzf920Q",
  authDomain:        "synccash-d9c04.firebaseapp.com",
  projectId:         "synccash-d9c04",
  storageBucket:     "synccash-d9c04.firebasestorage.app",
  messagingSenderId: "638377195713",
  appId:             "1:638377195713:web:9bc8b92da1025bbfe97c40"
});

const messaging = firebase.messaging();

// Show notification when app is in background or closed
messaging.onBackgroundMessage(function(payload) {
  const title = payload.notification?.title || 'SyncCash';
  const body  = payload.notification?.body  || 'New transaction added';

  self.registration.showNotification(title, {
    body:    body,
    icon:    '/icons/Icon-192.png',
    badge:   '/icons/Icon-192.png',
    vibrate: [200, 100, 200],
    tag:     'synccash-transaction',
    renotify: true,
    data:    payload.data || {},
  });
});

// Open or focus the app when notification is tapped
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function(clientList) {
        for (const client of clientList) {
          if (client.url && 'focus' in client) {
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow('/');
        }
      })
  );
});