-- Imperio: jalar la cadena (prestigio) y presumir la cartera en el chat.
-- El servidor solo cuenta las cagadas reales entre jaladas y lleva el número de jaladas: los rollos los calcula el
-- cliente (lib/imperio/motor.dart) y viajan en el estado como siempre.
-- imperio_cadena(): {cagadas, necesarias, jaladas}. cagadas = las del usuario desde la última jalada (o desde que abrió
--   el Imperio). necesarias = flag cadena_cagadas (valor de todos, sin variantes) o 5.
-- imperio_jalar(): valida y anota la jalada. El cliente reinicia la partida y guarda con imperio_guardar.
-- validar_mensaje (última versión: 20261031150000_imperio_logros_chat.sql) igual que antes más dos ramas:
--   'jalada' {n, rollos}: n tiene que ser la última jalada del usuario y de hace menos de un día, una vez por n.
--   'cartera': una cada 10 minutos; la tarjeta se arma con la fila del usuario (saldo, mj/s, mj/pujo, total, rollos).

alter table public.imperio
  add column jalada_en timestamptz,
  add column jaladas int not null default 0 check (jaladas >= 0);

-- Número no negativo y finito desde un texto del estado (jsonb ->> da texto). Cualquier cosa rara = 0.
create function public.imperio_numero(v text) returns double precision
language plpgsql immutable set search_path = '' as $$
declare
  n double precision;
begin
  if v is null or v !~ '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$' then return 0; end if;
  n := v::double precision;
  if n = 'Infinity'::double precision or n < 0 then return 0; end if;
  return n;
exception when others then
  return 0;
end;
$$;

create function public.imperio_cadena_necesarias() returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select least(greatest(round((f.valor #>> '{}')::numeric), 1), 1000)::int
    from public.imperio_flags f
    where f.clave = 'cadena_cagadas' and f.activo and jsonb_typeof(f.valor) = 'number'
  ), 5);
$$;

create function public.imperio_cadena() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  n bigint;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid;
  if fila.user_id is null then
    return jsonb_build_object('cagadas', 0, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', 0);
  end if;
  select count(*) into n from public.cagadas c
    where c.user_id = uid and c.created_at > coalesce(fila.jalada_en, fila.creado);
  return jsonb_build_object('cagadas', n, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', fila.jaladas);
end;
$$;

create function public.imperio_jalar() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  n bigint;
  total int;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid for update;
  if fila.user_id is null then
    raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
  end if;
  select count(*) into n from public.cagadas c
    where c.user_id = uid and c.created_at > coalesce(fila.jalada_en, fila.creado);
  if n < public.imperio_cadena_necesarias() then
    raise exception 'Todavía te faltan cagadas para jalar la cadena' using errcode = 'P0001';
  end if;
  -- La mejora se compra una vez y la jalada la borra del estado: después de la primera ya no se pide.
  if fila.jaladas = 0 and not (jsonb_typeof(fila.estado -> 'mejoras') = 'array' and (fila.estado -> 'mejoras') ? 'cadena_trono') then
    raise exception 'Todavía no tienes La cadena del trono' using errcode = 'P0001';
  end if;
  update public.imperio set jalada_en = now(), jaladas = jaladas + 1 where user_id = uid
    returning jaladas into total;
  return jsonb_build_object('jaladas', total);
end;
$$;

-- Tope de rollos que da un MJ total (misma fórmula que rollosPorMj en lib/imperio/motor.dart, con los flags de todos).
-- Las tarjetas del chat nunca muestran más rollos que este tope.
create function public.imperio_rollos_max(mj double precision) returns double precision
language sql stable security definer set search_path = '' as $$
  select floor(power(greatest(coalesce(mj, 0), 0) / greatest(coalesce((
           select (f.valor #>> '{}')::double precision from public.imperio_flags f
            where f.clave = 'cadena_divisor' and f.activo and jsonb_typeof(f.valor) = 'number'), 1e10), 1),
         least(greatest(coalesce((
           select (f.valor #>> '{}')::double precision from public.imperio_flags f
            where f.clave = 'cadena_exponente' and f.activo and jsonb_typeof(f.valor) = 'number'), 0.5), 0.1), 1)));
$$;

revoke all on function public.imperio_numero(text) from public, anon;
revoke all on function public.imperio_cadena_necesarias() from public, anon;
revoke all on function public.imperio_rollos_max(double precision) from public, anon;
revoke all on function public.imperio_cadena() from public, anon;
revoke all on function public.imperio_jalar() from public, anon;
grant execute on function public.imperio_cadena() to authenticated;
grant execute on function public.imperio_jalar() to authenticated;

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
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
