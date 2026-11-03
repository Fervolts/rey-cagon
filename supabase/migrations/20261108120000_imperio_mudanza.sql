-- Imperio: la Mudanza 🏠 (segunda capa de reinicio) y el Llavero 🔑.
--
-- Mudarse cambia de casa (Rancho, Casa, Quinta, Mansión, Palacio, Palacio II...), reinicia la corrida, los Rollos, la
-- Plomería y las jaladas de la casa, y da Llaves para el Llavero. El servidor lleva la cuenta buena:
--  1. Columnas nuevas en imperio: mudanzas, mj_base (mj_total al mudarse), mj_casa (MJ ganados en la casa), jaladas_base,
--     mudanza_en y llaves_ganadas.
--  2. Rollos de la casa = imperio_rollos_max(MJ de la casa) x (1 + mudanzas). Los MJ de la casa van en su propia columna
--     (mj_casa) porque mj_total - mj_base pierde todo con números grandes (1e34 + 1e13 = 1e34 en double). En el Rancho
--     (mudanzas = 0) los MJ de la casa son mj_total: da lo mismo que antes y las apps viejas (build 63 y antes) siguen
--     igual. Se usa en jalar, guardar (que también lleva la cuenta de mj_casa), ranking, perfil, estilos y en las
--     tarjetas del chat.
--  3. imperio_mudar(): revisa Rollos de la casa, jaladas en la casa y cagadas reales desde la llegada (tope 3 por día) y
--     cuenta las Llaves. Requisitos y fórmula en imperio_flags con los mismos defaults que la app (lib/imperio/flags.dart).
--  4. imperio_guardar: ignora el guardado con otra cuenta de mudanzas (partida vieja de antes de mudarse o inventada) o
--     con un Llavero que cuesta más Llaves de las ganadas; las bases y las Llaves ganadas las pone el servidor.
--  5. imperio_cadena manda también mudanzas, cagadas_casa, llaves_ganadas, mj_base y mj_casa (la app nueva se pone al día).
--  6. Los reinicios pendientes también vuelven la casa a 0.
-- La simulación de 300 días está en test/imperio_mudanza_ritmo_test.dart.

alter table public.imperio add column if not exists mudanzas int not null default 0;
alter table public.imperio add column if not exists mj_base double precision not null default 0;
alter table public.imperio add column if not exists mj_casa double precision not null default 0;
alter table public.imperio add column if not exists jaladas_base int not null default 0;
alter table public.imperio add column if not exists mudanza_en timestamptz;
alter table public.imperio add column if not exists llaves_ganadas int not null default 0;

-- Número de imperio_flags con default y rango (los mismos que Ajustes.desdeFlags en la app).
create or replace function public.imperio_flag_numero(p_clave text, p_defecto double precision, p_min double precision,
                                                      p_max double precision)
returns double precision
language sql stable security definer set search_path = '' as $$
  select least(greatest(coalesce((select (f.valor #>> '{}')::double precision from public.imperio_flags f
                                   where f.clave = p_clave and f.activo and jsonb_typeof(f.valor) = 'number'), p_defecto),
                        p_min), p_max);
$$;

-- Rollos que tocan en la casa con p_mj MJ ganados en ella: los del Rancho con los MJ divididos por
-- mudanza_divisor_x ^ mudanzas, x (1 + mudanzas). En el Rancho (0 mudanzas) es imperio_rollos_max tal cual.
create or replace function public.imperio_rollos_casa(p_mj double precision, p_mudanzas int)
returns double precision
language sql stable security definer set search_path = '' as $$
  select public.imperio_rollos_max(p_mj / power(public.imperio_flag_numero('mudanza_divisor_x', 15, 1, 1e12),
                                                greatest(coalesce(p_mudanzas, 0), 0)))
         * (1 + greatest(coalesce(p_mudanzas, 0), 0));
$$;

-- MJ ganados en la casa. En el Rancho son todos (mj_total); después de mudarse, los que suma imperio_guardar en mj_casa.
create or replace function public.imperio_mj_casa(p_fila public.imperio)
returns double precision
language sql stable security definer set search_path = '' as $$
  select case when coalesce(p_fila.mudanzas, 0) <= 0 then greatest(coalesce(p_fila.mj_total, 0), 0)
              else greatest(coalesce(p_fila.mj_casa, 0), 0) end;
$$;

-- Rollos de la casa de una fila (saldo + gastados en la Plomería), con tope en los que dan los MJ de la casa.
-- Margen 1e-6 porque la app redondea con un épsilon al contar Rollos.
create or replace function public.imperio_rollos_de(p_fila public.imperio)
returns double precision
language sql stable security definer set search_path = '' as $$
  select least(public.imperio_numero(p_fila.estado ->> 'rollos') + public.imperio_numero(p_fila.estado ->> 'rollos_gastados'),
               public.imperio_rollos_casa(public.imperio_mj_casa(p_fila) * (1 + 1e-6),
                                          p_fila.mudanzas));
$$;

-- Llaves que cuesta un Llavero {id: nivel}. Igual que costoLlavero en lib/imperio/catalogo.dart:
--   cimientos (1, 2, 3... hasta 20), mayordomo (3, 5, 8), camion_mudanza (2, 4, 6... hasta 5), ahorros (1, 2, 3... hasta 10),
--   primo_extra (4, 8), alquiler_barato (2, 3, 4... hasta 5). Ids desconocidos no cuestan (la app los ignora).
create or replace function public.imperio_llavero_costo(p_llavero jsonb)
returns bigint
language sql immutable set search_path = '' as $$
  select coalesce(sum(case x.k
      when 'cimientos' then least(x.n, 20) + least(x.n, 20) * (least(x.n, 20) - 1) / 2
      when 'mayordomo' then case least(x.n, 3) when 0 then 0 when 1 then 3 when 2 then 8 else 16 end
      when 'camion_mudanza' then 2 * least(x.n, 5) + least(x.n, 5) * (least(x.n, 5) - 1)
      when 'ahorros' then least(x.n, 10) + least(x.n, 10) * (least(x.n, 10) - 1) / 2
      when 'primo_extra' then case least(x.n, 2) when 0 then 0 when 1 then 4 else 12 end
      when 'alquiler_barato' then 2 * least(x.n, 5) + least(x.n, 5) * (least(x.n, 5) - 1) / 2
      else 0 end), 0)::bigint
  from (select e.k, greatest(least(floor(case when jsonb_typeof(e.v) = 'number' then (e.v)::numeric else 0 end), 1000), 0)::bigint as n
          from jsonb_each(case when jsonb_typeof(p_llavero) = 'object' then p_llavero else '{}'::jsonb end) e(k, v)) x;
$$;

revoke all on function public.imperio_flag_numero(text, double precision, double precision, double precision) from public, anon, authenticated;
revoke all on function public.imperio_rollos_casa(double precision, int) from public, anon, authenticated;
revoke all on function public.imperio_rollos_de(public.imperio) from public, anon, authenticated;
revoke all on function public.imperio_llavero_costo(jsonb) from public, anon, authenticated;

-- Mudarse. Devuelve {ok, llaves, mudanzas, mj_base} o {ok: false, motivo: 'rollos' | 'jaladas' | 'cagadas'}.
-- La app guarda justo antes (como al jalar), así los Rollos de la fila son los de ahora.
create or replace function public.imperio_mudar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  pedidos double precision;
  rollos double precision;
  cagadas bigint;
  llaves int;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid for update;
  if fila.user_id is null then
    raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
  end if;

  pedidos := public.imperio_flag_numero('mudanza_rollos', 1e8, 1, 1e20)
             * power(public.imperio_flag_numero('mudanza_rollos_subida', 30, 1, 1e6), greatest(fila.mudanzas, 0));
  rollos := public.imperio_rollos_de(fila);
  if rollos < pedidos then
    return jsonb_build_object('ok', false, 'motivo', 'rollos');
  end if;
  if fila.jaladas - fila.jaladas_base < round(public.imperio_flag_numero('mudanza_jaladas', 9, 0, 1000)) then
    return jsonb_build_object('ok', false, 'motivo', 'jaladas');
  end if;
  cagadas := public.imperio_cagadas_tope(uid, coalesce(fila.mudanza_en, fila.creado));
  if cagadas < round(public.imperio_flag_numero('mudanza_cagadas', 30, 0, 10000)) then
    return jsonb_build_object('ok', false, 'motivo', 'cagadas');
  end if;

  -- Llaves = piso((Rollos de la casa / pedidos) ^ exponente x factor). Igual que Imperio.llavesPorGanar.
  llaves := least(floor(power(rollos / pedidos, public.imperio_flag_numero('mudanza_llaves_exp', 1.0 / 3, 0.05, 1))
                        * public.imperio_flag_numero('mudanza_llaves_x', 3, 0.1, 1000) + 1e-9), 1000000)::int;

  -- Los Rollos y las bases también en el estado, para que el ranking y las tarjetas no lean la casa de antes
  -- mientras llega el guardado siguiente.
  update public.imperio
     set mudanzas = mudanzas + 1, mj_base = mj_total, mj_casa = 0, jaladas_base = jaladas, mudanza_en = now(),
         llaves_ganadas = llaves_ganadas + llaves,
         estado = case when jsonb_typeof(estado) = 'object' then estado else '{}'::jsonb end
                  || jsonb_build_object('rollos', 0, 'rollos_gastados', 0, 'mudanzas', fila.mudanzas + 1,
                                        'mj_base', fila.mj_total, 'mj_casa', 0, 'jaladas_base', fila.jaladas,
                                        'llaves_ganadas', fila.llaves_ganadas + llaves)
   where user_id = uid;
  return jsonb_build_object('ok', true, 'llaves', llaves, 'mudanzas', fila.mudanzas + 1, 'mj_base', fila.mj_total);
end;
$$;
revoke all on function public.imperio_mudar() from public, anon;
grant execute on function public.imperio_mudar() to authenticated;

-- La cadena manda también la casa. Las apps viejas ignoran las claves nuevas.
create or replace function public.imperio_cadena()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  n bigint;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid;
  if fila.user_id is null then
    return jsonb_build_object('cagadas', 0, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', 0,
                              'mudanzas', 0, 'cagadas_casa', 0, 'llaves_ganadas', 0, 'mj_base', 0, 'mj_casa', 0);
  end if;
  n := public.imperio_cagadas_tope(uid, coalesce(fila.jalada_en, fila.creado));
  return jsonb_build_object('cagadas', n, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', fila.jaladas,
                            'mudanzas', fila.mudanzas,
                            'cagadas_casa', public.imperio_cagadas_tope(uid, coalesce(fila.mudanza_en, fila.creado)),
                            'llaves_ganadas', fila.llaves_ganadas, 'mj_base', fila.mj_base,
                            'mj_casa', public.imperio_mj_casa(fila));
end;
$$;
revoke all on function public.imperio_cadena() from public, anon;
grant execute on function public.imperio_cadena() to authenticated;

-- Jalar: el Rollo que falta se cuenta con los MJ de la casa x factor de casa.
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
  if public.imperio_rollos_casa(public.imperio_mj_casa(fila) * (1 + 1e-6), fila.mudanzas)
     - (public.imperio_numero(fila.estado ->> 'rollos') + public.imperio_numero(fila.estado ->> 'rollos_gastados')) < 1 then
    raise exception 'Todavía te faltan MJ para el siguiente Rollo' using errcode = 'P0001';
  end if;
  update public.imperio set jalada_en = now(), jaladas = jaladas + 1 where user_id = uid
    returning jaladas into total;
  return jsonb_build_object('jaladas', total);
end;
$$;
revoke all on function public.imperio_jalar() from public, anon;
grant execute on function public.imperio_jalar() to authenticated;

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
  margen double precision;
  pedido_casa double precision;
  nuevo_casa double precision := 0;
  pedido_mps double precision := greatest(coalesce(p_mps, 0), 0);
  tope_mps double precision;
  nuevo_mps double precision;
  ritmo double precision;
  recortado boolean := false;
  jaladas_copia int;
  version_minima double precision;
  mudanzas_copia int;
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

  -- Mudanza: la copia tiene que estar en la misma casa que el servidor. Una copia de antes de mudarse (o con más
  -- mudanzas de las que hizo imperio_mudar) no se guarda; la app se pone al día con imperio_cadena. Sin la clave
  -- (apps viejas) cuenta como 0, igual que la fila de quien nunca se mudó.
  mudanzas_copia := case when jsonb_typeof(p_estado -> 'mudanzas') = 'number' then (p_estado ->> 'mudanzas')::numeric::int else 0 end;
  if mudanzas_copia <> fila.mudanzas then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado, 'ignorado', true,
                              'mudanzas', fila.mudanzas);
  end if;
  -- Llavero: lo comprado no puede costar más Llaves de las ganadas al mudarse.
  if public.imperio_llavero_costo(p_estado -> 'llavero') > fila.llaves_ganadas then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado, 'ignorado', true,
                              'mudanzas', fila.mudanzas);
  end if;
  -- Las bases de la casa y las Llaves ganadas las pone el servidor (la app no las puede subir a mano).
  if fila.mudanzas > 0 or fila.llaves_ganadas > 0 then
    p_estado := p_estado || jsonb_build_object('mudanzas', fila.mudanzas, 'mj_base', fila.mj_base,
                                               'jaladas_base', fila.jaladas_base, 'llaves_ganadas', fila.llaves_ganadas);
  end if;

  seg := greatest(extract(epoch from now() - fila.guardado), 0);

  -- p_mps es Imperio.ritmoEfectivo: max(MJ/s sin efectos, valor del pujo x (20 pujos/s + 10 por Primo)), sin efectos
  -- temporales. Solo sube comprando (edificios, mejoras, Rollos, Llavero). Tope: x100 sobre el pico de una vez y x10 más por hora
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
  margen := (seg * 24 + 216000) * ritmo * public.imperio_temporada_x(fila.guardado - interval '2 hours', now()) + 100000;
  permitido := fila.mj_total + margen;
  nuevo_total := least(greatest(coalesce(p_mj_total, 0), fila.mj_total), permitido);
  if coalesce(p_mj_total, 0) > nuevo_total then recortado := true; end if;
  -- MJ de la casa (después de mudarse): con números grandes mj_total ya no se mueve, así que se cuentan aparte, con el
  -- mismo tope. Nunca bajan con un guardado y la app recibe el valor bueno de vuelta.
  if fila.mudanzas > 0 then
    pedido_casa := case when jsonb_typeof(p_estado -> 'mj_casa') = 'number' then greatest((p_estado ->> 'mj_casa')::double precision, 0)
                        else 0 end;
    nuevo_casa := least(greatest(pedido_casa, fila.mj_casa), fila.mj_casa + margen);
    if pedido_casa > nuevo_casa then recortado := true; end if;
    p_estado := p_estado || jsonb_build_object('mj_casa', nuevo_casa);
  end if;

  update public.imperio
    set estado = p_estado, mj_total = nuevo_total, mj_casa = nuevo_casa, mps = nuevo_mps, mps_pico = greatest(fila.mps_pico, nuevo_mps),
        guardado = now()
    where user_id = uid;

  return jsonb_build_object('mj_total', nuevo_total, 'recortado', recortado, 'guardado', now())
         || case when fila.mudanzas > 0 then jsonb_build_object('mj_casa', nuevo_casa) else '{}'::jsonb end;
end $$;
revoke all on function public.imperio_guardar(jsonb, double precision, double precision, int) from public, anon;
grant execute on function public.imperio_guardar(jsonb, double precision, double precision, int) to authenticated;

-- Ranking: Rollos de la casa con tope en los que dan los MJ de la casa (y 1e15, para que el bigint no se desborde).
-- Columna nueva al final: mudanzas (la app vieja la ignora). Por Rollos ordena primero por casa.
-- Cambia el tipo de salida: hay que borrarla antes (los grants se vuelven a dar abajo).
drop function if exists public.imperio_ranking(text, text);
create or replace function public.imperio_ranking(p_alcance text default 'amigos', p_orden text default 'mj')
returns table(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
              lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real,
              mj_total double precision, rollos bigint, yo boolean, movimiento text, jaladas integer, puesto bigint,
              mudanzas integer)
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
           least(public.imperio_rollos_de(i), 1e15)::bigint as rl, greatest(i.mudanzas, 0) as mu,
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
    select b.*, row_number() over (order by case when p_orden = 'rollos' then b.mu else 0 end desc,
                                       case when p_orden = 'rollos' then b.rl else 0 end desc, b.mj desc, b.nombre) as n
    from base b
  )
  select o.uid, o.nombre, o.av, o.so, o.le, o.ma, o.ca, o.lx, o.ly, o.sx, o.sy, o.le_e, o.so_e,
         o.mj, o.rl, o.es_yo, o.mov, o.ja, o.n, o.mu
  from orden o
  where o.n <= 100 or o.es_yo
  order by o.n;
$$;

revoke all on function public.imperio_ranking(text, text) from public, anon;
grant execute on function public.imperio_ranking(text, text) to authenticated;

-- Perfil: Rollos de la casa y en qué casa va (mudanzas).
create or replace function public.imperio_perfil(p_usuario uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'mj_total', i.mj_total,
           'rollos', least(public.imperio_rollos_de(i), 1e15)::bigint,
           'mudanzas', greatest(i.mudanzas, 0),
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


-- Estilos con precio en Rollos: cuentan los Rollos que tiene (sin los gastados), con el tope de la casa.
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
           least(public.imperio_numero(im.estado ->> 'rollos'),
                 public.imperio_rollos_casa(public.imperio_mj_casa(im) * (1 + 1e-6), im.mudanzas))
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


-- Tarjetas del chat: el tope de Rollos es el de la casa y la tarjeta del baño dice en qué casa va.
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
      if rollos > 1e12 or rollos > public.imperio_rollos_casa(public.imperio_mj_casa(im), im.mudanzas) then
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
                        public.imperio_rollos_casa(public.imperio_mj_casa(im), im.mudanzas)));
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

-- Reinicios pendientes: también vuelven al Rancho sin Llaves.
create or replace function public.imperio_reinicios_aplicar() returns int
language plpgsql security definer set search_path = public as $$
declare
  r public.imperio_reinicios_pendientes;
  fila public.imperio;
  nuevas int;
  hechos int := 0;
begin
  for r in select * from public.imperio_reinicios_pendientes where aplicado is null order by id loop
    continue when r.build_minimo > public.imperio_build_play();
    continue when public.imperio_build_de(r.user_id) < r.build_minimo;
    select * into fila from public.imperio where user_id = r.user_id for update;
    if not found then
      update public.imperio_reinicios_pendientes set aplicado = now(), respaldo = 'null'::jsonb where id = r.id;
      continue;
    end if;
    continue when fila.guardado > now() - interval '3 minutes';
    continue when exists (select 1 from public.imperio_eventos e where e.user_id = r.user_id and e.creado > now() - interval '3 minutes');
    nuevas := coalesce(fila.jaladas, 0) + 1;
    update public.imperio
       set estado = jsonb_build_object('jaladas', nuevas), jaladas = nuevas, mj_total = 0, mps = 0, mps_pico = 0,
           jalada_en = now(), guardado = now(), mudanzas = 0, mj_base = 0, mj_casa = 0, jaladas_base = 0, llaves_ganadas = 0,
           mudanza_en = null
     where user_id = r.user_id;
    update public.imperio_reinicios_pendientes set aplicado = now(), respaldo = to_jsonb(fila) where id = r.id;
    hechos := hechos + 1;
  end loop;
  return hechos;
end $$;

revoke execute on function public.imperio_reinicios_aplicar() from public, anon, authenticated;

notify pgrst, 'reload schema';
