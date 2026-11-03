-- Imperio: ABDICAR 👑 (tercera capa de reinicio), las Coronas y La Corte.
--
-- Abdicar deja la casa (vuelves al Rancho, o a la casa del Heraldo), las Llaves y el Llavero, y además todo lo que ya
-- pierde la mudanza. Da Coronas: cada Corona sin gastar sube la producción y con ellas se compra La Corte, que dura
-- entre abdicaciones. El servidor lleva la cuenta buena:
--  1. Columnas nuevas en imperio: abdicaciones, abdicado_en y coronas_ganadas.
--  2. imperio_corte_costo(): lo que cuesta La Corte en Coronas (igual que costoCorte en lib/imperio/catalogo.dart).
--  3. imperio_abdicar(): revisa mudanzas, Llaves ganadas y cagadas reales del reinado (tope 3 por día), cuenta las
--     Coronas y aplica lo que hace La Corte en el servidor (Heraldo, Tesorero y Mayordomo real). Requisitos y fórmula
--     en imperio_flags con los mismos defaults que la app (lib/imperio/flags.dart).
--  4. imperio_mudar: el Maestro de obras pide menos Rollos (las Llaves se cuentan sin descuento).
--  5. imperio_guardar: ignora el guardado con otra cuenta de abdicaciones o con La Corte más cara que las Coronas
--     ganadas; el Mayordomo real regala el primer nivel del Mayordomo del Llavero.
--  6. imperio_cadena, imperio_ranking, imperio_perfil y la tarjeta del baño mandan también las abdicaciones.
--  7. Los reinicios pendientes también borran las dinastías.
-- La simulación de 600 días está en test/imperio_mudanza_ritmo_test.dart (SIM_ABDICAR=1).

begin;

alter table public.imperio add column if not exists abdicaciones int not null default 0;
alter table public.imperio add column if not exists abdicado_en timestamptz;
alter table public.imperio add column if not exists coronas_ganadas int not null default 0;

-- Nivel de p_id en un mapa de niveles (La Corte o el Llavero), entre 0 y p_max. Lo que venga mal cuenta como 0.
create or replace function public.imperio_corte_nivel(p_mapa jsonb, p_id text, p_max int)
returns int
language sql immutable set search_path = '' as $$
  select greatest(least(floor(case when jsonb_typeof(p_mapa) = 'object' and jsonb_typeof(p_mapa -> p_id) = 'number'
                                   then (p_mapa ->> p_id)::numeric else 0 end), p_max), 0)::int;
$$;

-- Coronas que cuesta La Corte (suma de los precios de cada nivel comprado), con los mismos topes que la app.
--  bufon y catador: 1, 2, 3... ; heraldo: 4, 8, 16 ; tesorero y maestro_obras: 2, 4, 6... ; mayordomo_real: 6.
create or replace function public.imperio_corte_costo(p_corte jsonb)
returns bigint
language sql immutable set search_path = '' as $$
  select coalesce(sum(case x.k
      when 'bufon' then least(x.n, 20) + least(x.n, 20) * (least(x.n, 20) - 1) / 2
      when 'heraldo' then case least(x.n, 3) when 0 then 0 when 1 then 4 when 2 then 12 else 28 end
      when 'tesorero' then 2 * least(x.n, 5) + least(x.n, 5) * (least(x.n, 5) - 1)
      when 'maestro_obras' then 2 * least(x.n, 5) + least(x.n, 5) * (least(x.n, 5) - 1)
      when 'catador' then least(x.n, 4) + least(x.n, 4) * (least(x.n, 4) - 1) / 2
      when 'mayordomo_real' then case when x.n >= 1 then 6 else 0 end
      else 0 end), 0)::bigint
  from (select e.k, greatest(least(floor(case when jsonb_typeof(e.v) = 'number' then (e.v)::numeric else 0 end), 1000), 0)::bigint as n
          from jsonb_each(case when jsonb_typeof(p_corte) = 'object' then p_corte else '{}'::jsonb end) e(k, v)) x;
$$;

revoke all on function public.imperio_corte_nivel(jsonb, text, int) from public, anon, authenticated;
revoke all on function public.imperio_corte_costo(jsonb) from public, anon, authenticated;

-- Abdicar. Requisitos: abdicar_mudanzas mudanzas en esta dinastía, abdicar_llaves Llaves ganadas y abdicar_cagadas
-- cagadas reales desde la última abdicación (o desde siempre), con tope de 3 por día.
-- Coronas = piso((Llaves ganadas / abdicar_llaves) ^ abdicar_coronas_exponente x abdicar_coronas_factor). Igual que
-- Imperio.coronasPorGanar.
create or replace function public.imperio_abdicar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  corte jsonb;
  pedidas double precision;
  cagadas bigint;
  coronas int;
  casa int;
  llaves int;
  llavero jsonb;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid for update;
  if fila.user_id is null then
    raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
  end if;
  corte := case when jsonb_typeof(fila.estado -> 'corte') = 'object' then fila.estado -> 'corte' else '{}'::jsonb end;

  if fila.mudanzas < round(public.imperio_flag_numero('abdicar_mudanzas', 4, 1, 1000)) then
    return jsonb_build_object('ok', false, 'motivo', 'mudanzas');
  end if;
  pedidas := public.imperio_flag_numero('abdicar_llaves', 87, 1, 1e6);
  if fila.llaves_ganadas < pedidas then
    return jsonb_build_object('ok', false, 'motivo', 'llaves');
  end if;
  cagadas := public.imperio_cagadas_tope(uid, fila.abdicado_en);
  if cagadas < round(public.imperio_flag_numero('abdicar_cagadas', 60, 0, 10000)) then
    return jsonb_build_object('ok', false, 'motivo', 'cagadas');
  end if;

  coronas := least(floor(power(fila.llaves_ganadas / pedidas, public.imperio_flag_numero('abdicar_coronas_exponente', 0.5, 0.05, 1))
                         * public.imperio_flag_numero('abdicar_coronas_factor', 3, 0.1, 1000) + 1e-9), 1000000)::int;
  -- La Corte en el servidor: el Heraldo te deja en la casa 1, 2 o 3; el Tesorero guarda el 10% de las Llaves ganadas
  -- por nivel (con el Llavero vacío) y el Mayordomo real deja el Mayordomo del Llavero en el nivel 1.
  casa := public.imperio_corte_nivel(corte, 'heraldo', 3);
  llaves := floor(fila.llaves_ganadas * 0.1 * public.imperio_corte_nivel(corte, 'tesorero', 5) + 1e-9)::int;
  llavero := case when public.imperio_corte_nivel(corte, 'mayordomo_real', 1) >= 1 then '{"mayordomo": 1}'::jsonb
                  else '{}'::jsonb end;

  -- Como en la mudanza, los Rollos y las bases también en el estado para que el ranking y las tarjetas no lean la
  -- dinastía de antes mientras llega el guardado siguiente.
  update public.imperio
     set abdicaciones = abdicaciones + 1, coronas_ganadas = coronas_ganadas + coronas, abdicado_en = now(),
         mudanzas = casa, llaves_ganadas = llaves, mj_base = mj_total, mj_casa = 0, jaladas_base = jaladas, mudanza_en = now(),
         estado = case when jsonb_typeof(estado) = 'object' then estado else '{}'::jsonb end
                  || jsonb_build_object('rollos', 0, 'rollos_gastados', 0, 'mudanzas', casa, 'mj_base', fila.mj_total,
                                        'mj_casa', 0, 'jaladas_base', fila.jaladas, 'llaves_ganadas', llaves,
                                        'abdicaciones', fila.abdicaciones + 1,
                                        'coronas_ganadas', fila.coronas_ganadas + coronas, 'llavero', llavero)
   where user_id = uid;
  return jsonb_build_object('ok', true, 'coronas', coronas, 'abdicaciones', fila.abdicaciones + 1, 'mudanzas', casa,
                            'llaves_ganadas', llaves, 'mj_base', fila.mj_total);
end $$;

revoke all on function public.imperio_abdicar() from public, anon;
grant execute on function public.imperio_abdicar() to authenticated;

-- MJ de la casa: en el Rancho de la primera dinastía son mj_total; después de mudarse o de abdicar van aparte.
CREATE OR REPLACE FUNCTION public.imperio_mj_casa(p_fila imperio)
 RETURNS double precision
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when coalesce(p_fila.mudanzas, 0) <= 0 and coalesce(p_fila.abdicaciones, 0) <= 0 then greatest(coalesce(p_fila.mj_total, 0), 0)
              else greatest(coalesce(p_fila.mj_casa, 0), 0) end;
$function$;

-- Mudarse: el Maestro de obras baja los Rollos pedidos.
CREATE OR REPLACE FUNCTION public.imperio_mudar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  pedidos double precision;
  rollos double precision;
  cagadas bigint;
  llaves int;
  descuento double precision;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid for update;
  if fila.user_id is null then
    raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
  end if;

  pedidos := public.imperio_flag_numero('mudanza_rollos', 1e8, 1, 1e20)
             * power(public.imperio_flag_numero('mudanza_rollos_subida', 30, 1, 1e6), greatest(fila.mudanzas, 0));
  rollos := public.imperio_rollos_de(fila);
  -- Maestro de obras (La Corte): pide 10% menos Rollos por nivel, nunca menos de la mitad. Las Llaves se cuentan
  -- contra lo pedido sin descuento (igual que Imperio.llavesPorGanar).
  descuento := greatest(0.5, 1 - 0.1 * public.imperio_corte_nivel(fila.estado -> 'corte', 'maestro_obras', 5));
  if rollos < pedidos * descuento then
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
$function$;

revoke all on function public.imperio_mudar() from public, anon;
grant execute on function public.imperio_mudar() to authenticated;

-- La Cadena manda también abdicaciones, Coronas ganadas y cagadas del reinado (la app nueva se pone al día).
CREATE OR REPLACE FUNCTION public.imperio_cadena()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  n bigint;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid;
  if fila.user_id is null then
    return jsonb_build_object('cagadas', 0, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', 0,
                              'mudanzas', 0, 'cagadas_casa', 0, 'llaves_ganadas', 0, 'mj_base', 0, 'mj_casa', 0,
                              'abdicaciones', 0, 'coronas_ganadas', 0, 'cagadas_reinado', 0);
  end if;
  n := public.imperio_cagadas_tope(uid, coalesce(fila.jalada_en, fila.creado));
  return jsonb_build_object('cagadas', n, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', fila.jaladas,
                            'mudanzas', fila.mudanzas,
                            'cagadas_casa', public.imperio_cagadas_tope(uid, coalesce(fila.mudanza_en, fila.creado)),
                            'llaves_ganadas', fila.llaves_ganadas, 'mj_base', fila.mj_base,
                            'mj_casa', public.imperio_mj_casa(fila),
                            'abdicaciones', fila.abdicaciones, 'coronas_ganadas', fila.coronas_ganadas,
                            'cagadas_reinado', public.imperio_cagadas_tope(uid, fila.abdicado_en));
end;
$function$;

revoke all on function public.imperio_cadena() from public, anon;
grant execute on function public.imperio_cadena() to authenticated;

-- Guardar: misma dinastía, La Corte pagada con Coronas ganadas y el Mayordomo real en el Llavero.
CREATE OR REPLACE FUNCTION public.imperio_guardar(p_estado jsonb, p_mj_total double precision, p_mps double precision, p_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  seg double precision;
  permitido double precision;
  nuevo_total double precision;
  margen double precision;
  premios_s double precision;
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
  abdicaciones_copia int;
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
  -- Abdicar: igual que la mudanza, la copia tiene que ser de la misma dinastía. Sin la clave cuenta como 0.
  abdicaciones_copia := case when jsonb_typeof(p_estado -> 'abdicaciones') = 'number' then (p_estado ->> 'abdicaciones')::numeric::int else 0 end;
  if abdicaciones_copia <> fila.abdicaciones then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado, 'ignorado', true,
                              'mudanzas', fila.mudanzas, 'abdicaciones', fila.abdicaciones);
  end if;
  -- La Corte: lo comprado no puede costar más Coronas de las ganadas al abdicar.
  if public.imperio_corte_costo(p_estado -> 'corte') > fila.coronas_ganadas then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado, 'ignorado', true,
                              'mudanzas', fila.mudanzas, 'abdicaciones', fila.abdicaciones);
  end if;
  -- Llavero: lo comprado no puede costar más Llaves de las ganadas al mudarse. El Mayordomo real de La Corte regala
  -- el primer nivel del Mayordomo (3 Llaves).
  if public.imperio_llavero_costo(p_estado -> 'llavero')
     - (case when public.imperio_corte_nivel(p_estado -> 'corte', 'mayordomo_real', 1) >= 1
                  and public.imperio_corte_nivel(p_estado -> 'llavero', 'mayordomo', 3) >= 1 then 3 else 0 end)
     > fila.llaves_ganadas then
    return jsonb_build_object('mj_total', fila.mj_total, 'recortado', false, 'guardado', fila.guardado, 'ignorado', true,
                              'mudanzas', fila.mudanzas);
  end if;
  -- Las bases de la casa y las Llaves ganadas las pone el servidor (la app no las puede subir a mano).
  if fila.mudanzas > 0 or fila.llaves_ganadas > 0 or fila.abdicaciones > 0 then
    p_estado := p_estado || jsonb_build_object('mudanzas', fila.mudanzas, 'mj_base', fila.mj_base,
                                               'jaladas_base', fila.jaladas_base, 'llaves_ganadas', fila.llaves_ganadas,
                                               'abdicaciones', fila.abdicaciones, 'coronas_ganadas', fila.coronas_ganadas);
  end if;

  seg := greatest(extract(epoch from now() - fila.guardado), 0);

  -- p_mps es Imperio.ritmoEfectivo: max(MJ/s sin efectos, valor del pujo x (20 pujos/s + 10 por Primo)), sin efectos
  -- temporales. Solo sube comprando (edificios, mejoras, Rollos, Llavero). Tope: x100 sobre el pico de una vez y x10 más por hora
  -- pasada (hasta 24 h). Piso 1000 MJ/s para el que empieza. En la simulación de 21 y 60 días al tope de la mano,
  -- el ritmo nunca pasó x21 su pico en un guardado.
  tope_mps := greatest(fila.mps_pico, fila.mps, 1000) * 100 * power(10, least(seg, 86400) / 3600);
  nuevo_mps := least(pedido_mps, tope_mps);
  ritmo := greatest(fila.mps, nuevo_mps, 1);

  -- Premios de apuesta del Cagadón (reto_apuesta_cobrar) cobrados desde 10 minutos antes del guardado anterior, en
  -- segundos de producción: hasta 2 x 60 min = 7200 s por reto ganado. La app los paga con MJ/s sin efectos, que es
  -- menor o igual que ritmo. Los 10 minutos cubren un guardado que ya iba en camino al cobrar; un premio puede
  -- contar en más de un guardado de esos 10 minutos, pero nunca más de esos 7200 s. Las devoluciones no cuentan:
  -- solo devuelven saldo y no suben mj_total.
  premios_s := 60 * coalesce((select sum(case when r.retador = uid then r.cobro_retador else r.cobro_retado end)
    from public.retos r
    where r.ganador = uid and not r.apuesta_anulada
      and ((r.retador = uid and r.cobrado_retador > fila.guardado - interval '10 minutes')
        or (r.retado = uid and r.cobrado_retado > fila.guardado - interval '10 minutes'))), 0);

  -- Permitido = lo que había + (segundos x 24 + 216000 + premios) x ritmo x temporada + 100000.
  --  x24 por segundo pasado: el ritmo base no trae efectos. Lo más que se sostiene es producción x4 (tope de efectos)
  --    con pujos x4 (Turbo, Laxante, fuerza) que además cobran el % del ritmo con efectos, y épicos x10 al 3-6%:
  --    unas 23-24 veces el ritmo base. En la simulación lo sostenido de verdad (guardados de más de 10 min) no pasó de x1,2.
  --  216000 s de ritmo de golpe (7200 x 30, lo mismo que daba antes con tiempo corto): Pujo loco (x777, 13-26 s),
  --    Fiebre (x7, 77-154 s), Lluvia (hasta 900 s), Descargas (900-1350 s por cagada), Ciruela de 2 h (7200 s), Cofre
  --    y Súper plomero (3600 s), regalo de vuelta (4 h). En la simulación lo más que llegó de golpe fueron 152834 s.
  --  Lo que pasa de ahí ya se recortaba antes (Pujo loco con Sagrado y Fiebre encima, varias Ciruelas en un minuto).
  margen := (seg * 24 + 216000 + premios_s) * ritmo * public.imperio_temporada_x(fila.guardado - interval '2 hours', now()) + 100000;
  permitido := fila.mj_total + margen;
  nuevo_total := least(greatest(coalesce(p_mj_total, 0), fila.mj_total), permitido);
  if coalesce(p_mj_total, 0) > nuevo_total then recortado := true; end if;
  -- MJ de la casa (después de mudarse): con números grandes mj_total ya no se mueve, así que se cuentan aparte, con el
  -- mismo tope. Nunca bajan con un guardado y la app recibe el valor bueno de vuelta. Después de abdicar también,
  -- aunque el Heraldo no te deje en una casa nueva.
  if fila.mudanzas > 0 or fila.abdicaciones > 0 then
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
         || case when fila.mudanzas > 0 or fila.abdicaciones > 0 then jsonb_build_object('mj_casa', nuevo_casa) else '{}'::jsonb end;
end $function$;

revoke all on function public.imperio_guardar(jsonb, double precision, double precision, int) from public, anon;
grant execute on function public.imperio_guardar(jsonb, double precision, double precision, int) to authenticated;

-- Ranking: columna nueva al final, abdicaciones (la app vieja la ignora). Por Rollos ordena primero por dinastía y
-- luego por casa. Cambia el tipo de salida: hay que borrarla antes (los grants se vuelven a dar abajo).
drop function if exists public.imperio_ranking(text, text);
CREATE OR REPLACE FUNCTION public.imperio_ranking(p_alcance text DEFAULT 'amigos'::text, p_orden text DEFAULT 'mj'::text)
 RETURNS TABLE(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real, mj_total double precision, rollos bigint, yo boolean, movimiento text, jaladas integer, puesto bigint, mudanzas integer, abdicaciones integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with base as (
    select p.id as uid, p.username as nombre, p.avatar as av, p.sombrero as so, p.lentes as le, p.mascota as ma,
           p.cagadas as ca, p.lentes_x as lx, p.lentes_y as ly, p.sombrero_x as sx, p.sombrero_y as sy,
           p.lentes_escala as le_e, p.sombrero_escala as so_e,
           coalesce(i.mj_total, 0) as mj,
           least(public.imperio_rollos_de(i), 1e15)::bigint as rl, greatest(i.mudanzas, 0) as mu,
           greatest(i.abdicaciones, 0) as ab,
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
    select b.*, row_number() over (order by case when p_orden = 'rollos' then b.ab else 0 end desc,
                                       case when p_orden = 'rollos' then b.mu else 0 end desc,
                                       case when p_orden = 'rollos' then b.rl else 0 end desc, b.mj desc, b.nombre) as n
    from base b
  )
  select o.uid, o.nombre, o.av, o.so, o.le, o.ma, o.ca, o.lx, o.ly, o.sx, o.sy, o.le_e, o.so_e,
         o.mj, o.rl, o.es_yo, o.mov, o.ja, o.n, o.mu, o.ab
  from orden o
  where o.n <= 100 or o.es_yo
  order by o.n;
$function$;

revoke all on function public.imperio_ranking(text, text) from public, anon;
grant execute on function public.imperio_ranking(text, text) to authenticated;

-- Perfil: en qué dinastía va.
CREATE OR REPLACE FUNCTION public.imperio_perfil(p_usuario uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
           'mj_total', i.mj_total,
           'rollos', least(public.imperio_rollos_de(i), 1e15)::bigint,
           'mudanzas', greatest(i.mudanzas, 0),
           'abdicaciones', greatest(i.abdicaciones, 0),
           'jaladas', i.jaladas,
           'mps', i.mps,
           'movimiento', p.movimiento)
  from public.imperio i
  join public.profiles p on p.id = i.user_id
  where i.user_id = p_usuario
    and (select auth.uid()) is not null
    and (i.mj_total > 0 or i.jaladas > 0)
    and not public.hay_bloqueo(p_usuario);
$function$;

-- Los reinicios pendientes también borran las dinastías (La Corte va en el estado, que ya se vacía).
CREATE OR REPLACE FUNCTION public.imperio_reinicios_aplicar()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
           mudanza_en = null, abdicaciones = 0, coronas_ganadas = 0, abdicado_en = null
     where user_id = r.user_id;
    update public.imperio_reinicios_pendientes set aplicado = now(), respaldo = to_jsonb(fila) where id = r.id;
    hechos := hechos + 1;
  end loop;
  return hechos;
end $function$;

revoke execute on function public.imperio_reinicios_aplicar() from public, anon, authenticated;

-- validar_mensaje (versión en vivo, última en 20261108130000_imperio_regalos.sql) igual, más las abdicaciones en la
-- tarjeta del baño.
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
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$function$;


commit;

notify pgrst, 'reload schema';
