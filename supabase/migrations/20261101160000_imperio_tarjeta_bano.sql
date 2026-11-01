-- Imperio: presumir el baño en el chat. No se sube ninguna imagen: la tarjeta lleva lo que dibuja el baño y la app lo
-- pinta con el código del juego (lib/imperio/tarjeta_bano.dart).
-- validar_mensaje (última versión: 20261031170000_imperio_cadena.sql) igual que antes más una rama:
--   'bano': una cada 10 minutos; la tarjeta se arma con la fila del usuario (imperio.estado y imperio.esteticas):
--   {edificios: {id: n}, mejoras: [id], esteticas: [est_*], vista: {ocultos?, dedos?, ambiente?}}. Sin saldo ni MJ.
--   Ids y edificios con lista cerrada (igual que edificiosTarjetaBano y mejorasTarjetaBano en la app).

create or replace function public.validar_mensaje()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
begin
  -- auth.uid() es null cuando escribe el servidor (cierre de retos): se respeta el user_id.
  new.user_id := coalesce(auth.uid(), new.user_id);
  new.oculto := false;
  new.created_at := now();
  new.texto := btrim(new.texto);
  if public.sala_publica(new.sala) then new.es_bug := false; end if;
  if new.texto = '' and new.tarjeta is null then
    raise exception 'Mensaje vacío' using errcode = 'P0001';
  end if;
  malo := public.link_peligroso(new.texto);
  if malo is not null then
    raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
  end if;
  if public.sala_publica(new.sala) and (new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') then
    raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
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
      if rollos > 1e12 or rollos > public.imperio_rollos_max(im.mj_total) then
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
        'rollos', least(public.imperio_numero(im.estado ->> 'rollos'), public.imperio_rollos_max(im.mj_total)));
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
      new.tarjeta := jsonb_build_object('tipo', 'bano',
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
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
