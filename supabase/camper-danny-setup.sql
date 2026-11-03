-- Camper Danny: eenmalige installatie voor Supabase
-- Plak dit hele bestand in Supabase > SQL Editor en klik op Run.
-- Je kunt het veilig opnieuw uitvoeren.

-- 1. Tabellen -------------------------------------------------------------

create table if not exists public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  role text not null default 'pending' check (role in ('pending', 'viewer', 'member', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.docs (
  path text primary key,
  coll text generated always as (regexp_replace(path, '/[^/]+$', '')) stored,
  top  text generated always as (split_part(path, '/', 1)) stored,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint docs_top_ok check (split_part(path, '/', 1) in ('trips', 'bookings', 'todos', 'settings', 'spots'))
);
create index if not exists docs_coll_idx on public.docs (coll);

create table if not exists public.photos (
  id text primary key,
  trip_id text not null,
  data jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists photos_trip_idx on public.photos (trip_id);

-- 2. Rol van de ingelogde persoon -------------------------------------------

create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.members where user_id = auth.uid()
$$;

-- 3. Nieuwe accounts: de eerste persoon wordt beheerder, daarna wacht iedereen op goedkeuring

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.members (user_id, name, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)),
    case when exists (select 1 from public.members) then 'pending' else 'admin' end
  );
  return new;
end
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4. Toegangsregels ---------------------------------------------------------
-- viewer: ziet reizen, kaart en tijdlijn
-- member: ziet en wijzigt ook agenda en to-do
-- admin : beheert daarnaast instellingen en leden

alter table public.members enable row level security;
alter table public.docs    enable row level security;
alter table public.photos  enable row level security;

drop policy if exists members_read on public.members;
create policy members_read on public.members for select to authenticated
  using (
    user_id = auth.uid()
    or public.my_role() = 'admin'
    or (public.my_role() in ('viewer', 'member') and role <> 'pending')
  );

drop policy if exists members_admin_update on public.members;
create policy members_admin_update on public.members for update to authenticated
  using (public.my_role() = 'admin')
  with check (public.my_role() = 'admin');

drop policy if exists docs_select on public.docs;
create policy docs_select on public.docs for select to authenticated
  using (
    case split_part(path, '/', 1)
      when 'trips'    then public.my_role() in ('viewer', 'member', 'admin')
      when 'settings' then public.my_role() in ('viewer', 'member', 'admin')
      else public.my_role() in ('member', 'admin')
    end
  );

drop policy if exists docs_insert on public.docs;
create policy docs_insert on public.docs for insert to authenticated
  with check (
    case split_part(path, '/', 1)
      when 'settings' then public.my_role() = 'admin'
      else public.my_role() in ('member', 'admin')
    end
  );

drop policy if exists docs_update on public.docs;
create policy docs_update on public.docs for update to authenticated
  using (
    case split_part(path, '/', 1)
      when 'settings' then public.my_role() = 'admin'
      else public.my_role() in ('member', 'admin')
    end
  )
  with check (
    case split_part(path, '/', 1)
      when 'settings' then public.my_role() = 'admin'
      else public.my_role() in ('member', 'admin')
    end
  );

drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated
  using (
    case split_part(path, '/', 1)
      when 'settings' then public.my_role() = 'admin'
      else public.my_role() in ('member', 'admin')
    end
  );

drop policy if exists photos_select on public.photos;
create policy photos_select on public.photos for select to authenticated
  using (public.my_role() in ('viewer', 'member', 'admin'));

drop policy if exists photos_insert on public.photos;
create policy photos_insert on public.photos for insert to authenticated
  with check (public.my_role() in ('member', 'admin'));

drop policy if exists photos_update on public.photos;
create policy photos_update on public.photos for update to authenticated
  using (public.my_role() in ('member', 'admin'))
  with check (public.my_role() in ('member', 'admin'));

drop policy if exists photos_delete on public.photos;
create policy photos_delete on public.photos for delete to authenticated
  using (public.my_role() in ('member', 'admin'));

-- 5. Rechten voor ingelogde gebruikers (anonieme bezoekers krijgen niets) ------

grant usage on schema public to authenticated;
revoke all on public.members, public.docs, public.photos from anon;
grant select, update on public.members to authenticated;
grant select, insert, update, delete on public.docs   to authenticated;
grant select, insert, update, delete on public.photos to authenticated;

-- 6. Live bijwerken tussen toestellen -----------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docs'
  ) then
    alter publication supabase_realtime add table public.docs;
  end if;
end
$$;
