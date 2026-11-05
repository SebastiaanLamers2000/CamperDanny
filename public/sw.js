// Minimale service worker: maakt installeren op het startscherm mogelijk, cachet bijna niets.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
// Enige uitzondering: de landgrenzen voor de kaart worden bewaard, zodat de kaart ook offline mooi blijft.
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.hostname !== 'cdn.jsdelivr.net' || u.pathname.indexOf('world-atlas') < 0) return;
  e.respondWith(caches.open('geo-v1').then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(r => { if (r.ok) c.put(e.request, r.clone()); return r; }))));
});

// Meldingen (Web Push)
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (x) {}
  e.waitUntil(self.registration.showNotification(d.title || 'Camper Danny', { body: d.body || '', tag: d.tag || 'cd', icon: 'icon-192.png', badge: 'icon-192.png', data: { tab: d.tab || '' } }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close(); const tab = (e.notification.data || {}).tab || '';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) { if ('focus' in c) { c.postMessage({ cdTab: tab }); return c.focus(); } }
    return self.clients.openWindow('./' + (tab ? '#m-' + tab : ''));
  }));
});
