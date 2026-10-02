// Service worker: makes the site installable, keeps the app shell available offline,
// and shows notifications (required on Android). Live scores are never cached —
// requests to other origins (ESPN, fonts) pass straight through.
const CACHE = 'cricket-live-v3';
const SHELL = ['/', '/styles.css', '/app.js', '/features.js', '/lib/data.js', '/lib/espn.js', '/lib/scorecard.js',
  '/manifest.webmanifest', '/favicon.svg', '/icons/icon-192.png', '/icons/icon-512.png', '/icons/maskable-192.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).catch(() => {}).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()));
});

// Network first (so new deployments show up immediately), cache as offline fallback.
self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;
  event.respondWith(
    fetch(req).then((res) => {
      if (res.ok && !url.pathname.endsWith('version.json')) {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
      }
      return res;
    }).catch(() => caches.match(req).then((hit) => hit ?? caches.match('/'))));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data?.url ?? '/';
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((wins) => {
    const existing = wins.find((w) => new URL(w.url).origin === self.location.origin);
    if (existing) { existing.navigate(target).catch(() => {}); return existing.focus(); }
    return self.clients.openWindow(target);
  }));
});
