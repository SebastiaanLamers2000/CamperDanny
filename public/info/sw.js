const V="danny-1795000000000";const F=["./index.html","./vertrek.html","./boiler.html","./verwarming.html","./bed.html","./douche.html","./wc.html","./water.html","./koken.html","./elektriciteit.html","./frigo.html","./terugbrengen.html","./benodigdheden.html","./noodgeval.html","./problemen.html","./style.css","./site.js","./icon.svg","./icon-192.png","./img/gas.jpg"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(F)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
// Netwerk eerst, maar bij slecht bereik (3 seconden) meteen de bewaarde pagina tonen. Alleen eigen, geslaagde antwoorden bewaren.
self.addEventListener("fetch",e=>{
  const q=e.request; if(q.method!=="GET"||new URL(q.url).origin!==self.location.origin)return;
  const cached=()=>caches.match(q,{ignoreSearch:true}).then(r=>r||caches.match("./"+new URL(q.url).pathname.split("/").pop()+".html"));
  const net=fetch(q).then(r=>{if(r.ok){const c=r.clone();caches.open(V).then(x=>x.put(q,c))}return r});
  const slow=new Promise(res=>setTimeout(()=>res(null),3000)).then(()=>cached()).then(r=>r||net);
  e.respondWith(Promise.race([net.catch(()=>cached().then(r=>r||Response.error())),slow]));
});
