// Minimale service worker: maakt installeren op het startscherm mogelijk, cachet bijna niets.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
// Enige uitzondering: de landgrenzen voor de kaart worden bewaard, zodat de kaart ook offline mooi blijft.
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.hostname !== 'cdn.jsdelivr.net' || u.pathname.indexOf('world-atlas') < 0) return;
  e.respondWith(caches.open('geo-v1').then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(r => { if (r.ok) c.put(e.request, r.clone()); return r; }))));
});
