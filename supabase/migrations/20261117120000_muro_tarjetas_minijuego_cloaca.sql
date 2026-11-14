-- Dos tarjetas nuevas del muro (solo en el muro, nunca en el chat):
--   minijuego: récord de un minijuego con el puesto de la semana entre amigos.
--   mi_cloaca: estado de mi Cloaca; quien la ve puede unirse con cloaca_unirme_desde_muro sin ver el código.
-- normalizar_tarjeta se redefine entera: igual que en 20261115130000_muro_tarjetas_textos más las dos ramas.

create or replace function public.normalizar_tarjeta(p_user uuid, p_tarjeta jsonb, p_tabla text)
returns jsonb language plpgsql set search_path = '' as $$
declare
  total bigint;
  t text;
  c record;
  d record;
  r public.cagadas;
  im public.imperio;
  rollos numeric;
  e jsonb;
  v jsonb;
  g public.imperio_regalos;
  cl public.cloacas;
  n int;
  pos bigint;
  servidor boolean := coalesce(current_setting('imperio.tarjeta_servidor', true), '') = '1';
begin
  if p_tarjeta is null then return null; end if;
  if p_tabla not in ('mensajes', 'muro') then
    raise exception 'Tabla desconocida' using errcode = '23514';
  end if;
  t := p_tarjeta ->> 'tipo';
  select count(*) into total from public.cagadas where user_id = p_user;
  if t = 'hito' then
    if not ((p_tarjeta ->> 'n')::int = any (public.hitos())) or (p_tarjeta ->> 'n')::int > total then
      raise exception 'Todavía no llegas a ese número' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'hito', 'n', (p_tarjeta ->> 'n')::int,
      'reina', coalesce((select genero = 'mujer' from public.profiles where id = p_user), false));
  elsif t = 'desbloqueo' then
    select * into d from public.desbloqueos x where x.emoji = p_tarjeta ->> 'emoji' limit 1;
    if d is null or d.minimo > total then
      raise exception 'Todavía no has desbloqueado eso' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'desbloqueo', 'emoji', d.emoji, 'ranura', d.ranura, 'minimo', d.minimo);
  elsif t = 'cagada' then
    select x.id, x.tipo, x.peso, x.created_at into c from public.cagadas x
      where x.id = (p_tarjeta ->> 'id')::bigint and x.user_id = p_user;
    if c is null or c.tipo is null then
      raise exception 'Esa cagada no existe o no dijiste qué salió' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'cagada', 'mojon', c.tipo, 'peso', c.peso,
      'n', (select count(*) from public.cagadas x where x.user_id = p_user and x.created_at <= c.created_at));
  elsif t = 'racha' then
    select * into r from public.cagadas x
      where x.id = (p_tarjeta ->> 'id')::bigint and x.user_id = p_user;
    if r.id is null or public.racha_del_dia(r) < 2 then
      raise exception 'Esa cagada no es racha' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.mensajes x where p_tabla = 'mensajes' and x.tarjeta ->> 'tipo' = 'racha' and (x.tarjeta ->> 'id')::bigint = r.id)
       or exists (select 1 from public.muro x where p_tabla = 'muro' and x.tarjeta ->> 'tipo' = 'racha' and x.tarjeta ->> 'id' = r.id::text) then
      raise exception 'Esa racha ya salió en el %', case when p_tabla = 'muro' then 'muro' else 'chat' end using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'racha', 'id', r.id, 'n', public.racha_del_dia(r));
  elsif t in ('reto', 'reto_fin') and p_tabla = 'mensajes' then
    if not exists (select 1 from public.retos x where x.id = (p_tarjeta ->> 'id')::bigint
                   and p_user in (x.retador, x.retado)
                   and x.estado = case t when 'reto' then 'aceptado' else 'terminado' end) then
      raise exception 'Ese reto no es tuyo' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', t, 'id', (p_tarjeta ->> 'id')::bigint);
  elsif t = 'reto' then
    -- Muro: solo el servidor, al crear el reto, a nombre del que retó. Una sola publicación por reto.
    if not servidor or coalesce(p_tarjeta ->> 'id', '') !~ '^[0-9]{1,18}$'
       or not exists (select 1 from public.retos x where x.id = (p_tarjeta ->> 'id')::bigint
                      and x.retador = p_user and x.estado = 'pendiente') then
      raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.muro x where x.tarjeta ->> 'tipo' = 'reto' and x.tarjeta ->> 'id' = p_tarjeta ->> 'id') then
      raise exception 'Ese reto ya está en el muro' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'reto', 'id', (p_tarjeta ->> 'id')::bigint);
  elsif t = 'logro_imperio' then
    if coalesce(p_tarjeta ->> 'id', '') !~ '^[a-z0-9_]{1,40}$'
       or not exists (select 1 from public.imperio x where x.user_id = p_user
                      and jsonb_typeof(x.estado -> 'logros') = 'array'
                      and (x.estado -> 'logros') ? (p_tarjeta ->> 'id')) then
      raise exception 'Todavía no tienes ese logro del Imperio' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'logro_imperio', 'id', p_tarjeta ->> 'id');
  elsif t = 'jalada' then
    select * into im from public.imperio x where x.user_id = p_user;
    if im.user_id is null or coalesce(p_tarjeta ->> 'n', '') !~ '^[0-9]{1,9}$'
       or (p_tarjeta ->> 'n')::int <> im.jaladas or im.jaladas < 1
       or im.jalada_en is null or im.jalada_en < now() - interval '1 day' then
      raise exception 'Esa jalada no existe o ya pasó' using errcode = 'P0001';
    end if;
    if coalesce(p_tarjeta ->> 'rollos', '') !~ '^[0-9]{1,13}$' then
      raise exception 'Rollos fuera de rango' using errcode = 'P0001';
    end if;
    rollos := (p_tarjeta ->> 'rollos')::numeric;
    if rollos > 1e12 or rollos > public.imperio_rollos_tope(im) then
      raise exception 'Rollos fuera de rango' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.mensajes x where p_tabla = 'mensajes' and x.user_id = p_user and x.tarjeta ->> 'tipo' = 'jalada'
               and x.tarjeta ->> 'n' = im.jaladas::text)
       or exists (select 1 from public.muro x where p_tabla = 'muro' and x.user_id = p_user and x.tarjeta ->> 'tipo' = 'jalada'
               and x.tarjeta ->> 'n' = im.jaladas::text) then
      raise exception 'Esa jalada ya salió en el %', case when p_tabla = 'muro' then 'muro' else 'chat' end using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'jalada', 'n', im.jaladas, 'rollos', rollos::bigint);
  elsif t = 'cartera' then
    select * into im from public.imperio x where x.user_id = p_user;
    if im.user_id is null then
      raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.mensajes x where p_tabla = 'mensajes' and x.user_id = p_user and x.tarjeta ->> 'tipo' = 'cartera'
               and x.created_at > now() - interval '10 minutes')
       or exists (select 1 from public.muro x where p_tabla = 'muro' and x.user_id = p_user and x.tarjeta ->> 'tipo' = 'cartera'
               and x.created_at > now() - interval '10 minutes') then
      raise exception 'Espera un rato para volver a presumir tu cartera' using errcode = 'P0001';
    end if;
    -- Los números salen de la fila del usuario (lo último que guardó), nunca de lo que manda el cliente.
    return jsonb_build_object('tipo', 'cartera',
      'saldo', public.imperio_numero(im.estado ->> 'saldo'),
      'mps', public.imperio_numero(coalesce(im.estado ->> '_mps_edificios', im.mps::text)),
      'pujo', public.imperio_numero(im.estado ->> '_pujo'),
      'mj_total', greatest(coalesce(im.mj_total, 0), 0),
      'jaladas', greatest(im.jaladas, 0),
      'rollos', least(public.imperio_numero(im.estado ->> 'rollos'),
                      public.imperio_rollos_tope(im)));
  elsif t = 'bano' then
    select * into im from public.imperio x where x.user_id = p_user;
    if im.user_id is null then
      raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.mensajes x where p_tabla = 'mensajes' and x.user_id = p_user and x.tarjeta ->> 'tipo' = 'bano'
               and x.created_at > now() - interval '10 minutes')
       or exists (select 1 from public.muro x where p_tabla = 'muro' and x.user_id = p_user and x.tarjeta ->> 'tipo' = 'bano'
               and x.created_at > now() - interval '10 minutes') then
      raise exception 'Espera un rato para volver a presumir tu baño' using errcode = 'P0001';
    end if;
    -- Solo lo que dibuja el baño, sacado de la fila (nunca del cliente). Lo que venga mal se vuelve vacío.
    e := case when jsonb_typeof(im.estado) = 'object' then im.estado else '{}'::jsonb end;
    v := case when jsonb_typeof(e -> 'vista') = 'object' then e -> 'vista' else '{}'::jsonb end;
    return jsonb_build_object('tipo', 'bano', 'mudanzas', greatest(im.mudanzas, 0),
      'abdicaciones', greatest(coalesce(im.abdicaciones, 0), 0),
      'edificios', coalesce((select jsonb_object_agg(x.k, least(floor(case when jsonb_typeof(x.n) = 'number' then (x.n)::numeric end), 1000000)::int)
        from jsonb_each(case when jsonb_typeof(e -> 'edificios') = 'object' then e -> 'edificios' else '{}'::jsonb end) x(k, n)
        where x.k = any (array['dedo', 'ciruela', 'cafe', 'arepa', 'inodoro', 'bano', 'camion', 'planta', 'cloaca', 'granja',
                               'mina', 'templo', 'volcan', 'laxante_tiempo', 'agujero'])
          and case when jsonb_typeof(x.n) = 'number' then (x.n)::numeric >= 1 else false end), '{}'::jsonb),
      'mejoras', coalesce((select jsonb_agg(q.m order by q.m) from (
        select distinct m from jsonb_array_elements_text(
          case when jsonb_typeof(e -> 'mejoras') = 'array' then e -> 'mejoras' else '[]'::jsonb end) m
        where m ~ '^((adorno|tanque|valvula|dedo|ciruela|cafe|arepa|inodoro|bano|camion|planta)_[a-z0-9]{1,20}|iman|brillo|lavanda|guantes|faja)$'
        order by m limit 200) q), '[]'::jsonb),
      'esteticas', coalesce((select jsonb_agg(q.s order by q.s) from (
        select distinct s from unnest(im.esteticas) s where s ~ '^est_[a-z0-9_]{1,40}$' order by s limit 100) q), '[]'::jsonb),
      'vista', jsonb_strip_nulls(jsonb_build_object(
        'ocultos', (select jsonb_agg(q.o order by q.o) from (
          select distinct o from jsonb_array_elements_text(
            case when jsonb_typeof(v -> 'ocultos') = 'array' then v -> 'ocultos' else '[]'::jsonb end) o
          where o ~ '^[a-z0-9_]{1,40}$' order by o limit 100) q),
        'dedos', case when jsonb_typeof(v -> 'dedos') = 'number'
                      then least(greatest(floor((v -> 'dedos')::numeric), 0), 24)::int end,
        'ambiente', case when jsonb_typeof(v -> 'ambiente') = 'string' and v ->> 'ambiente' ~ '^[a-z]{1,20}$'
                         then v ->> 'ambiente' end)));
  elsif t = 'regalo' then
    -- Solo la pone imperio_regalar (servidor). Lleva quién da (el autor) y a quién va.
    if not servidor
       or coalesce(p_tarjeta ->> 'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
    end if;
    select * into g from public.imperio_regalos x where x.id = (p_tarjeta ->> 'id')::uuid and x.de = p_user;
    if g.id is null then
      raise exception 'Ese regalo no existe' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'regalo', 'id', g.id, 'de', g.de, 'para', g.para,
      'de_nombre', coalesce((select p.username from public.profiles p where p.id = g.de), ''),
      'para_nombre', coalesce((select p.username from public.profiles p where p.id = g.para), ''));
  elsif t = 'imperio' then
    -- Tarjeta genérica del Imperio {emoji, titulo, linea}: solo desde el servidor (imperio_tarjeta_chat).
    if not servidor then
      raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'imperio',
      'emoji', left(coalesce(nullif(btrim(p_tarjeta ->> 'emoji'), ''), '💩'), 8),
      'titulo', left(coalesce(btrim(p_tarjeta ->> 'titulo'), ''), 60),
      'linea', left(coalesce(btrim(p_tarjeta ->> 'linea'), ''), 140));
  elsif t = 'cloaca' then
    -- Ganadora de la liga semanal: solo la pone cloaca_cerrar_semana (servidor). Los datos salen del historial.
    if not servidor
       or coalesce(p_tarjeta ->> 'cloaca_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(p_tarjeta ->> 'semana', '') !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
    end if;
    select h.* into d from public.cloaca_historial h
     where h.semana = (p_tarjeta ->> 'semana')::date and h.cloaca_id = (p_tarjeta ->> 'cloaca_id')::uuid
       and h.puesto = 1;
    if d.cloaca_id is null then
      raise exception 'Esa Cloaca no ganó esa semana' using errcode = 'P0001';
    end if;
    return jsonb_build_object('tipo', 'cloaca', 'semana', d.semana, 'cloaca_id', d.cloaca_id,
      'nombre', d.nombre, 'emoji', d.emoji, 'puntos', d.puntos, 'miembros', d.miembros,
      'rollos', public.imperio_flag_numero('cloaca_premio_rollos', 2, 0, 1000)::int);
  elsif t = 'minijuego' and p_tabla = 'muro' then
    -- Récord de un minijuego: los puntos son el mejor de siempre del usuario; el puesto, el de esta semana entre amigos.
    if coalesce(p_tarjeta ->> 'juego', '') not in ('tuberia', 'destapa', 'memoria') then
      raise exception 'Ese juego no existe' using errcode = 'P0001';
    end if;
    select max(x.puntos) into n from public.imperio_minijuegos x
     where x.user_id = p_user and x.juego = p_tarjeta ->> 'juego';
    if n is null then
      raise exception 'Todavía no tienes partidas en ese juego' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.muro x where x.user_id = p_user and x.tarjeta ->> 'tipo' = 'minijuego'
               and x.tarjeta ->> 'juego' = p_tarjeta ->> 'juego' and x.tarjeta ->> 'puntos' = n::text) then
      raise exception 'Ese récord ya está pegado' using errcode = 'P0001';
    end if;
    -- El ranking mira a auth.uid(): solo vale si quien pega es el mismo usuario.
    if (select auth.uid()) = p_user then
      select k.puesto into pos from public.imperio_minijuego_ranking(p_tarjeta ->> 'juego', 'amigos') k where k.yo;
    end if;
    return jsonb_build_object('tipo', 'minijuego', 'juego', p_tarjeta ->> 'juego', 'puntos', n, 'puesto', pos);
  elsif t = 'mi_cloaca' and p_tabla = 'muro' then
    -- Foto de mi Cloaca para que otros se unan desde el muro (cloaca_unirme_desde_muro). Sin el código de invitación.
    select x.* into cl from public.cloacas x join public.cloaca_miembros m on m.cloaca_id = x.id where m.user_id = p_user;
    if cl.id is null then
      raise exception 'No estás en ninguna Cloaca' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.muro x where x.user_id = p_user and x.tarjeta ->> 'tipo' = 'mi_cloaca'
               and x.created_at >= public.imperio_inicio_dia()) then
      raise exception 'Tu Cloaca ya está pegada hoy' using errcode = 'P0001';
    end if;
    -- El mismo orden que cloaca_ranking.
    with sem as (select public.cloaca_semana_de(now()) as s),
    liga as (select q.cloaca_id, sum(q.puntos)::int as puntos from sem, public.cloaca_puntos(sem.s) q group by 1),
    orden as (select y.id, row_number() over (order by coalesce(liga.puntos, 0) desc, y.creado, y.id) as puesto
              from public.cloacas y left join liga on liga.cloaca_id = y.id)
    select orden.puesto into pos from orden where orden.id = cl.id;
    return jsonb_build_object('tipo', 'mi_cloaca', 'cloaca_id', cl.id, 'nombre', cl.nombre, 'emoji', cl.emoji,
      'puesto', pos,
      'miembros', (select count(*) from public.cloaca_miembros m where m.cloaca_id = cl.id)::int,
      'max', public.imperio_flag_numero('cloaca_max_miembros', 25, 2, 100)::int,
      'cagaron_hoy', (select count(*) from public.cloaca_miembros m where m.cloaca_id = cl.id
                      and exists (select 1 from public.cagadas k where k.user_id = m.user_id
                                  and k.created_at >= greatest(public.imperio_inicio_dia(), m.unido)))::int,
      'bono', public.cloaca_bono_de(p_user));
  elsif t in ('minijuego', 'mi_cloaca') then
    raise exception 'Esa tarjeta solo va en el muro' using errcode = 'P0001';
  end if;
  raise exception 'Tarjeta desconocida' using errcode = '23514';
end;
$$;
revoke execute on function public.normalizar_tarjeta(uuid, jsonb, text) from public, anon, authenticated;

-- Unirse a la Cloaca de una tarjeta mi_cloaca del muro. La publicación debe existir, no estar oculta y tener 7 días o
-- menos, sin bloqueo entre los dos. Usa cloaca_unirse con el código guardado en el servidor (el cliente nunca lo ve) y devuelve lo mismo.
create or replace function public.cloaca_unirme_desde_muro(p_muro_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  m public.muro;
  cod text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'motivo', 'sin_sesion'); end if;
  select * into m from public.muro x where x.id = p_muro_id;
  if m.id is null or m.oculto or coalesce(m.tarjeta ->> 'tipo', '') <> 'mi_cloaca'
     or m.created_at < now() - interval '7 days' or public.hay_bloqueo(m.user_id) then
    return jsonb_build_object('ok', false, 'motivo', 'publicacion');
  end if;
  select c.codigo into cod from public.cloacas c where c.id::text = m.tarjeta ->> 'cloaca_id';
  if cod is null then return jsonb_build_object('ok', false, 'motivo', 'codigo'); end if;
  return public.cloaca_unirse(cod);
end;
$$;
revoke all on function public.cloaca_unirme_desde_muro(bigint) from public, anon;
grant execute on function public.cloaca_unirme_desde_muro(bigint) to authenticated;
