-- Tarjetas al muro, no al chat. Lo que se presume (hito, desbloqueo, cagada, racha, Imperio, regalo, Cloaca) pasa a ser
-- una publicación del muro con su tarjeta, y el chat queda solo para hablar. Los retos Cagadón también: al crearse el
-- reto, el que retó pega su tarjeta en el muro (pendiente) y esa misma publicación pasa a marcador en vivo y a resultado.
--
-- Compatibilidad: las apps 72 y 73 siguen leyendo tarjetas del chat, así que el servidor escribe las dos copias (chat y
-- muro). La copia del chat se quita cuando version_minima pase el build que lee las tarjetas del muro.

-- 1. Columna y check ---------------------------------------------------------------------------------------------------
alter table public.muro add column tarjeta jsonb;
alter table public.muro drop constraint muro_check;
alter table public.muro add constraint muro_contenido check (texto is not null or dibujo is not null or tarjeta is not null);
create index muro_tarjeta_tipo_id on public.muro ((tarjeta ->> 'tipo'), ((tarjeta ->> 'id'))) where tarjeta is not null;

-- 2. Normalizar una tarjeta (compartida por el chat y el muro) ---------------------------------------------------------
-- Comprueba que la tarjeta sea de verdad del usuario y la rehace desde las filas del servidor (nunca de lo que manda el
-- cliente). p_tabla dice dónde se publica ('mensajes' o 'muro'): los anti-duplicados miran esa tabla.
-- Diferencia a propósito: en el chat la tarjeta 'reto' es de un reto aceptado; en el muro la pone solo el servidor al
-- crear el reto (pendiente) y 'reto_fin' no existe (la misma publicación pasa a resultado).
create function public.normalizar_tarjeta(p_user uuid, p_tarjeta jsonb, p_tabla text)
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
      raise exception 'Esa racha ya salió' using errcode = 'P0001';
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
      raise exception 'Esa jalada ya salió' using errcode = 'P0001';
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
  end if;
  raise exception 'Tarjeta desconocida' using errcode = '23514';
end;
$$;
revoke execute on function public.normalizar_tarjeta(uuid, jsonb, text) from public, anon, authenticated;

-- 3. El chat usa la función compartida (mismo comportamiento que antes) ------------------------------------------------
create or replace function public.validar_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  malo text;
begin
  -- auth.uid() es null cuando escribe el servidor (cierre de retos): se respeta el user_id.
  new.user_id := coalesce(auth.uid(), new.user_id);
  new.oculto := false;
  new.created_at := now();
  new.texto := btrim(new.texto);
  if public.sala_publica(new.sala) or new.sala like 'cloaca:%' or new.sala like 'dm:%' then new.es_bug := false; end if;
  if new.texto = '' and new.tarjeta is null then
    raise exception 'Mensaje vacío' using errcode = 'P0001';
  end if;
  malo := public.link_peligroso(new.texto);
  if malo is not null then
    raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
  end if;
  if (public.sala_publica(new.sala) or new.sala like 'cloaca:%' or new.sala like 'dm:%') and (new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') then
    raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
  end if;

  -- Los privados son solo texto: ninguna tarjeta (hitos, cagadas, regalos...) entra en un dm.
  if new.sala like 'dm:%' and new.tarjeta is not null then
    raise exception 'En privado solo van mensajes de texto' using errcode = 'P0001';
  end if;
  -- Tope de privados: 20 por minuto, y 20 conversaciones nuevas por día (cada mensaje dispara un push).
  if new.sala like 'dm:%' then
    if (select count(*) from public.mensajes x
        where x.user_id = new.user_id and x.sala like 'dm:%' and x.created_at > now() - interval '1 minute') >= 20 then
      raise exception 'Vas muy rápido. Espera un momento.' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.mensajes x where x.sala = new.sala)
       and (select count(distinct x.sala) from public.mensajes x
            where x.user_id = new.user_id and x.sala like 'dm:%' and x.created_at > now() - interval '1 day'
              and not exists (select 1 from public.mensajes y where y.sala = x.sala and y.id < x.id)) >= 20 then
      raise exception 'Ya abriste muchas conversaciones hoy. Prueba mañana.' using errcode = 'P0001';
    end if;
  end if;

  if new.tarjeta is not null then
    new.tarjeta := public.normalizar_tarjeta(new.user_id, new.tarjeta, 'mensajes');
  end if;
  return new;
end;
$$;

-- 4. El muro acepta tarjetas -------------------------------------------------------------------------------------------
-- Lo que escribe el servidor (setting imperio.tarjeta_servidor = '1') puede ir a nombre de otro y no cuenta para el tope.
create or replace function public.validar_muro()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  malo text;
  servidor boolean := coalesce(current_setting('imperio.tarjeta_servidor', true), '') = '1';
begin
  if new.user_id is distinct from auth.uid() and not (servidor and new.user_id is not null) then
    raise exception 'Solo puedes publicar a tu nombre' using errcode = 'P0001';
  end if;
  new.oculto := false;
  new.created_at := now();
  new.texto := nullif(btrim(new.texto), '');
  if new.texto is null and new.dibujo is null and new.tarjeta is null then
    raise exception 'Publicación vacía' using errcode = 'P0001';
  end if;
  if new.texto is not null then
    if char_length(new.texto) > 500 then raise exception 'Texto muy largo' using errcode = 'P0001'; end if;
    malo := public.link_peligroso(new.texto);
    if malo is not null then
      raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
    end if;
    if new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
      raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
    end if;
  end if;
  if new.dibujo is not null then
    malo := public.dibujo_invalido(new.dibujo);
    if malo is not null then
      raise exception 'Dibujo inválido: %', malo using errcode = 'P0001';
    end if;
  end if;
  -- Dos publicaciones a la vez no se saltan el tope (ni los anti-duplicados de la tarjeta).
  perform pg_advisory_xact_lock(hashtext('muro:' || new.user_id::text));
  if new.tarjeta is not null then
    new.tarjeta := public.normalizar_tarjeta(new.user_id, new.tarjeta, 'muro');
  end if;
  if not servidor
     and (select count(*) from public.muro m where m.user_id = new.user_id and m.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Ya publicaste mucho esta hora. Espera un rato.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- Pegar una tarjeta del servidor en el muro. Nunca falla hacia afuera: que el muro falle no tumba lo que la llamó.
create function public.muro_tarjeta_servidor(p_user uuid, p_tarjeta jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  nuevo bigint;
  antes text := coalesce(current_setting('imperio.tarjeta_servidor', true), '');
begin
  if p_user is null or p_tarjeta is null then return null; end if;
  perform set_config('imperio.tarjeta_servidor', '1', true);
  begin
    insert into public.muro (user_id, tarjeta) values (p_user, p_tarjeta) returning id into nuevo;
  exception when others then
    nuevo := null;
  end;
  perform set_config('imperio.tarjeta_servidor', antes, true);
  return nuevo;
end;
$$;
revoke execute on function public.muro_tarjeta_servidor(uuid, jsonb) from public, anon, authenticated;

-- 5. Lo que hoy escribe el servidor en el chat también va al muro ------------------------------------------------------
-- Regalos y Cloaca (imperio_regalar, cloaca_cerrar_semana) pasan por aquí.
create or replace function public.imperio_tarjeta_chat(p_user uuid, p_tarjeta jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  nuevo bigint;
begin
  if p_user is null or p_tarjeta is null then return null; end if;
  perform set_config('imperio.tarjeta_servidor', '1', true);
  -- Copia del chat para las apps 72/73: se quita cuando version_minima pase el build que lee el muro.
  begin
    insert into public.mensajes (sala, user_id, texto, tarjeta) values ('global', p_user, '', p_tarjeta) returning id into nuevo;
  exception when others then
    nuevo := null;
  end;
  perform set_config('imperio.tarjeta_servidor', '', true);
  perform public.muro_tarjeta_servidor(p_user, p_tarjeta);
  return nuevo;
end;
$$;

create or replace function public.anunciar_racha()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    -- Deshacer la cagada se lleva su tarjeta (del chat y del muro).
    delete from public.mensajes where tarjeta ->> 'tipo' = 'racha' and (tarjeta ->> 'id')::bigint = old.id;
    delete from public.muro where tarjeta ->> 'tipo' = 'racha' and tarjeta ->> 'id' = old.id::text;
    return null;
  end if;
  if public.racha_del_dia(new) >= 2 then
    -- Copia del chat para las apps 72/73: se quita cuando version_minima pase el build que lee el muro.
    begin
      insert into public.mensajes (sala, user_id, tarjeta)
      values ('global', new.user_id, jsonb_build_object('tipo', 'racha', 'id', new.id));
    exception when others then
      -- Que el chat falle no puede tumbar la cagada.
      null;
    end;
    perform public.muro_tarjeta_servidor(new.user_id, jsonb_build_object('tipo', 'racha', 'id', new.id));
  end if;
  return null;
end;
$$;

-- 6. Retos: la tarjeta va al muro al crearse ---------------------------------------------------------------------------
-- Aceptar, terminar y rajarse no crean publicaciones: la misma tarjeta cambia de estado. Cancelar la borra.
create function public.reto_al_muro()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.muro_tarjeta_servidor(new.retador, jsonb_build_object('tipo', 'reto', 'id', new.id));
  return null;
end;
$$;
revoke execute on function public.reto_al_muro() from public, anon, authenticated;
create trigger retos_muro after insert on public.retos for each row execute function public.reto_al_muro();

create or replace function public.responder_reto(rid bigint, accion text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.retos;
  yo uuid := auth.uid();
begin
  select * into r from public.retos where id = rid for update;
  if r is null or r.estado <> 'pendiente' then
    raise exception 'Ese reto ya no está pendiente' using errcode = 'P0001';
  end if;
  if r.dia <> (now() at time zone 'America/Caracas')::date then
    update public.retos set estado = 'cancelado' where id = rid;
    raise exception 'Ese reto era de otro día' using errcode = 'P0001';
  end if;
  if accion = 'cancelar' and yo = r.retador then
    update public.retos set estado = 'cancelado' where id = rid;
    delete from public.muro where tarjeta ->> 'tipo' = 'reto' and tarjeta ->> 'id' = rid::text;
  elsif accion = 'rechazar' and yo = r.retado then
    update public.retos set estado = 'rechazado' where id = rid;
    perform public.avisar_reto(rid, 'rechazado');
  elsif accion = 'aceptar' and yo = r.retado then
    update public.retos set estado = 'aceptado', apuesta_anulada = (r.apuesta_min > 0) where id = rid;
    -- Copia del chat para las apps 72/73: se quita cuando version_minima pase el build que lee el muro.
    insert into public.mensajes (sala, user_id, tarjeta) values ('global', yo, jsonb_build_object('tipo', 'reto', 'id', rid));
    perform public.avisar_reto(rid, 'aceptado');
  else
    raise exception 'No puedes hacer eso' using errcode = '42501';
  end if;
end;
$$;

-- Reto en cualquier estado para la tarjeta del muro. Solo si está pegado en el muro (o es tuyo) y con lo mismo que
-- reto_publico: quiénes, día, estado, ganador y marcador (el marcador solo con el reto aceptado o terminado).
-- reto_publico sigue igual (solo aceptado/terminado) para las apps viejas.
create function public.reto_muro(rid bigint)
returns table (retador uuid, retado uuid, dia date, estado text, ganador uuid, a integer, b integer)
language sql stable security definer set search_path = '' as $$
  select m.retador, m.retado, m.dia, m.estado, m.ganador,
         case when m.estado in ('aceptado', 'terminado') then m.a end,
         case when m.estado in ('aceptado', 'terminado') then m.b end
  from public.marcador_reto(rid) m
  where (select auth.uid()) is not null
    and ((select auth.uid()) in (m.retador, m.retado)
         or exists (select 1 from public.muro x where x.tarjeta ->> 'tipo' = 'reto' and x.tarjeta ->> 'id' = rid::text
                    and (not x.oculto or public.es_admin()) and not public.hay_bloqueo(x.user_id)));
$$;
revoke execute on function public.reto_muro(bigint) from public, anon;
grant execute on function public.reto_muro(bigint) to authenticated;

-- 7. Feed -------------------------------------------------------------------------------------------------------------
-- La firma vieja no devuelve tarjetas (las apps que no saben dibujarlas verían una publicación vacía).
create or replace function public.muro_feed(p_antes timestamptz default null, p_amigos boolean default false, p_limite int default 20)
returns table (
  id bigint, user_id uuid, texto text, dibujo jsonb, created_at timestamptz,
  likes bigint, yo_like boolean, comentarios bigint,
  username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
  lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real
)
language sql stable security definer set search_path = '' as $$
  select m.id, m.user_id, m.texto, m.dibujo, m.created_at,
         (select count(*) from public.muro_likes l where l.post_id = m.id),
         exists (select 1 from public.muro_likes l where l.post_id = m.id and l.user_id = (select auth.uid())),
         (select count(*) from public.muro_comentarios c where c.post_id = m.id and not public.hay_bloqueo(c.user_id)),
         p.username, p.avatar, p.sombrero, p.lentes, p.mascota, p.cagadas,
         p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala
  from public.muro m
  join public.profiles p on p.id = m.user_id
  where (select auth.uid()) is not null
    and m.tarjeta is null
    and (p_antes is null or m.created_at < p_antes)
    and (not m.oculto or m.user_id = (select auth.uid()) or public.es_admin())
    and not public.hay_bloqueo(m.user_id)
    and (not p_amigos
         or m.user_id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = m.user_id))
  order by m.created_at desc, m.id desc
  limit least(greatest(coalesce(p_limite, 20), 1), 50);
$$;

-- Feed con tarjetas (app nueva). Mismas reglas que muro_feed.
create function public.muro_feed_tarjetas(p_antes timestamptz default null, p_amigos boolean default false, p_limite int default 20)
returns table (
  id bigint, user_id uuid, texto text, dibujo jsonb, tarjeta jsonb, created_at timestamptz,
  likes bigint, yo_like boolean, comentarios bigint,
  username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
  lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real
)
language sql stable security definer set search_path = '' as $$
  select m.id, m.user_id, m.texto, m.dibujo, m.tarjeta, m.created_at,
         (select count(*) from public.muro_likes l where l.post_id = m.id),
         exists (select 1 from public.muro_likes l where l.post_id = m.id and l.user_id = (select auth.uid())),
         (select count(*) from public.muro_comentarios c where c.post_id = m.id and not public.hay_bloqueo(c.user_id)),
         p.username, p.avatar, p.sombrero, p.lentes, p.mascota, p.cagadas,
         p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala
  from public.muro m
  join public.profiles p on p.id = m.user_id
  where (select auth.uid()) is not null
    and (p_antes is null or m.created_at < p_antes)
    and (not m.oculto or m.user_id = (select auth.uid()) or public.es_admin())
    and not public.hay_bloqueo(m.user_id)
    and (not p_amigos
         or m.user_id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = m.user_id))
  order by m.created_at desc, m.id desc
  limit least(greatest(coalesce(p_limite, 20), 1), 50);
$$;
revoke execute on function public.muro_feed_tarjetas(timestamptz, boolean, int) from public, anon;
grant execute on function public.muro_feed_tarjetas(timestamptz, boolean, int) to authenticated;
