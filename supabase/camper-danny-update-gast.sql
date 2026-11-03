-- Camper Danny: nieuwe tussenrol "guest" (Gast)
-- Gast ziet reizen, spots, agenda, huuraanvragen en foto's (geen to-do's).
-- Gast kan reizen, spots en reserveringen toevoegen en alleen zijn eigen items aanpassen.
-- Gast kan niets verwijderen en geen aanvragen goedkeuren of afwijzen.

alter table public.members drop constraint if exists members_role_check;
alter table public.members add constraint members_role_check
  check (role in ('pending', 'viewer', 'guest', 'member', 'admin'));

drop policy if exists members_read on public.members;
create policy members_read on public.members for select to authenticated
  using (
    user_id = auth.uid()
    or public.my_role() = 'admin'
    or (public.my_role() in ('viewer', 'guest', 'member') and role <> 'pending')
  );

drop policy if exists docs_select on public.docs;
create policy docs_select on public.docs for select to authenticated
  using (
    case split_part(path, '/', 1)
      when 'trips'    then public.my_role() in ('viewer', 'guest', 'member', 'admin')
      when 'settings' then public.my_role() in ('viewer', 'guest', 'member', 'admin')
      when 'spots'    then public.my_role() in ('guest', 'member', 'admin')
      when 'bookings' then public.my_role() in ('guest', 'member', 'admin')
      else public.my_role() in ('member', 'admin')
    end
  );

drop policy if exists docs_insert on public.docs;
create policy docs_insert on public.docs for insert to authenticated
  with check (
    case split_part(path, '/', 1)
      when 'settings' then public.my_role() = 'admin'
      when 'todos'    then public.my_role() in ('member', 'admin')
      else public.my_role() in ('member', 'admin')
        or (public.my_role() = 'guest' and data->>'by' = auth.uid()::text)
    end
  );

drop policy if exists docs_update on public.docs;
create policy docs_update on public.docs for update to authenticated
  using (
    case split_part(path, '/', 1)
      when 'settings' then public.my_role() = 'admin'
      when 'todos'    then public.my_role() in ('member', 'admin')
      else public.my_role() in ('member', 'admin')
        or (public.my_role() = 'guest' and data->>'by' = auth.uid()::text)
    end
  )
  with check (
    case split_part(path, '/', 1)
      when 'settings' then public.my_role() = 'admin'
      when 'todos'    then public.my_role() in ('member', 'admin')
      else public.my_role() in ('member', 'admin')
        or (public.my_role() = 'guest' and data->>'by' = auth.uid()::text)
    end
  );
-- docs_delete blijft: alleen leden en beheerders (instellingen: beheerder).

drop policy if exists photos_select on public.photos;
create policy photos_select on public.photos for select to authenticated
  using (public.my_role() in ('viewer', 'guest', 'member', 'admin'));

drop policy if exists photos_insert on public.photos;
create policy photos_insert on public.photos for insert to authenticated
  with check (public.my_role() in ('guest', 'member', 'admin'));

-- Een gast mag foto's alleen wijzigen of wissen bij een reis/spot die hij zelf maakte.
create or replace function public.owns_parent(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.docs
    where path in ('trips/' || p_id, 'spots/' || p_id) and data->>'by' = auth.uid()::text
  )
$$;
revoke all on function public.owns_parent(text) from public, anon;
grant execute on function public.owns_parent(text) to authenticated;

drop policy if exists photos_update on public.photos;
create policy photos_update on public.photos for update to authenticated
  using (public.my_role() in ('member', 'admin') or (public.my_role() = 'guest' and public.owns_parent(trip_id)))
  with check (public.my_role() in ('member', 'admin') or (public.my_role() = 'guest' and public.owns_parent(trip_id)));

drop policy if exists photos_delete on public.photos;
create policy photos_delete on public.photos for delete to authenticated
  using (public.my_role() in ('member', 'admin') or (public.my_role() = 'guest' and public.owns_parent(trip_id)));

-- Huuraanvragen: een gast mag ze zien, maar niet verwijderen of beslissen (decide_request blijft leden/beheerders).
drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests for select to authenticated
  using (coalesce(public.my_role(), '') in ('guest', 'member', 'admin'));
