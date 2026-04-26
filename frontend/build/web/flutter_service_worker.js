// Kill-switch service worker.
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.map((n) => caches.delete(n)));
    await self.registration.unregister();
    const cs = await self.clients.matchAll({ type: 'window' });
    for (const c of cs) { try { c.navigate(c.url); } catch (_) {} }
  })());
});
self.addEventListener('fetch', (event) => event.respondWith(fetch(event.request)));
