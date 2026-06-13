// web/firebase-messaging-sw.js
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey:            'AIzaSyA8PmfMdBr1jPFrmatUOxDNF3Jqhzf920Q',
  authDomain:        'synccash-d9c04.firebaseapp.com',
  projectId:         'synccash-d9c04',
  storageBucket:     'synccash-d9c04.firebasestorage.app',
  messagingSenderId: '638377195713',
  appId:             '1:638377195713:web:9bc8b92da1025bbfe97c40',
});

const messaging = firebase.messaging();

self.addEventListener('install',  () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(clients.claim()));

// Background push notifications.
// IMPORTANT: This handler is ONLY called when the PWA is closed or not focused.
// When the PWA is open and focused, Flutter's onMessage handler fires instead.
// We check for focused clients to be safe and avoid double notifications.
messaging.onBackgroundMessage(async (payload) => {
  // If any PWA window is visible and focused, let the Flutter foreground
  // handler deal with it — returning here prevents a double notification.
  const allClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
  for (const client of allClients) {
    if (client.visibilityState === 'visible') {
      console.log('[SW] PWA is focused — skipping SW notification, Flutter handler will show it');
      return;
    }
  }

  const title = payload.data?.title || 'SyncCash';
  const body  = payload.data?.body  || '';

  // Unique tag per notification so rapid events don't collapse each other
  const tag = 'synccash-' + (payload.data?.cashbookId || 'tx') + '-' + Date.now();

  return self.registration.showNotification(title, {
    body,
    icon:    '/icons/Icon-192.png',
    badge:   '/icons/Icon-192.png',
    tag,
    vibrate: [200, 100, 200],
    data:    payload.data || {},
  });
});

// Notification tap → focus or open the PWA
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((list) => {
        for (const client of list) {
          if ('focus' in client) return client.focus();
        }
        return clients.openWindow('/');
      })
  );
});