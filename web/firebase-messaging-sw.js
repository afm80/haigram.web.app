importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '__FB_API_KEY__',
  appId: '__FB_APP_ID__',
  messagingSenderId: '__FB_SENDER_ID__',
  projectId: '__FB_PROJECT_ID__',
  authDomain: '__FB_AUTH_DOMAIN__',
  storageBucket: '__FB_STORAGE_BUCKET__',
});

firebase.messaging().onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  self.registration.showNotification(notification.title || 'Haigram', {
    body: notification.body || 'رسالة جديدة',
    icon: notification.icon || '/icons/Icon-192.png',
    data: payload.data || {},
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const target = new URL('/', self.location.origin);
  if (data.conversationId && data.senderUid) {
    target.searchParams.set('chat', data.conversationId);
    target.searchParams.set('from', data.senderUid);
  }
  event.waitUntil(clients.openWindow(target.toString()));
});
