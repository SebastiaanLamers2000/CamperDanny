// Camper Danny: volgt een Google Maps-link (ook de korte maps.app.goo.gl-links) en geeft de coördinaten terug.
// Plak deze code in Supabase > Edge Functions > Deploy a new function > Via Editor. Naam: resolve-map-link
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const HOSTS = /^(maps\.app\.goo\.gl|goo\.gl|g\.co|(www\.|maps\.)?google\.[a-z.]+|consent\.google\.[a-z.]+)$/i;
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

export function parseCoords(s: string): { lat: number; lon: number } | null {
  let t = s; try { t = decodeURIComponent(s); } catch (_e) { /* laten staan */ }
  const pats = [
    /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/,
    /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/,
    /[?&](?:q|ll|query|center|destination|daddr)=(-?\d+(?:\.\d+)?)[,+ ]\s*(-?\d+(?:\.\d+)?)/,
    /center=(-?\d+(?:\.\d+)?)%2C(-?\d+(?:\.\d+)?)/,
  ];
  for (const p of pats) {
    const m = t.match(p);
    if (m) { const lat = parseFloat(m[1]), lon = parseFloat(m[2]); if (Math.abs(lat) <= 90 && Math.abs(lon) <= 180) return { lat, lon }; }
  }
  return null;
}

export function parseName(u: string): string | null {
  const m = u.match(/\/maps\/place\/([^/@?]+)/);
  if (!m) return null;
  try { const n = decodeURIComponent(m[1].replace(/\+/g, ' ')).trim(); return /^-?\d+(\.\d+)?[,\s]/.test(n) ? null : n.slice(0, 120); } catch (_e) { return null; }
}

export async function resolve(input: string, doFetch: typeof fetch = fetch) {
  let cur = new URL(input);
  if (cur.protocol !== 'https:' || !HOSTS.test(cur.hostname)) return { ok: false, error: 'host' };
  const headers = { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36', 'accept-language': 'nl-BE,nl;q=0.9', cookie: 'CONSENT=YES+cb; SOCS=CAI' };
  let body = '';
  for (let hop = 0; hop < 8; hop++) {
    const direct = parseCoords(cur.toString());
    if (direct && hop > 0) return { ok: true, ...direct, name: parseName(cur.toString()), url: cur.toString() };
    const res = await doFetch(cur.toString(), { redirect: 'manual', headers });
    const loc = res.headers.get('location');
    if (res.status >= 300 && res.status < 400 && loc) {
      let next = new URL(loc, cur);
      if (/^consent\.google\./i.test(next.hostname) && next.searchParams.get('continue')) next = new URL(next.searchParams.get('continue')!);
      if (next.protocol !== 'https:' || !HOSTS.test(next.hostname)) return { ok: false, error: 'host' };
      cur = next; continue;
    }
    body = (await res.text()).slice(0, 600000);
    break;
  }
  const c = parseCoords(cur.toString()) || parseCoords(body);
  return c ? { ok: true, ...c, name: parseName(cur.toString()), url: cur.toString() } : { ok: false, error: 'nocoords', name: parseName(cur.toString()), url: cur.toString() };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const { url } = await req.json();
    if (typeof url !== 'string' || url.length > 500) return json({ ok: false, error: 'bad' }, 400);
    return json(await resolve(url));
  } catch (_e) { return json({ ok: false, error: 'fail' }, 200); }
});
