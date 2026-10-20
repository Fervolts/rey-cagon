-- El usuario solo ve sus propios bloqueos (RLS), así que la revisión en los dos sentidos va en
-- una función con permisos del dueño.
-- Solo responde por quien pregunta, para no revelar bloqueos entre terceros.
create function public.hay_bloqueo(otro uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.bloqueos x
                 where (x.bloqueador = (select auth.uid()) and x.bloqueado = otro)
                    or (x.bloqueador = otro and x.bloqueado = (select auth.uid())));
$$;
revoke execute on function public.hay_bloqueo(uuid) from public, anon;
grant execute on function public.hay_bloqueo(uuid) to authenticated;

drop policy follows_sin_bloqueo on public.follows;
create policy follows_sin_bloqueo on public.follows as restrictive for insert to authenticated
  with check (not public.hay_bloqueo(followed));

create or replace function public.leaderboard(period text, solo_siguiendo boolean DEFAULT false)
 RETURNS TABLE(user_id uuid, username text, avatar text, total bigint, sombrero text, lentes text, mascota text, cagadas integer, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p.id, p.username, p.avatar, count(c.id) as total, p.sombrero, p.lentes, p.mascota,
         p.cagadas, p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
    and not public.hay_bloqueo(p.id)
  group by p.id
  order by total desc, p.username;
$function$;

create or replace function public.ranking_placer(period text, solo_siguiendo boolean DEFAULT false)
 RETURNS TABLE(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real, placenteras bigint, destructivas bigint, calificadas bigint, promedio numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p.id, p.username, p.avatar, p.sombrero, p.lentes, p.mascota,
         p.cagadas, p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala,
         count(c.id) filter (where c.placer >= 5),
         count(c.id) filter (where c.placer <= 3),
         count(c.placer),
         round(avg(c.placer), 1)
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and exists (select 1 from public.profiles yo where yo.id = (select auth.uid()) and yo.placer_desbloqueado)
    and p.placer_desbloqueado
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
    and not public.hay_bloqueo(p.id)
  group by p.id;
$function$;
