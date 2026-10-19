-- Perfil simple: emoji de avatar y bio corta.
alter table public.profiles
  add column avatar text not null default '💩' check (char_length(avatar) between 1 and 8),
  add column bio text check (char_length(bio) <= 140);

-- Quién sigue a quién. Ranking "Siguiendo" y los push solo usan esto.
create table public.follows (
  follower uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  followed uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower, followed),
  check (follower <> followed)
);
create index on public.follows (followed);
alter table public.follows enable row level security;

create policy follows_read on public.follows for select to authenticated using (true);
create policy follows_insert_own on public.follows
  for insert to authenticated with check ((select auth.uid()) = follower);
create policy follows_delete_own on public.follows
  for delete to authenticated using ((select auth.uid()) = follower);

alter publication supabase_realtime add table public.follows;

-- Los 3 que ya estaban se conocen: se siguen entre todos para que nadie abra la app con el ranking vacío.
insert into public.follows (follower, followed)
select a.id, b.id from public.profiles a cross join public.profiles b where a.id <> b.id;

-- solo_siguiendo = yo + a quienes sigo.
drop function public.leaderboard(text);
create function public.leaderboard(period text, solo_siguiendo boolean default false)
returns table(user_id uuid, username text, avatar text, total bigint)
language sql stable set search_path = ''
as $$
  select p.id, p.username, p.avatar, count(c.id) as total
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
  group by p.id, p.username, p.avatar
  order by total desc, p.username;
$$;
revoke execute on function public.leaderboard(text, boolean) from public, anon;
grant execute on function public.leaderboard(text, boolean) to authenticated;

-- Stats del perfil en una sola llamada.
create function public.perfil(uid uuid)
returns table(
  username text, avatar text, bio text, desde timestamptz,
  hoy bigint, semana bigint, mes bigint, anio bigint, total bigint,
  tipo_favorito smallint, seguidores bigint, siguiendo bigint, lo_sigo boolean
)
language sql stable set search_path = ''
as $$
  with c as (select created_at, tipo from public.cagadas where user_id = uid),
  t0 as (select now() at time zone 'America/Caracas' as ahora)
  select p.username, p.avatar, p.bio, p.created_at,
    (select count(*) from c, t0 where c.created_at >= date_trunc('day', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c, t0 where c.created_at >= date_trunc('week', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c, t0 where c.created_at >= date_trunc('month', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c, t0 where c.created_at >= date_trunc('year', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c),
    (select tipo from c where tipo is not null group by tipo order by count(*) desc, tipo limit 1),
    (select count(*) from public.follows where followed = uid),
    (select count(*) from public.follows where follower = uid),
    exists (select 1 from public.follows where follower = (select auth.uid()) and followed = uid)
  from public.profiles p where p.id = uid;
$$;
revoke execute on function public.perfil(uuid) from public, anon;
grant execute on function public.perfil(uuid) to authenticated;
