-- Camper Danny: uitbreiding voor het tablad "Spots" (leuke overnachtingsplekken)
-- Plak dit in Supabase > SQL Editor en klik op Run. Je kunt het veilig opnieuw uitvoeren.
-- Bestaande reizen, foto's, boekingen en accounts blijven ongemoeid.

alter table public.docs drop constraint if exists docs_top_ok;
alter table public.docs add constraint docs_top_ok
  check (split_part(path, '/', 1) in ('trips', 'bookings', 'todos', 'settings', 'spots'));
