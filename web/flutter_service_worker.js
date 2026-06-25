// Kill-switch service worker.
//
// The app is now built with --pwa-strategy=none (no service worker), but older
// installs (especially iOS web-clips) still have the previous Flutter service
// worker registered and keep serving a stale cached bundle. The browser checks
// this file for updates on navigation; serving this self-destruct worker makes
// those stale installs clear their caches, unregister, and reload with the
// fresh build. New visitors never register a worker, so they never fetch this.
// Activate immediately, even if the old worker is still controlling a page.
self.addEventListener('install', function (event) {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    // 1. Delete every cache the old worker created.
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
    } catch (_) {}
    // 2. Take control of all open pages so we can reload them.
    try { await self.clients.claim(); } catch (_) {}
    // 3. Remove this (and the old) registration entirely.
    try { await self.registration.unregister(); } catch (_) {}
    // 4. Hard-reload every open window onto the fresh, worker-free build.
    try {
      const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of clients) {
        client.navigate(client.url);
      }
    } catch (_) {}
  })());
});

// If a controlled page asks (belt-and-suspenders), also reload on message.
self.addEventListener('message', function (event) {
  if (event.data === 'check-update') self.registration.update();
});
