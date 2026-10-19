-- Posición elegida por el usuario para lentes y sombrero (centro, en fracciones del avatar).
-- null = la posición calibrada para ese avatar.
alter table public.profiles
  add column lentes_x real check (lentes_x between -0.5 and 1.5),
  add column lentes_y real check (lentes_y between -0.5 and 1.5),
  add column sombrero_x real check (sombrero_x between -0.5 and 1.5),
  add column sombrero_y real check (sombrero_y between -0.5 and 1.5);
grant update (lentes_x, lentes_y, sombrero_x, sombrero_y) on public.profiles to authenticated;

-- 😎 ya trae lentes, así que se cambia por 🙂 para poder ponerle los de la app.
update public.profiles set avatar = '🙂' where avatar = '😎';

drop function public.leaderboard(text, boolean);
create function public.leaderboard(period text, solo_siguiendo boolean default false)
returns table(user_id uuid, username text, avatar text, total bigint, sombrero text, lentes text, mascota text,
              cagadas int, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real)
language sql stable set search_path = ''
as $$
  select p.id, p.username, p.avatar, count(c.id) as total, p.sombrero, p.lentes, p.mascota,
         p.cagadas, p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
  group by p.id
  order by total desc, p.username;
$$;
revoke execute on function public.leaderboard(text, boolean) from public, anon;
grant execute on function public.leaderboard(text, boolean) to authenticated;

drop function public.perfil(uuid);
create function public.perfil(uid uuid)
returns table(
  username text, avatar text, bio text, desde timestamptz,
  hoy bigint, semana bigint, mes bigint, anio bigint, total bigint,
  tipo_favorito smallint, seguidores bigint, siguiendo bigint, lo_sigo boolean,
  sombrero text, lentes text, mascota text, cagadas int,
  lentes_x real, lentes_y real, sombrero_x real, sombrero_y real
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
    exists (select 1 from public.follows where follower = (select auth.uid()) and followed = uid),
    p.sombrero, p.lentes, p.mascota, p.cagadas,
    p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y
  from public.profiles p where p.id = uid;
$$;
revoke execute on function public.perfil(uuid) from public, anon;
grant execute on function public.perfil(uuid) to authenticated;
