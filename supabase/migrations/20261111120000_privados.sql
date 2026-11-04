-- Privados: chats de uno a uno dentro del Baño.
--
-- 1. Reusa public.mensajes con sala 'dm:<uuidA>:<uuidB>' (minúsculas, A < B en orden de bytes): una sola sala por
--    pareja, la arme quien la arme. hilo queda null (el check de soporte lo exige).
-- 2. profiles.mensajes_de ('todos' | 'amigos' | 'nadie', por defecto 'amigos'): quién te puede escribir primero.
--    'amigos' = gente que TÚ sigues (follows.follower = tú). A quien ya te escribió siempre le puedes responder.
-- 3. Ayudantes: dm_soy_parte(sala), dm_otro(sala), dm_puedo_escribir(sala) y la RPC dm_puedo(otro) para la app.
-- 4. RLS de mensajes: en un dm leen y escriben solo las dos partes (sin bloqueo); el admin lee para moderar.
-- 5. validar_mensaje: igual que en vivo; los dm cuentan como la Cloaca (sin es_bug, sin teléfonos ni correos)
--    y no aceptan tarjetas.
-- 6. dm_bandeja(): una fila por conversación con el perfil del otro y el último mensaje.
-- 7. Push: trigger avisar_dm llama a la Edge Function notificaciones con {tipo:'dm', id}. Categoría nueva
--    'privados' en push_ajustes (push_avisos_mios, push_aviso y push_resumen_mio la conocen).

begin;

-- ---------------------------------------------------------------- 1. Salas dm
alter table public.mensajes drop constraint mensajes_sala_check;
alter table public.mensajes add constraint mensajes_sala_check check (
  sala = any (array['global', 'es', 'en', 'soporte'])
  or sala ~ '^cloaca:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or (sala ~ '^dm:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and split_part(sala, ':', 2) collate "C" < split_part(sala, ':', 3) collate "C"));

-- La bandeja busca por cada lado de la pareja: un índice por lado, solo sobre los dm.
create index mensajes_dm_a_idx on public.mensajes (split_part(sala, ':', 2), sala, id desc) where sala like 'dm:%';
create index mensajes_dm_autor_idx on public.mensajes (user_id, created_at desc) where sala like 'dm:%';
create index mensajes_dm_b_idx on public.mensajes (split_part(sala, ':', 3), sala, id desc) where sala like 'dm:%';

-- ---------------------------------------------------------------- 2. Quién te puede escribir
alter table public.profiles
  add column mensajes_de text not null default 'amigos' check (mensajes_de in ('todos', 'amigos', 'nadie'));
grant update (mensajes_de) on public.profiles to authenticated;

-- ---------------------------------------------------------------- 3. Ayudantes
-- La sala de dos usuarios, en el mismo orden que salaDm() de la app.
create function public.dm_sala(a uuid, b uuid)
returns text language sql immutable set search_path = '' as $$
  select 'dm:' || least(a::text collate "C", b::text collate "C") || ':' || greatest(a::text collate "C", b::text collate "C");
$$;

create function public.dm_soy_parte(p_sala text)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_sala ~ '^dm:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and (select auth.uid())::text in (split_part(p_sala, ':', 2), split_part(p_sala, ':', 3));
$$;
revoke all on function public.dm_soy_parte(text) from public, anon;
grant execute on function public.dm_soy_parte(text) to authenticated;

-- El otro lado de una sala dm donde estoy yo (null si no estoy).
create function public.dm_otro(p_sala text)
returns uuid language sql stable security definer set search_path = '' as $$
  select case when not public.dm_soy_parte(p_sala) then null
              when split_part(p_sala, ':', 2) = (select auth.uid())::text then split_part(p_sala, ':', 3)::uuid
              else split_part(p_sala, ':', 2)::uuid end;
$$;
revoke all on function public.dm_otro(text) from public, anon;
grant execute on function public.dm_otro(text) to authenticated;

-- Puedo escribir en esta sala si soy parte, el otro existe, no hay bloqueo en ningún sentido y:
-- el otro deja escribir a todos, o tiene 'amigos' y me sigue (follower = el otro, followed = yo), o ya me escribió aquí.
create function public.dm_puedo_escribir(p_sala text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.dm_soy_parte(p_sala) and exists (
    select 1 from public.profiles o
    where o.id = public.dm_otro(p_sala)
      and o.id <> (select auth.uid())
      and not public.hay_bloqueo(o.id)
      and (o.mensajes_de = 'todos'
           or (o.mensajes_de = 'amigos'
               and exists (select 1 from public.follows f where f.follower = o.id and f.followed = (select auth.uid())))
           or exists (select 1 from public.mensajes m where m.sala = p_sala and m.user_id = o.id))), false);
$$;
revoke all on function public.dm_puedo_escribir(text) from public, anon;
grant execute on function public.dm_puedo_escribir(text) to authenticated;

-- Para la app: ¿muestro el botón MENSAJE en el perfil de [otro]?
create function public.dm_puedo(otro uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(otro is not null and otro <> (select auth.uid())
                  and public.dm_puedo_escribir(public.dm_sala((select auth.uid()), otro)), false);
$$;
revoke all on function public.dm_puedo(uuid) from public, anon;
grant execute on function public.dm_puedo(uuid) to authenticated;

-- ---------------------------------------------------------------- 4. RLS
drop policy mensajes_select on public.mensajes;
create policy mensajes_select on public.mensajes for select using (
  (public.sala_publica(sala) and not public.hay_bloqueo(user_id)
   and ((not oculto) or user_id = (select auth.uid()) or public.es_admin()))
  or (sala = 'soporte' and (hilo = (select auth.uid()) or public.es_admin()))
  or (sala like 'cloaca:%' and ((public.cloaca_es_mia(sala) and not public.hay_bloqueo(user_id)
                                 and ((not oculto) or user_id = (select auth.uid())))
                                or public.es_admin()))
  or (sala like 'dm:%' and ((public.dm_soy_parte(sala) and not public.hay_bloqueo(user_id)
                             and ((not oculto) or user_id = (select auth.uid())))
                            or public.es_admin())));
-- En un dm ni el admin escribe por otro: solo las dos partes, con dm_puedo_escribir.
drop policy mensajes_insert on public.mensajes;
create policy mensajes_insert on public.mensajes for insert with check (
  user_id = (select auth.uid())
  and case when sala like 'dm:%' then public.dm_puedo_escribir(sala)
           else (public.sala_publica(sala) or hilo = (select auth.uid()) or public.es_admin()
                 or public.cloaca_es_mia(sala)) end);

-- ---------------------------------------------------------------- 5. validar_mensaje (copia de la versión en vivo)
CREATE OR REPLACE FUNCTION public.validar_mensaje()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  total bigint;
  malo text;
  t text;
  c record;
  d record;
  r public.cagadas;
  im public.imperio;
  rollos numeric;
  e jsonb;
  v jsonb;
  g public.imperio_regalos;
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
    t := new.tarjeta ->> 'tipo';
    select count(*) into total from public.cagadas where user_id = new.user_id;
    if t = 'hito' then
      if not ((new.tarjeta ->> 'n')::int = any (public.hitos())) or (new.tarjeta ->> 'n')::int > total then
        raise exception 'Todavía no llegas a ese número' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'hito', 'n', (new.tarjeta ->> 'n')::int,
        'reina', coalesce((select genero = 'mujer' from public.profiles where id = new.user_id), false));
    elsif t = 'desbloqueo' then
      select * into d from public.desbloqueos x where x.emoji = new.tarjeta ->> 'emoji' limit 1;
      if d is null or d.minimo > total then
        raise exception 'Todavía no has desbloqueado eso' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'desbloqueo', 'emoji', d.emoji, 'ranura', d.ranura, 'minimo', d.minimo);
    elsif t = 'cagada' then
      select x.id, x.tipo, x.peso, x.created_at into c from public.cagadas x
        where x.id = (new.tarjeta ->> 'id')::bigint and x.user_id = new.user_id;
      if c is null or c.tipo is null then
        raise exception 'Esa cagada no existe o no dijiste qué salió' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'cagada', 'mojon', c.tipo, 'peso', c.peso,
        'n', (select count(*) from public.cagadas x where x.user_id = new.user_id and x.created_at <= c.created_at));
    elsif t = 'racha' then
      select * into r from public.cagadas x
        where x.id = (new.tarjeta ->> 'id')::bigint and x.user_id = new.user_id;
      if r.id is null or public.racha_del_dia(r) < 2 then
        raise exception 'Esa cagada no es racha' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.tarjeta ->> 'tipo' = 'racha' and (x.tarjeta ->> 'id')::bigint = r.id) then
        raise exception 'Esa racha ya salió en el chat' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'racha', 'id', r.id, 'n', public.racha_del_dia(r));
    elsif t in ('reto', 'reto_fin') then
      if not exists (select 1 from public.retos x where x.id = (new.tarjeta ->> 'id')::bigint
                     and new.user_id in (x.retador, x.retado)
                     and x.estado = case t when 'reto' then 'aceptado' else 'terminado' end) then
        raise exception 'Ese reto no es tuyo' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', t, 'id', (new.tarjeta ->> 'id')::bigint);
    elsif t = 'logro_imperio' then
      if coalesce(new.tarjeta ->> 'id', '') !~ '^[a-z0-9_]{1,40}$'
         or not exists (select 1 from public.imperio x where x.user_id = new.user_id
                        and jsonb_typeof(x.estado -> 'logros') = 'array'
                        and (x.estado -> 'logros') ? (new.tarjeta ->> 'id')) then
        raise exception 'Todavía no tienes ese logro del Imperio' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'logro_imperio', 'id', new.tarjeta ->> 'id');
    elsif t = 'jalada' then
      select * into im from public.imperio x where x.user_id = new.user_id;
      if im.user_id is null or coalesce(new.tarjeta ->> 'n', '') !~ '^[0-9]{1,9}$'
         or (new.tarjeta ->> 'n')::int <> im.jaladas or im.jaladas < 1
         or im.jalada_en is null or im.jalada_en < now() - interval '1 day' then
        raise exception 'Esa jalada no existe o ya pasó' using errcode = 'P0001';
      end if;
      if coalesce(new.tarjeta ->> 'rollos', '') !~ '^[0-9]{1,13}$' then
        raise exception 'Rollos fuera de rango' using errcode = 'P0001';
      end if;
      rollos := (new.tarjeta ->> 'rollos')::numeric;
      if rollos > 1e12 or rollos > public.imperio_rollos_tope(im) then
        raise exception 'Rollos fuera de rango' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.user_id = new.user_id and x.tarjeta ->> 'tipo' = 'jalada'
                 and x.tarjeta ->> 'n' = im.jaladas::text) then
        raise exception 'Esa jalada ya salió en el chat' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'jalada', 'n', im.jaladas, 'rollos', rollos::bigint);
    elsif t = 'cartera' then
      select * into im from public.imperio x where x.user_id = new.user_id;
      if im.user_id is null then
        raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.user_id = new.user_id and x.tarjeta ->> 'tipo' = 'cartera'
                 and x.created_at > now() - interval '10 minutes') then
        raise exception 'Espera un rato para volver a presumir tu cartera' using errcode = 'P0001';
      end if;
      -- Los números salen de la fila del usuario (lo último que guardó), nunca de lo que manda el cliente.
      new.tarjeta := jsonb_build_object('tipo', 'cartera',
        'saldo', public.imperio_numero(im.estado ->> 'saldo'),
        'mps', public.imperio_numero(coalesce(im.estado ->> '_mps_edificios', im.mps::text)),
        'pujo', public.imperio_numero(im.estado ->> '_pujo'),
        'mj_total', greatest(coalesce(im.mj_total, 0), 0),
        'jaladas', greatest(im.jaladas, 0),
        'rollos', least(public.imperio_numero(im.estado ->> 'rollos'),
                        public.imperio_rollos_tope(im)));
    elsif t = 'bano' then
      select * into im from public.imperio x where x.user_id = new.user_id;
      if im.user_id is null then
        raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.user_id = new.user_id and x.tarjeta ->> 'tipo' = 'bano'
                 and x.created_at > now() - interval '10 minutes') then
        raise exception 'Espera un rato para volver a presumir tu baño' using errcode = 'P0001';
      end if;
      -- Solo lo que dibuja el baño, sacado de la fila (nunca del cliente). Lo que venga mal se vuelve vacío.
      e := case when jsonb_typeof(im.estado) = 'object' then im.estado else '{}'::jsonb end;
      v := case when jsonb_typeof(e -> 'vista') = 'object' then e -> 'vista' else '{}'::jsonb end;
      new.tarjeta := jsonb_build_object('tipo', 'bano', 'mudanzas', greatest(im.mudanzas, 0),
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
      -- Solo la pone imperio_regalar (servidor). Lleva quién da (el autor del mensaje) y a quién va.
      if coalesce(current_setting('imperio.tarjeta_servidor', true), '') <> '1'
         or coalesce(new.tarjeta ->> 'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
      end if;
      select * into g from public.imperio_regalos x where x.id = (new.tarjeta ->> 'id')::uuid and x.de = new.user_id;
      if g.id is null then
        raise exception 'Ese regalo no existe' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'regalo', 'id', g.id, 'de', g.de, 'para', g.para,
        'de_nombre', coalesce((select p.username from public.profiles p where p.id = g.de), ''),
        'para_nombre', coalesce((select p.username from public.profiles p where p.id = g.para), ''));
    elsif t = 'imperio' then
      -- Tarjeta genérica del Imperio {emoji, titulo, linea}: solo desde el servidor (imperio_tarjeta_chat).
      if coalesce(current_setting('imperio.tarjeta_servidor', true), '') <> '1' then
        raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'imperio',
        'emoji', left(coalesce(nullif(btrim(new.tarjeta ->> 'emoji'), ''), '💩'), 8),
        'titulo', left(coalesce(btrim(new.tarjeta ->> 'titulo'), ''), 60),
        'linea', left(coalesce(btrim(new.tarjeta ->> 'linea'), ''), 140));
    elsif t = 'cloaca' then
      -- Ganadora de la liga semanal: solo la pone cloaca_cerrar_semana (servidor) en la sala general. Los datos salen
      -- del historial de esa semana, no de lo que venga en la tarjeta.
      if coalesce(current_setting('imperio.tarjeta_servidor', true), '') <> '1'
         or coalesce(new.tarjeta ->> 'cloaca_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         or coalesce(new.tarjeta ->> 'semana', '') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
      end if;
      select h.* into d from public.cloaca_historial h
       where h.semana = (new.tarjeta ->> 'semana')::date and h.cloaca_id = (new.tarjeta ->> 'cloaca_id')::uuid
         and h.puesto = 1;
      if d.cloaca_id is null then
        raise exception 'Esa Cloaca no ganó esa semana' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'cloaca', 'semana', d.semana, 'cloaca_id', d.cloaca_id,
        'nombre', d.nombre, 'emoji', d.emoji, 'puntos', d.puntos, 'miembros', d.miembros,
        'rollos', public.imperio_flag_numero('cloaca_premio_rollos', 2, 0, 1000)::int);
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$function$;


-- ---------------------------------------------------------------- 6. Bandeja
-- Una fila por conversación mía: el otro (columnas de columnasAvatar en lib/accesorios.dart) y el último mensaje
-- que puedo ver. Sin las conversaciones con bloqueo. Más reciente primero.
create function public.dm_bandeja()
returns table (sala text, otro uuid, perfil jsonb, mensaje_id bigint, texto text, autor uuid, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  with yo as (select (select auth.uid()) as id),
  ultimos as (
    select distinct on (m.sala) m.sala, m.id, m.texto, m.user_id, m.created_at
    from public.mensajes m, yo
    where m.sala like 'dm:%'
      and (split_part(m.sala, ':', 2) = yo.id::text or split_part(m.sala, ':', 3) = yo.id::text)
      and ((not m.oculto) or m.user_id = yo.id)
    order by m.sala, m.id desc
  )
  select u.sala, p.id,
         jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar, 'sombrero', p.sombrero,
           'lentes', p.lentes, 'mascota', p.mascota, 'cagadas', p.cagadas, 'movimiento', p.movimiento,
           'lentes_x', p.lentes_x, 'lentes_y', p.lentes_y, 'sombrero_x', p.sombrero_x, 'sombrero_y', p.sombrero_y,
           'lentes_escala', p.lentes_escala, 'sombrero_escala', p.sombrero_escala),
         u.id, u.texto, u.user_id, u.created_at
  from ultimos u
  join public.profiles p on p.id = public.dm_otro(u.sala)
  where not public.hay_bloqueo(p.id)
  order by u.id desc
  limit 200;
$$;
revoke all on function public.dm_bandeja() from public, anon;
grant execute on function public.dm_bandeja() to authenticated;

-- ---------------------------------------------------------------- 7. Push
create function public.avisar_dm()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.sala not like 'dm:%' then return new; end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')),
    body := jsonb_build_object('tipo', 'dm', 'id', new.id));
  return new;
end; $$;
revoke execute on function public.avisar_dm() from public, anon, authenticated;
create trigger mensajes_avisar_dm after insert on public.mensajes for each row execute function public.avisar_dm();

alter table public.push_ajustes add column privados boolean not null default true;

create or replace function public.push_avisos_mios()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a public.push_ajustes;
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;
  select * into a from public.push_ajustes where user_id = auth.uid();
  return jsonb_build_object(
    'cagadas', coalesce(a.cagadas, true),
    'rachas', coalesce(a.rachas, true),
    'ganadores', coalesce(a.ganadores, true),
    'cierres', coalesce(a.cierres, true),
    'chat', coalesce(a.chat, true),
    'retos', coalesce(a.retos, true),
    'seguidores', coalesce(a.seguidores, true),
    'imperio', coalesce(a.imperio, true) and coalesce(a.poceta, true) and coalesce(a.racha, true),
    'privados', coalesce(a.privados, true)
  );
end;
$$;

create or replace function public.push_aviso(p_clave text, p_activo boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;
  if p_activo is null then raise exception 'activo vacío'; end if;
  if p_clave = 'imperio' then
    insert into public.push_ajustes (user_id, imperio, poceta, racha) values (auth.uid(), p_activo, p_activo, p_activo)
      on conflict (user_id) do update set imperio = excluded.imperio, poceta = excluded.poceta, racha = excluded.racha;
    return;
  end if;
  if p_clave not in ('cagadas', 'rachas', 'ganadores', 'cierres', 'chat', 'retos', 'seguidores', 'privados') then
    raise exception 'clave desconocida: %', p_clave;
  end if;
  execute format(
    'insert into public.push_ajustes (user_id, %1$I) values ($1, $2) on conflict (user_id) do update set %1$I = excluded.%1$I',
    p_clave) using auth.uid(), p_activo;
end;
$$;

-- Igual que en 20261108150000_avisos_menos.sql, con la novena categoría: 'dm' cuenta como 'privados'.
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
        when tipo = 'dm' then 'privados'
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
    + (coalesce(a.imperio, true) and coalesce(a.poceta, true) and coalesce(a.racha, true))::int
    + coalesce(a.privados, true)::int;

  return jsonb_build_object(
    'dias', 7,
    'total', coalesce(v_total, 0),
    'por_tipo', coalesce(v_tipos, '{}'::jsonb),
    'por_categoria', coalesce(v_categorias, '{}'::jsonb),
    'prendidas', v_prendidas,
    'categorias', 9
  );
end;
$$;

commit;

notify pgrst, 'reload schema';
