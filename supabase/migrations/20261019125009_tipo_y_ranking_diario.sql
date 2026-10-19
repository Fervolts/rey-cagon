-- Tipo de mojón (de chiste, no es escala médica). Null = no lo dijo.
alter table public.cagadas add column tipo smallint check (tipo between 1 and 7);

-- Para poder ponerle el tipo después de registrar.
create policy cagadas_update_own on public.cagadas
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- 'day' alimenta el aviso de "vas perdiendo" del día.
create or replace function public.leaderboard(period text)
returns table(user_id uuid, username text, total bigint)
language sql stable set search_path = ''
as $$
  select p.id, p.username, count(c.id) as total
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
  group by p.id, p.username
  order by total desc, p.username;
$$;
