-- Total histórico de cagadas en el perfil, para los efectos de la mascota (se mueve,
-- cromada, dorada, arcoíris) sin contar en cada consulta.
alter table public.profiles add column cagadas int not null default 0;
update public.profiles p set cagadas = (select count(*) from public.cagadas c where c.user_id = p.id);

create function public.contar_cagadas() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set cagadas = cagadas + 1 where id = new.user_id;
  else
    update public.profiles set cagadas = greatest(cagadas - 1, 0) where id = old.user_id;
  end if;
  return null;
end;
$$;
revoke execute on function public.contar_cagadas() from public, anon, authenticated;

create trigger cagadas_contar after insert or delete on public.cagadas
  for each row execute function public.contar_cagadas();

-- El usuario solo edita estas columnas; cagadas la lleva el trigger.
revoke update on public.profiles from anon, authenticated;
grant update (username, avatar, bio, sombrero, lentes, mascota) on public.profiles to authenticated;

drop function public.leaderboard(text, boolean);
create function public.leaderboard(period text, solo_siguiendo boolean default false)
returns table(user_id uuid, username text, avatar text, total bigint, sombrero text, lentes text, mascota text, cagadas int)
language sql stable set search_path = ''
as $$
  select p.id, p.username, p.avatar, count(c.id) as total, p.sombrero, p.lentes, p.mascota, p.cagadas
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
  sombrero text, lentes text, mascota text, cagadas int
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
    p.sombrero, p.lentes, p.mascota, p.cagadas
  from public.profiles p where p.id = uid;
$$;
revoke execute on function public.perfil(uuid) from public, anon;
grant execute on function public.perfil(uuid) to authenticated;
