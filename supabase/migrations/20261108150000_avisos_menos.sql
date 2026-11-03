-- Menos avisos push.
--   1. push_config.cagadas_cada_min (90): como mucho un push de 'cagada' o 'placer' por persona cada tantos minutos.
--      Las cagadas de amigos que caen dentro de esa ventana no mandan push; el siguiente aviso las resume
--      ("Pedro cagó (y 3 amigos más desde tu último aviso)"). 0 = sin tope.
--   2. push_config.version_cada_horas (20): como mucho un push de 'version' por persona cada tantas horas.
--      0 = sin tope. 'actualizar_play' no cambia.
--   3. push_tope(): la Edge Function notificaciones pregunta quién está frenado y cuántos amigos cagaron desde su
--      último aviso. No hay tabla nueva: se cuenta sobre push_envios (último envío, índice push_envios_user_idx)
--      y sobre follows + cagadas (lo que pasó desde ese envío). Un viaje a la base por aviso.
--   4. push_resumen_mio(): cuántos avisos te llegaron en 7 días, por tipo y por categoría, y cuántas categorías
--      tienes prendidas. Lo usa la app para la tarjeta "Ordena tus avisos" y para los números de Ajustes.
-- La Edge Function y la app funcionan sin esta migración (sin tope y sin tarjeta).

alter table public.push_config
  add column if not exists cagadas_cada_min int not null default 90,
  add column if not exists version_cada_horas int not null default 20;

-- ---------------------------------------------------------------- tope por persona (solo service_role)
-- p_tipo: 'cagadas' (tipos cagada y placer) o 'version'. Devuelve una fila por usuario de p_usuarios que tuvo un
-- aviso de esos tipos hace poco: frenado = cayó dentro de la ventana; otros = amigos (gente que sigue, sin contar a
-- p_autor) que cagaron después de ese aviso. Usuarios sin fila = sin tope.
create or replace function public.push_tope(p_usuarios uuid[], p_tipo text, p_autor uuid default null)
returns table (user_id uuid, frenado boolean, otros integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tipos text[];
  v_minutos int;
begin
  if p_tipo = 'cagadas' then
    v_tipos := array['cagada', 'placer'];
    v_minutos := coalesce((select c.cagadas_cada_min from public.push_config c limit 1), 0);
  elsif p_tipo = 'version' then
    v_tipos := array['version'];
    v_minutos := coalesce((select c.version_cada_horas from public.push_config c limit 1), 0) * 60;
  else
    raise exception 'tipo de tope desconocido: %', p_tipo;
  end if;
  if v_minutos <= 0 or p_usuarios is null then return; end if;

  return query
  with ultimos as (
    select e.user_id as uid, max(e.enviado) as ultimo
    from public.push_envios e
    where e.user_id = any (p_usuarios)
      and e.tipo = any (v_tipos)
      and e.enviado > now() - make_interval(mins => greatest(v_minutos, 1440))
    group by e.user_id
  )
  select
    u.uid,
    u.ultimo > now() - make_interval(mins => v_minutos),
    case when p_tipo = 'cagadas' then (
      select count(distinct c.user_id)::int
      from public.follows f
      join public.cagadas c on c.user_id = f.followed and c.created_at > u.ultimo
      where f.follower = u.uid
        and (p_autor is null or f.followed <> p_autor)
    ) else 0 end
  from ultimos u;
end;
$$;
revoke all on function public.push_tope(uuid[], text, uuid) from public, anon, authenticated;
grant execute on function public.push_tope(uuid[], text, uuid) to service_role;

-- ---------------------------------------------------------------- RPC de la app
-- Tus avisos de los últimos 7 días. push_envios guarda una fila por teléfono: un mismo envío a tus dos teléfonos
-- comparte tipo y hora (se insertan en la misma sentencia), así que se cuenta por (tipo, subtipo, enviado).
-- por_categoria usa las 8 claves de push_ajustes; lo que no se apaga (versión, anuncio, soporte...) va a 'otros'.
-- prendidas: cuántas de las 8 tienes prendidas ('imperio' = imperio, poceta y racha, como en push_avisos_mios).
create or replace function public.push_resumen_mio()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a public.push_ajustes;
  v_tipos jsonb;
  v_categorias jsonb;
  v_total int;
  v_prendidas int;
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;

  with envios as (
    select distinct e.tipo, e.subtipo, e.enviado
    from public.push_envios e
    where e.user_id = auth.uid()
      and e.enviado > now() - interval '7 days'
  ), con_categoria as (
    select
      tipo,
      case
        when tipo = 'cagada' and subtipo in ('rampage', 'hexakill') then 'rachas'
        when tipo in ('cagada', 'placer') then 'cagadas'
        when tipo = 'follow' then 'seguidores'
        when tipo in ('mencion', 'respuesta') then 'chat'
        when tipo = 'reto' then 'retos'
        when tipo in ('poceta', 'racha', 'regalo') then 'imperio'
        when tipo = 'ganadores' then 'ganadores'
        when tipo = 'cierre' then 'cierres'
        else 'otros'
      end as categoria
    from envios
  )
  select
    count(*)::int,
    coalesce((select jsonb_object_agg(t.tipo, t.n) from (
      select tipo, count(*)::int as n from con_categoria group by tipo) t), '{}'::jsonb),
    coalesce((select jsonb_object_agg(k.categoria, k.n) from (
      select categoria, count(*)::int as n from con_categoria group by categoria) k), '{}'::jsonb)
  into v_total, v_tipos, v_categorias
  from con_categoria;

  select * into a from public.push_ajustes where user_id = auth.uid();
  v_prendidas :=
    coalesce(a.cagadas, true)::int + coalesce(a.rachas, true)::int + coalesce(a.ganadores, true)::int
    + coalesce(a.cierres, true)::int + coalesce(a.chat, true)::int + coalesce(a.retos, true)::int
    + coalesce(a.seguidores, true)::int
    + (coalesce(a.imperio, true) and coalesce(a.poceta, true) and coalesce(a.racha, true))::int;

  return jsonb_build_object(
    'dias', 7,
    'total', coalesce(v_total, 0),
    'por_tipo', coalesce(v_tipos, '{}'::jsonb),
    'por_categoria', coalesce(v_categorias, '{}'::jsonb),
    'prendidas', v_prendidas,
    'categorias', 8
  );
end;
$$;
revoke all on function public.push_resumen_mio() from public, anon;
grant execute on function public.push_resumen_mio() to authenticated;

notify pgrst, 'reload schema';
