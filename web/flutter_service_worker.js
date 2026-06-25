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
    // Delete every cache the old worker created, then remove the registration.
    // Deliberately does NOT call clients.navigate()/reload — forcing a reload
    // from here causes a refresh loop. The fresh, worker-free build loads on
    // the next normal navigation; after unregister, no worker remains.
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
    } catch (_) {}
    try { await self.registration.unregister(); } catch (_) {}
  })());
});
