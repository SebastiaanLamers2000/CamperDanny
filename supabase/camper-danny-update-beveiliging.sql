-- Beveiliging: alleen veilige tekens in paden en id's (voorkomt kwaadaardige id's), en gasten zien geen aanvragen meer.
alter table public.docs add constraint docs_path_safe check (path ~ '^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$' and length(path) <= 200);
alter table public.photos add constraint photos_id_safe check (id ~ '^[A-Za-z0-9_-]{1,64}$' and trip_id ~ '^[A-Za-z0-9_-]{1,64}$');
drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests for select to authenticated
  using (coalesce(public.my_role(), '') in ('member', 'admin'));

-- Een gast mag zijn eigen boeking (reservering) verwijderen, niets anders.
drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated using (
  case split_part(path, '/', 1)
    when 'settings' then (my_role() = 'admin')
    else (my_role() in ('member', 'admin'))
      or (my_role() = 'guest' and split_part(path, '/', 1) = 'bookings' and (data ->> 'by') = auth.uid()::text)
  end);
