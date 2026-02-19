const CACHE_NAME = 'pingy-v1-1-2-shell';
const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/pingy-icon-192.png',
  '/pingy-icon-512.png',
  '/favicon.png',
  '/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }

          return Promise.resolve();
        }),
      ),
    ),
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  if (request.method !== 'GET') {
    return;
  }

  if (request.url.includes('/api/') || request.url.includes('/socket.io/')) {
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) {
        return cached;
      }

      return fetch(request)
        .then((response) => {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, responseClone));
          return response;
        })
        .catch(() => caches.match('/index.html'));
    }),
  );
});

const buildConversationUrl = (conversationId) => {
  const url = new URL('/', self.location.origin);

  if (conversationId) {
    url.searchParams.set('conversationId', String(conversationId));
  }

  return url.toString();
};

self.addEventListener('push', (event) => {
  let payload = {};

  try {
    payload = event.data?.json() || {};
  } catch {
    payload = {
      body: event.data?.text() || 'New message',
    };
  }

  const conversationId = payload.conversationId || null;
  const title = payload.title || payload.senderUsername || 'Pingy';
  const body = payload.body || 'New message';
  const url = payload.url || buildConversationUrl(conversationId);

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/pingy-icon-192.png',
      badge: '/pingy-icon-192.png',
      tag: payload.tag || (conversationId ? `pingy-conversation-${conversationId}` : 'pingy-message'),
      data: {
        conversationId,
        url,
      },
      renotify: true,
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const conversationId = event.notification?.data?.conversationId || null;
  const targetUrl = event.notification?.data?.url || buildConversationUrl(conversationId);

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async (clients) => {
      if (clients.length > 0) {
        const targetClient = clients[0];

        if ('navigate' in targetClient) {
          await targetClient.navigate(targetUrl);
        }

        if ('focus' in targetClient) {
          await targetClient.focus();
        }

        return;
      }

      await self.clients.openWindow(targetUrl);
    }),
  );
});
