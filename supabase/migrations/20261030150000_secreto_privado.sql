-- El secreto deja de verse por la API.
--
-- Antes: la política cagadas_read deja leer todas las filas a cualquier usuario con sesión, y
-- los grants de columna incluían placer y etiquetas. Cualquiera podía pedir
-- /rest/v1/cagadas?select=user_id,placer,etiquetas y ver las calificaciones de los demás,
-- y Realtime mandaba las mismas columnas en cada cambio de la tabla.
--
-- Ahora: authenticated solo puede leer las columnas que la app usa (id, user_id, created_at,
-- tipo, peso). placer y etiquetas se pueden seguir escribiendo (el parte las manda en un
-- update sin select), pero solo salen por ranking_placer, que pasa a security definer y
-- sigue exigiendo placer_desbloqueado a quien pregunta y a quien sale en la lista.
--
-- Apps viejas: ninguna versión pide select=* ni placer/etiquetas en cagadas (los selects son
-- id / id,tipo / id,created_at,tipo / id,created_at,tipo,peso / created_at,tipo,peso), así que
-- siguen funcionando. Realtime omite las columnas sin permiso (apply_rls usa
-- has_column_privilege). Los triggers que leen placer (avisar_placer) y la función
-- notificaciones (service_role) no cambian.

revoke select on public.cagadas from anon, authenticated;
grant select (id, user_id, created_at, tipo, peso) on public.cagadas to authenticated;

-- Con el revoke, la versión invoker no podría leer cagadas.placer. Mismo cuerpo, como dueño.
create or replace function public.ranking_placer(period text, solo_siguiendo boolean default false)
returns table (user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text,
               cagadas integer, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real,
               lentes_escala real, sombrero_escala real,
               placenteras bigint, destructivas bigint, calificadas bigint, promedio numeric)
language sql stable security definer set search_path = '' as $$
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
$$;

revoke execute on function public.ranking_placer(text, boolean) from public, anon;
grant execute on function public.ranking_placer(text, boolean) to authenticated;
