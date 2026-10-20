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

// الرسائل بيانات فقط، فهذا هو العارض الوحيد للإشعار (لا تكرار).
firebase.messaging().onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const options = {
    body: data.body || 'رسالة جديدة',
    icon: '/icons/Icon-192.png',
    data,
  };
  // نفس الوسم يستبدل الإشعار السابق (محادثة واحدة = إشعار واحد يتحدّث).
  if (data.tag) {
    options.tag = data.tag;
    options.renotify = true;
  }
  return self.registration.showNotification(data.title || 'Haigram', options);
});

function targetFor(data) {
  const target = new URL('/', self.location.origin);
  if (data.conversationId && data.senderUid) {
    target.searchParams.set('chat', data.conversationId);
    target.searchParams.set('from', data.senderUid);
  } else if (data.postId) {
    target.searchParams.set('p', data.postId);
  }
  return target.toString();
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = targetFor(event.notification.data || {});
  event.waitUntil((async () => {
    const windows = await clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    const existing = windows.find(
      (client) => new URL(client.url).origin === self.location.origin,
    );
    if (existing) {
      try {
        await existing.focus();
        await existing.navigate(url);
        return;
      } catch (_) {
        // لا يمكن توجيه النافذة: نفتح واحدة جديدة.
      }
    }
    await clients.openWindow(url);
  })());
});
