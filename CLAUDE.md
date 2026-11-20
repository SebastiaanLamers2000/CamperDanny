# Camper Danny – werkafspraken voor Claude

Gratis telefoon-app (PWA) voor een gedeelde camper: reizen (km, foto's, nachten/slaapplaatsen), kaart, tijdlijn, agenda/reservaties, to-do, Spots, publieke huuraanvraag. Daarnaast een handleiding-site voor de camper op `/info/`.

## Wie en hoe
- Gebruiker spreekt Nederlands (Belgisch). Antwoord kort en in het Nederlands.
- Doe alleen wat gevraagd is. Geen handmatige Supabase/SQL-stappen van de gebruiker vragen: pas zelf toe via de Supabase-connector.
- Geen getypte locatievelden: locaties kies je op de kaart (zoals bij Spots).

## Deployen
- Live: https://mute-credit-0eda.sebastiaanlamers.workers.dev
- Cloudflare bouwt automatisch bij elke push naar `main` van `SebastiaanLamers2000/CamperDanny` (map `public/` is de assets-map, zie `wrangler.jsonc`). Duurt ongeveer 1 minuut.
- Na een wijziging: commit + push naar `main`. Gebruiker sluit en heropent de app op zijn gsm om de nieuwe versie te zien.

## Structuur
- `public/index.html`: de hele app in één bestand (vanilla JS). `public/sw.js`: service worker (cache + pushmeldingen). `public/config.js`: Supabase URL + publieke sleutel.
- `public/info/`: handleiding-site (aparte pagina's per onderwerp, eigen `style.css`, `site.js`, `sw.js`). Tekst van het koken staat in `info/koken.html`, de vertrekchecklist in `info/vertrek.html`. De tegel "Info over de camper" op het startscherm linkt naar `info/`.
- `supabase/*.sql`: databasescripts (al toegepast). `supabase/functions/`: edge functions (`resolve-map-link`, `send-push`).
- Supabase-project: `onkhjrbbdecvonmiycqv`. Rollen: pending, viewer, guest (Gast), member, admin.

## Let op
- Bij wijzigingen aan `index.html`: CSS-klasse `.tl` is al in gebruik (tijdlijn-tab); nachten gebruiken `.ntl`.
- De gebruiker bewerkt de handleiding soms lokaal op zijn pc (`C:\Users\sebas\Downloads\camper-danny-app`). Vergelijk dan eerst met `public/` voor je iets overschrijft: `index.html` in die map kan ouder zijn dan die in de repo.
- Hou `/mnt/user-data/outputs/camper-danny-site/index.html` niet als bron aan in een nieuw gesprek: de repo is de bron.
- Beveiliging: ids/paden mogen enkel `A-Za-z0-9_-` bevatten (check-constraints in de database + `okId()` in de app); gebruik `esc()` bij elke waarde in een HTML-attribuut. `public/_headers` bevat de CSP: voeg een nieuwe externe host daar ook toe, anders wordt hij geblokkeerd.
- Gasten zien geen huuraanvragen en mogen alleen hun eigen boekingen verwijderen (zie `supabase/camper-danny-update-beveiliging.sql`, al toegepast).
