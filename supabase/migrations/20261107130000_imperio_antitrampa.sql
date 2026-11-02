-- Antitrampa del Imperio.
--  1. imperio_guardar: tope al ritmo (mps) que manda la app, permitido más justo (x24 en vez de x30) y versión mínima.
--  2. imperio_jalar: además de las cagadas, pide que ya toque al menos un Rollo con los MJ que tiene el servidor.
--  3. Ranking, perfil y estilos: los Rollos nunca pasan de los que dan los MJ (imperio_rollos_max).
--  4. imperio_eventos: id por evento (evento_id) para que un reintento no duplique.
-- La simulación que respalda los números está en test/imperio_antitrampa_test.dart (repite esta fórmula en Dart).

-- El mayor ritmo aceptado. No baja al jalar la cadena: después de jalar el ritmo vuelve a crecer muy rápido
-- (en la simulación, de un guardado al siguiente sube hasta x1e11 contra el anterior, pero nunca más de x21 contra el pico).
alter table public.imperio add column if not exists mps_pico double precision not null default 0;

-- Un id por evento, opcional: la app vieja no lo manda.
alter table public.imperio_eventos add column if not exists evento_id uuid;
create unique index if not exists imperio_eventos_user_evento_key on public.imperio_eventos (user_id, evento_id);

-- La versión de 3 parámetros se borra: con las dos, una llamada sin p_version no sabría cuál usar.
-- La app vieja llama con p_estado, p_mj_total y p_mps, y cae en esta con p_version null.
drop function if exists public.imperio_guardar(jsonb, double precision, double precision);

create or replace function public.imperio_guardar(p_estado jsonb, p_mj_total double precision, p_mps double precision,
                                                  p_version int default null)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  seg double precision;
  permitido double precision;
  nuevo_total double precision;
  pedido_mps double precision := greatest(coalesce(p_mps, 0), 0);
  tope_mps double precision;
  nuevo_mps double precision;
  ritmo double precision;
  recortado boolean := false;
  jaladas_copia int;
  version_minima double precision;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  if p_estado is null or pg_column_size(p_estado) > 65536 then
    raise exception 'estado demasiado grande';
  end if;

  select * into fila from public.imperio where user_id = uid for update;
  if not found then raise exception 'imperio no existe'; end if;

  -- Versión mínima (flag version_minima, número de build). Con la flag puesta, sin p_version cuenta como vieja.
  -- No se guarda nada: la app nueva muestra "Actualiza para seguir jugando"; la vieja sigue en el teléfono sin subir.
  version_minima := coalesce((select (f.valor #>> '{}')::double precision from public.imperio_flags f
    where f.clave = 'version_minima' and f.activo and jsonb_typeof(f.valor) = 'number'), 0);
  if version_minima > 0 and coalesce(p_version, 0) < version_minima then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado,
                              'ignorado', true, 'version_vieja', true);
  end if;

  jaladas_copia := case when jsonb_typeof(p_estado -> 'jaladas') = 'number' then (p_estado ->> 'jaladas')::numeric::int else 0 end;
  if jaladas_copia < fila.jaladas then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado, 'ignorado', true);
  end if;

  seg := greatest(extract(epoch from now() - fila.guardado), 0);

  -- p_mps es Imperio.ritmoEfectivo: max(MJ/s sin efectos, valor del pujo x (20 pujos/s + 10 por Primo)), sin efectos
  -- temporales. Solo sube comprando (edificios, mejoras, Rollos). Tope: x100 sobre el pico de una vez y x10 más por hora
  -- pasada (hasta 24 h). Piso 1000 MJ/s para el que empieza. En la simulación de 21 y 60 días al tope de la mano,
  -- el ritmo nunca pasó x21 su pico en un guardado.
  tope_mps := greatest(fila.mps_pico, fila.mps, 1000) * 100 * power(10, least(seg, 86400) / 3600);
  nuevo_mps := least(pedido_mps, tope_mps);
  ritmo := greatest(fila.mps, nuevo_mps, 1);

  -- Permitido = lo que había + (segundos x 24 + 216000) x ritmo x temporada + 100000.
  --  x24 por segundo pasado: el ritmo base no trae efectos. Lo más que se sostiene es producción x4 (tope de efectos)
  --    con pujos x4 (Turbo, Laxante, fuerza) que además cobran el % del ritmo con efectos, y épicos x10 al 3-6%:
  --    unas 23-24 veces el ritmo base. En la simulación lo sostenido de verdad (guardados de más de 10 min) no pasó de x1,2.
  --  216000 s de ritmo de golpe (7200 x 30, lo mismo que daba antes con tiempo corto): Pujo loco (x777, 13-26 s),
  --    Fiebre (x7, 77-154 s), Lluvia (hasta 900 s), Descargas (900-1350 s por cagada), Ciruela de 2 h (7200 s), Cofre
  --    y Súper plomero (3600 s), regalo de vuelta (4 h). En la simulación lo más que llegó de golpe fueron 152834 s.
  --  Lo que pasa de ahí ya se recortaba antes (Pujo loco con Sagrado y Fiebre encima, varias Ciruelas en un minuto).
  permitido := fila.mj_total + (seg * 24 + 216000) * ritmo
    * public.imperio_temporada_x(fila.guardado - interval '2 hours', now()) + 100000;
  nuevo_total := least(greatest(coalesce(p_mj_total, 0), fila.mj_total), permitido);
  if coalesce(p_mj_total, 0) > nuevo_total then recortado := true; end if;

  update public.imperio
    set estado = p_estado, mj_total = nuevo_total, mps = nuevo_mps, mps_pico = greatest(fila.mps_pico, nuevo_mps),
        guardado = now()
    where user_id = uid;

  return jsonb_build_object('mj_total', nuevo_total, 'recortado', recortado, 'guardado', now());
end $$;
revoke all on function public.imperio_guardar(jsonb, double precision, double precision, int) from public, anon;
grant execute on function public.imperio_guardar(jsonb, double precision, double precision, int) to authenticated;

-- Jalar pide también que ya toque un Rollo con los MJ del servidor. jaladas solo suma, nunca vuelve a 0.
create or replace function public.imperio_jalar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  n := public.imperio_cagadas_tope(uid, coalesce(fila.jalada_en, fila.creado));
  if n < public.imperio_cadena_necesarias() then
    raise exception 'Todavía te faltan cagadas para jalar la cadena' using errcode = 'P0001';
  end if;
  -- La mejora se compra una vez y la jalada la borra del estado: después de la primera ya no se pide.
  if fila.jaladas = 0 and not (jsonb_typeof(fila.estado -> 'mejoras') = 'array' and (fila.estado -> 'mejoras') ? 'cadena_trono') then
    raise exception 'Todavía no tienes La cadena del trono' using errcode = 'P0001';
  end if;
  -- La app guarda justo antes de jalar. Margen 1e-6 porque la app redondea con un épsilon al contar Rollos.
  if public.imperio_rollos_max(fila.mj_total * (1 + 1e-6))
     - (public.imperio_numero(fila.estado ->> 'rollos') + public.imperio_numero(fila.estado ->> 'rollos_gastados')) < 1 then
    raise exception 'Todavía te faltan MJ para el siguiente Rollo' using errcode = 'P0001';
  end if;
  update public.imperio set jalada_en = now(), jaladas = jaladas + 1 where user_id = uid
    returning jaladas into total;
  return jsonb_build_object('jaladas', total);
end;
$$;

-- Ranking: Rollos con tope en los que dan los MJ (y 1e15 como antes, para que el bigint no se desborde).
create or replace function public.imperio_ranking(p_alcance text default 'amigos', p_orden text default 'mj')
returns table(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
              lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real,
              mj_total double precision, rollos bigint, yo boolean, movimiento text, jaladas integer, puesto bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select p.id as uid, p.username as nombre, p.avatar as av, p.sombrero as so, p.lentes as le, p.mascota as ma,
           p.cagadas as ca, p.lentes_x as lx, p.lentes_y as ly, p.sombrero_x as sx, p.sombrero_y as sy,
           p.lentes_escala as le_e, p.sombrero_escala as so_e,
           coalesce(i.mj_total, 0) as mj,
           least(public.imperio_numero(i.estado->>'rollos') + public.imperio_numero(i.estado->>'rollos_gastados'),
                 public.imperio_rollos_max(coalesce(i.mj_total, 0) * (1 + 1e-6)), 1e15)::bigint as rl,
           p.id = (select auth.uid()) as es_yo, p.movimiento as mov, i.jaladas as ja
    from public.imperio i
    join public.profiles p on p.id = i.user_id
    where (select auth.uid()) is not null
      and p_alcance in ('amigos', 'global')
      and p_orden in ('mj', 'rollos')
      and (p_alcance = 'global'
           or p.id = (select auth.uid())
           or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
      and (p.id = (select auth.uid()) or i.mj_total > 0)
      and not public.hay_bloqueo(p.id)
  ),
  orden as (
    select b.*, row_number() over (order by case when p_orden = 'rollos' then b.rl else 0 end desc, b.mj desc, b.nombre) as n
    from base b
  )
  select o.uid, o.nombre, o.av, o.so, o.le, o.ma, o.ca, o.lx, o.ly, o.sx, o.sy, o.le_e, o.so_e,
         o.mj, o.rl, o.es_yo, o.mov, o.ja, o.n
  from orden o
  where o.n <= 100 or o.es_yo
  order by o.n;
$$;

-- Perfil: mismo tope de Rollos.
create or replace function public.imperio_perfil(p_usuario uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'mj_total', i.mj_total,
           'rollos', least(public.imperio_numero(i.estado->>'rollos') + public.imperio_numero(i.estado->>'rollos_gastados'),
                           public.imperio_rollos_max(i.mj_total * (1 + 1e-6)), 1e15)::bigint,
           'jaladas', i.jaladas,
           'mps', i.mps,
           'movimiento', p.movimiento)
  from public.imperio i
  join public.profiles p on p.id = i.user_id
  where i.user_id = p_usuario
    and (select auth.uid()) is not null
    and (i.mj_total > 0 or i.jaladas > 0)
    and not public.hay_bloqueo(p_usuario);
$$;

-- Estilos con precio en Rollos: cuentan los Rollos que tiene (sin los gastados), con el mismo tope.
create or replace function public.imperio_estilo_comprar(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  est public.imperio_estilos_catalogo;
  mult double precision;
  mis_cagadas int;
  mi_total double precision;
  mis_rollos double precision;
  lista text[];
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into est from public.imperio_estilos_catalogo c where c.id = p_id;
  if not found then raise exception 'Ese estilo no existe' using errcode = 'P0001'; end if;
  if est.mj <= 0 and est.rollos <= 0 and est.cagadas <= 0 then
    raise exception 'Ese estilo es gratis' using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.imperio_estilos e where e.user_id = uid and e.id = p_id) then
    mult := coalesce((select (f.valor #>> '{}')::double precision from public.imperio_flags f
      where f.clave = 'estilo_precio_mult' and f.activo and jsonb_typeof(f.valor) = 'number'), 1);
    mult := least(greatest(mult, 0.01), 1000);

    select p.cagadas into mis_cagadas from public.profiles p where p.id = uid;
    if coalesce(mis_cagadas, 0) < est.cagadas then
      raise exception 'Te faltan cagadas: necesitas %', est.cagadas using errcode = 'P0001';
    end if;

    select im.mj_total,
           least(public.imperio_numero(im.estado ->> 'rollos'), public.imperio_rollos_max(im.mj_total * (1 + 1e-6)))
      into mi_total, mis_rollos
      from public.imperio im where im.user_id = uid;
    -- Por encima: el saldo real está en el teléfono, aquí solo se mira lo ganado en total.
    if est.mj > 0 and coalesce(mi_total, 0) < est.mj * mult then
      raise exception 'Te faltan MJ' using errcode = 'P0001';
    end if;
    if est.rollos > 0 and coalesce(mis_rollos, 0) < est.rollos then
      raise exception 'Te faltan Rollos' using errcode = 'P0001';
    end if;

    insert into public.imperio_estilos (user_id, id) values (uid, p_id) on conflict do nothing;
  end if;

  select coalesce(array_agg(e.id order by e.creado), '{}') into lista from public.imperio_estilos e where e.user_id = uid;
  return jsonb_build_object('comprados', to_jsonb(lista));
end;
$$;

-- Eventos: el id que manda la app (uuid) evita duplicados si el lote se reintenta. Sin id, como antes.
create or replace function public.imperio_registrar(p_eventos jsonb)
returns integer
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  uid uuid := auth.uid();
  hoy int;
  cupo int;
  guardados int;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array' then return 0; end if;

  -- Un lote a la vez por usuario, para que dos llamadas juntas no se salten el tope.
  perform pg_advisory_xact_lock(hashtext('imperio_eventos:' || uid::text));
  select count(*) into hoy from public.imperio_eventos where user_id = uid and creado >= date_trunc('day', now());
  cupo := least(100, 2000 - hoy);
  if cupo <= 0 then return 0; end if;

  insert into public.imperio_eventos (user_id, evento, datos, sesion, version_app, cliente_ms, evento_id)
  select uid,
         e->>'evento',
         case when jsonb_typeof(e->'datos') = 'object' then e->'datos' else '{}'::jsonb end,
         case when jsonb_typeof(e->'sesion') = 'string'
               and e->>'sesion' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then (e->>'sesion')::uuid end,
         case when jsonb_typeof(e->'version') = 'string' then left(e->>'version', 40) end,
         case when jsonb_typeof(e->'ms') = 'number' and (e->>'ms')::numeric between 0 and 1e14
              then floor((e->>'ms')::numeric)::bigint end,
         case when jsonb_typeof(e->'id') = 'string'
               and e->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then (e->>'id')::uuid end
    from jsonb_array_elements(p_eventos) with ordinality as t(e, orden)
   where t.orden <= 100
     and jsonb_typeof(e) = 'object'
     and jsonb_typeof(e->'evento') = 'string'
     and e->>'evento' ~ '^[a-z0-9_]{1,40}$'
     and (e->'datos' is null or jsonb_typeof(e->'datos') in ('object', 'null'))
     and (e->'datos' is null or pg_column_size(e->'datos') <= 4096)
   order by t.orden
   limit cupo
  on conflict (user_id, evento_id) do nothing;
  get diagnostics guardados = row_count;
  return guardados;
end $$;

-- Que PostgREST vea la firma nueva de imperio_guardar.
notify pgrst, 'reload schema';
