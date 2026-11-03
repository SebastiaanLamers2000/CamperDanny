-- Camper Danny: uitbreiding voor huuraanvragen
-- Voer dit uit NADAT camper-danny-setup.sql al gelukt is.
-- Plak dit hele bestand in Supabase > SQL Editor en klik op Run.
-- Je kunt het veilig opnieuw uitvoeren.

-- 1. Tabel met aanvragen ---------------------------------------------------------

create table if not exists public.requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  email text not null,
  phone text not null default '',
  note text not null default '',
  start_date date not null,
  end_date date not null,
  status text not null default 'new' check (status in ('new', 'approved', 'rejected')),
  decided_by uuid,
  decided_at timestamptz,
  booking_path text,
  constraint requests_dates_ok check (end_date >= start_date),
  constraint requests_len_ok check (
    char_length(name) between 2 and 100
    and char_length(email) <= 200
    and char_length(phone) <= 40
    and char_length(note) <= 1000
  )
);
create index if not exists requests_status_idx on public.requests (status, created_at desc);

-- 2. Wie mag de aanvragen zien -----------------------------------------------------
-- Alleen leden met "Alles" of beheerders. Bezoekers zonder account krijgen niets te lezen.

alter table public.requests enable row level security;

drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests for select to authenticated
  using (coalesce(public.my_role(), '') in ('member', 'admin'));

drop policy if exists requests_delete on public.requests;
create policy requests_delete on public.requests for delete to authenticated
  using (coalesce(public.my_role(), '') in ('member', 'admin'));

revoke all on public.requests from anon, authenticated;
grant select, delete on public.requests to authenticated;

-- 3. Hulpfunctie: tekst veilig omzetten naar een datum ---------------------------

create or replace function public.safe_date(t text)
returns date
language plpgsql
immutable
set search_path = public
as $$
begin
  return t::date;
exception when others then
  return null;
end
$$;
revoke all on function public.safe_date(text) from public, anon, authenticated;

-- 4. Bezette dagen voor het openbare formulier ------------------------------------
-- Geeft alleen begin- en einddatums terug. Geen titels, namen of notities.

create or replace function public.busy_dates()
returns table (d_start date, d_end date)
language sql
stable
security definer
set search_path = public
as $$
  select s, greatest(s, e)
  from (
    select public.safe_date(data->>'start') as s,
           coalesce(public.safe_date(data->>'end'), public.safe_date(data->>'start')) as e
    from public.docs
    where top = 'bookings'
  ) x
  where s is not null and e is not null
    and greatest(s, e) >= (now() at time zone 'Europe/Brussels')::date
  order by s
$$;
revoke all on function public.busy_dates() from public;
grant execute on function public.busy_dates() to anon, authenticated;

-- 5. Aanvraag indienen (zonder account) ----------------------------------------------
-- Controleert alles op de server, ook als iemand de pagina omzeilt.
-- Maximaal 3 aanvragen per e-mailadres per dag en 30 per uur in totaal.

create or replace function public.submit_request(
  p_name text,
  p_email text,
  p_phone text,
  p_start date,
  p_end date,
  p_note text default '',
  p_hp text default ''
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Europe/Brussels')::date;
  v_name  text := btrim(coalesce(p_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_phone text := btrim(coalesce(p_phone, ''));
  v_note  text := btrim(coalesce(p_note, ''));
  v_id uuid;
begin
  -- verborgen veld dat alleen bots invullen: doen alsof het gelukt is
  if btrim(coalesce(p_hp, '')) <> '' then
    return json_build_object('ok', true);
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 100 then
    return json_build_object('ok', false, 'error', 'name');
  end if;
  if char_length(v_email) > 200 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return json_build_object('ok', false, 'error', 'email');
  end if;
  if char_length(v_phone) > 40 then
    return json_build_object('ok', false, 'error', 'phone');
  end if;
  if char_length(v_note) > 1000 then
    return json_build_object('ok', false, 'error', 'note');
  end if;
  if p_start is null or p_end is null or p_start < v_today or p_end < p_start or p_end - p_start > 60 then
    return json_build_object('ok', false, 'error', 'dates');
  end if;

  if exists (select 1 from public.busy_dates() b where b.d_start <= p_end and b.d_end >= p_start) then
    return json_build_object('ok', false, 'error', 'busy');
  end if;

  if (select count(*) from public.requests where email = v_email and created_at > now() - interval '1 day') >= 3
     or (select count(*) from public.requests where created_at > now() - interval '1 hour') >= 30 then
    return json_build_object('ok', false, 'error', 'too_many');
  end if;

  insert into public.requests (name, email, phone, note, start_date, end_date)
  values (v_name, v_email, v_phone, v_note, p_start, p_end)
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id);
end
$$;
revoke all on function public.submit_request(text, text, text, date, date, text, text) from public;
grant execute on function public.submit_request(text, text, text, date, date, text, text) to anon, authenticated;

-- 6. Goedkeuren of afwijzen (alleen ingelogde leden met "Alles" of beheerders) ---------
-- Bij goedkeuren komt de periode meteen als "Gereserveerd" in de agenda.

create or replace function public.decide_request(p_id uuid, p_approve boolean)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.requests%rowtype;
  v_path text;
  v_notes text;
begin
  if coalesce(public.my_role(), '') not in ('member', 'admin') then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select * into r from public.requests where id = p_id for update;
  if not found then
    return json_build_object('ok', false, 'error', 'notfound');
  end if;
  if r.status <> 'new' then
    return json_build_object('ok', false, 'error', 'already');
  end if;

  if p_approve then
    v_path := 'bookings/req-' || r.id::text;
    v_notes := 'Huurder: ' || r.name || ' · ' || r.email
      || case when r.phone <> '' then ' · ' || r.phone else '' end
      || case when r.note <> '' then E'\n' || r.note else '' end;
    insert into public.docs (path, data)
    values (
      v_path,
      jsonb_build_object(
        'title', 'Huur: ' || r.name,
        'kind', 'reservering',
        'start', r.start_date::text,
        'end', r.end_date::text,
        'notes', v_notes,
        'by', null,
        'createdAt', (extract(epoch from now()) * 1000)::bigint,
        'requestId', r.id::text
      )
    )
    on conflict (path) do nothing;
  end if;

  update public.requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(),
         decided_at = now(),
         booking_path = case when p_approve then v_path else null end
   where id = p_id;

  return json_build_object('ok', true);
end
$$;
revoke all on function public.decide_request(uuid, boolean) from public, anon;
grant execute on function public.decide_request(uuid, boolean) to authenticated;

-- 7. Live bijwerken van nieuwe aanvragen ---------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'requests'
  ) then
    alter publication supabase_realtime add table public.requests;
  end if;
end
$$;
