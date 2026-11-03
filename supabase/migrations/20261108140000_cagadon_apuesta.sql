-- Cagadón con apuesta: los dos se juegan minutos de producción del Imperio (0, 15, 30 o 60).
--  1. Quien reta elige la apuesta y la paga al retar; quien acepta la paga al aceptar. Cada uno la descuenta de SU
--     producción en la app (si no le alcanza, paga lo que tiene) y avisa qué fracción pagó (pago_*, de 0 a 1).
--  2. Al cerrar el reto (cerrar_retos, sin cambios) el ganador cobra el doble de lo que pagó, en minutos de su propia
--     producción. El que pierde no recibe nada. Empate, rechazo, cancelación o reto vencido sin aceptar: cada uno
--     recupera lo que pagó.
--  3. Un solo cobro por persona y reto (cobrado_*). Cobrar sin haber pagado deja una sospecha.
--  4. imperio_guardar deja pasar los premios cobrados en los últimos 10 minutos antes del guardado anterior: el
--     premio sube mj_total de golpe y sin esto podía chocar con el tope.
--  5. La app 63 no sabe de apuestas: retar desde ella es sin apuesta (no manda apuesta_min), y si acepta con
--     responder_reto un reto con apuesta, la apuesta se anula y el que retó recupera lo suyo.
-- Los MJ no se compran con dinero: la apuesta es solo de producción del juego.

alter table public.retos
  add column if not exists apuesta_min int not null default 0 check (apuesta_min in (0, 15, 30, 60)),
  add column if not exists apuesta_anulada boolean not null default false,
  add column if not exists pago_retador real check (pago_retador between 0 and 1),
  add column if not exists pago_retado real check (pago_retado between 0 and 1),
  add column if not exists cobro_retador double precision,
  add column if not exists cobro_retado double precision,
  add column if not exists cobrado_retador timestamptz,
  add column if not exists cobrado_retado timestamptz;

-- Para el tope de imperio_guardar: premios cobrados hace poco.
create index if not exists retos_cobrado_retador on public.retos (retador, cobrado_retador) where cobrado_retador is not null;
create index if not exists retos_cobrado_retado on public.retos (retado, cobrado_retado) where cobrado_retado is not null;

insert into public.imperio_flags (clave, valor, nota) values
  ('apuesta_max_min', '60', 'Tope de la apuesta del Cagadón en minutos de producción; 0 apaga las apuestas')
on conflict (clave) do nothing;

-- Tope de la apuesta. Sin la flag vale 60, igual que el default de la app.
create or replace function public.apuesta_tope() returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((select (f.valor #>> '{}')::double precision from public.imperio_flags f
    where f.clave = 'apuesta_max_min' and f.activo and jsonb_typeof(f.valor) = 'number'), 60)::int
$$;
revoke all on function public.apuesta_tope() from public, anon, authenticated;

-- El Imperio prendido (flag imperio_activo). Sin la flag, prendido.
create or replace function public.apuesta_imperio_activo() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select (f.valor #>> '{}')::boolean from public.imperio_flags f
    where f.clave = 'imperio_activo' and f.activo and jsonb_typeof(f.valor) = 'boolean'), true)
$$;
revoke all on function public.apuesta_imperio_activo() from public, anon, authenticated;

-- Igual que antes, más la apuesta. Los campos de pago y cobro los pone el servidor, no la app.
create or replace function public.validar_reto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  tope int;
begin
  new.retador := auth.uid();
  new.dia := (now() at time zone 'America/Caracas')::date;
  new.estado := 'pendiente';
  new.ganador := null;
  if not exists (select 1 from public.follows f where f.follower = new.retador and f.followed = new.retado) then
    raise exception 'Solo puedes retar a gente que sigues' using errcode = 'P0001';
  end if;
  if public.hay_bloqueo(new.retado) then
    raise exception 'No puedes retar a esa persona' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.retos r
             where least(r.retador, r.retado) = least(new.retador, new.retado)
               and greatest(r.retador, r.retado) = greatest(new.retador, new.retado)
               and r.dia = new.dia and r.estado in ('pendiente', 'aceptado', 'terminado')) then
    raise exception 'Ya tienen un Cagadón hoy' using errcode = 'P0001';
  end if;

  new.apuesta_min := coalesce(new.apuesta_min, 0);
  new.apuesta_anulada := false;
  new.pago_retado := null;
  new.cobro_retador := null;
  new.cobro_retado := null;
  new.cobrado_retador := null;
  new.cobrado_retado := null;
  if new.apuesta_min = 0 then
    new.pago_retador := null;
    return new;
  end if;
  tope := public.apuesta_tope();
  if tope <= 0 or not public.apuesta_imperio_activo() then
    raise exception 'Las apuestas están apagadas' using errcode = 'P0001';
  end if;
  if new.apuesta_min > tope then
    raise exception 'Esa apuesta pasa del tope' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.imperio i where i.user_id = new.retador and i.mj_total > 0) then
    raise exception 'Abre el Imperio antes de apostar' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.imperio i where i.user_id = new.retado and i.mj_total > 0) then
    raise exception 'Esa persona todavía no juega al Imperio: reta sin apuesta' using errcode = 'P0001';
  end if;
  -- null = no pagó (cobrar así deja sospecha).
  if new.pago_retador is not null then
    new.pago_retador := least(greatest(new.pago_retador, 0), 1);
  end if;
  return new;
end;
$$;

-- Igual que antes. Lo único nuevo: aceptar por aquí (app 63) un reto con apuesta la anula.
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
  elsif accion = 'rechazar' and yo = r.retado then
    update public.retos set estado = 'rechazado' where id = rid;
    perform public.avisar_reto(rid, 'rechazado');
  elsif accion = 'aceptar' and yo = r.retado then
    update public.retos set estado = 'aceptado', apuesta_anulada = (r.apuesta_min > 0) where id = rid;
    insert into public.mensajes (sala, user_id, tarjeta) values ('global', yo, jsonb_build_object('tipo', 'reto', 'id', rid));
    perform public.avisar_reto(rid, 'aceptado');
  else
    raise exception 'No puedes hacer eso' using errcode = '42501';
  end if;
end;
$$;

-- Aceptar desde la app nueva. p_apuesta tiene que ser la del reto (la que vio en pantalla) o 0 = acepto sin apuesta
-- (no juega al Imperio o lo tiene apagado): entonces se anula y el que retó recupera lo suyo.
-- p_fraccion: cuánto de la apuesta pudo pagar (0 a 1).
create or replace function public.aceptar_reto_apuesta(rid bigint, p_apuesta int, p_fraccion double precision)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.retos;
  yo uuid := auth.uid();
  anular boolean;
begin
  select * into r from public.retos where id = rid for update;
  if r is null or r.estado <> 'pendiente' then
    raise exception 'Ese reto ya no está pendiente' using errcode = 'P0001';
  end if;
  if yo is distinct from r.retado then
    raise exception 'No puedes hacer eso' using errcode = '42501';
  end if;
  if r.dia <> (now() at time zone 'America/Caracas')::date then
    raise exception 'Ese reto era de otro día' using errcode = 'P0001';
  end if;
  if coalesce(p_apuesta, 0) <> 0 and p_apuesta <> r.apuesta_min then
    raise exception 'La apuesta cambió: vuelve a abrir el reto' using errcode = 'P0001';
  end if;
  anular := r.apuesta_min > 0 and (coalesce(p_apuesta, 0) = 0 or not public.apuesta_imperio_activo());
  update public.retos
    set estado = 'aceptado',
        apuesta_anulada = anular,
        pago_retado = case when r.apuesta_min > 0 and not anular
                           then least(greatest(coalesce(p_fraccion, 0), 0), 1)::real end
    where id = rid;
  insert into public.mensajes (sala, user_id, tarjeta) values ('global', yo, jsonb_build_object('tipo', 'reto', 'id', rid));
  perform public.avisar_reto(rid, 'aceptado');
end;
$$;
revoke all on function public.aceptar_reto_apuesta(bigint, int, double precision) from public, anon;
grant execute on function public.aceptar_reto_apuesta(bigint, int, double precision) to authenticated;

-- Qué le toca a yo en ese reto: resultado ('gana', 'pierde', 'devuelve' o null si todavía no se sabe) y minutos.
-- gana: el doble de lo que pagó. devuelve: lo que pagó. Sin pago: 0 minutos.
create or replace function public.apuesta_de(r public.retos, yo uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  pago double precision;
  resultado text;
begin
  if r.apuesta_min = 0 or yo is null or (yo <> r.retador and yo <> r.retado) then return null; end if;
  pago := case when yo = r.retador then r.pago_retador else r.pago_retado end;
  resultado := case
    when r.apuesta_anulada or r.estado in ('rechazado', 'cancelado') then 'devuelve'
    when r.estado = 'terminado' and r.ganador is null then 'devuelve'
    when r.estado = 'terminado' and r.ganador = yo then 'gana'
    when r.estado = 'terminado' then 'pierde'
    else null end;
  return jsonb_build_object(
    'resultado', resultado,
    'pago', pago,
    'minutos', case resultado when 'gana' then 2 * r.apuesta_min * coalesce(pago, 0)
                              when 'devuelve' then r.apuesta_min * coalesce(pago, 0)
                              else 0 end,
    'cobrado', (case when yo = r.retador then r.cobrado_retador else r.cobrado_retado end) is not null);
end $$;
revoke all on function public.apuesta_de(public.retos, uuid) from public, anon, authenticated;

-- La apuesta de un reto. Cualquiera la ve si el reto está aceptado o terminado (como reto_publico); los dos del reto
-- ven además lo suyo: pago, resultado, minutos y si ya cobró.
create or replace function public.reto_apuesta(rid bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r public.retos;
  yo uuid := auth.uid();
begin
  select * into r from public.retos where id = rid;
  if not found then return null; end if;
  if yo is not null and (yo = r.retador or yo = r.retado) then
    return jsonb_build_object('apuesta', r.apuesta_min, 'anulada', r.apuesta_anulada)
      || coalesce(public.apuesta_de(r, yo), '{}'::jsonb);
  end if;
  if r.estado not in ('aceptado', 'terminado') then return null; end if;
  return jsonb_build_object('apuesta', r.apuesta_min, 'anulada', r.apuesta_anulada);
end $$;
revoke all on function public.reto_apuesta(bigint) from public, anon;
grant execute on function public.reto_apuesta(bigint) to authenticated;

-- Mis apuestas con algo por cobrar (premio o devolución), de cualquier día. Las perdidas no salen.
create or replace function public.reto_apuesta_pendientes()
returns table (id bigint, dia date, estado text, apuesta int, resultado text, minutos double precision, otro uuid)
language sql stable security definer set search_path = '' as $$
  select r.id, r.dia, r.estado, r.apuesta_min, a ->> 'resultado', (a ->> 'minutos')::double precision,
         case when r.retador = auth.uid() then r.retado else r.retador end
  from public.retos r
  cross join lateral (select public.apuesta_de(r, auth.uid()) as a) x
  where (r.retador = auth.uid() or r.retado = auth.uid())
    and r.apuesta_min > 0
    and r.estado in ('rechazado', 'cancelado', 'aceptado', 'terminado')
    and a ->> 'resultado' in ('gana', 'devuelve')
    and (a ->> 'minutos')::double precision > 0
    and not (a ->> 'cobrado')::boolean
  order by r.id desc
  limit 20
$$;
revoke all on function public.reto_apuesta_pendientes() from public, anon;
grant execute on function public.reto_apuesta_pendientes() to authenticated;

-- Cobrar (o recuperar) la apuesta. Una sola vez. Devuelve resultado, minutos y cuántas apuestas ganadas lleva
-- cobradas (para los logros). Cobrar un premio sin haber pagado da 0 y deja sospecha.
create or replace function public.reto_apuesta_cobrar(rid bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r public.retos;
  yo uuid := auth.uid();
  a jsonb;
  minutos double precision;
  ganadas int;
begin
  if yo is null then raise exception 'no autenticado'; end if;
  select * into r from public.retos where id = rid for update;
  if not found or (yo <> r.retador and yo <> r.retado) then
    raise exception 'No puedes hacer eso' using errcode = '42501';
  end if;
  a := public.apuesta_de(r, yo);
  if a is null or a ->> 'resultado' is null then
    raise exception 'Esa apuesta todavía no se puede cobrar' using errcode = 'P0001';
  end if;
  if (a ->> 'cobrado')::boolean then
    raise exception 'Ya cobraste esa apuesta' using errcode = 'P0001';
  end if;
  if a ->> 'resultado' = 'pierde' then
    raise exception 'Perdiste esa apuesta' using errcode = 'P0001';
  end if;
  minutos := (a ->> 'minutos')::double precision;
  if a ->> 'pago' is null then
    if a ->> 'resultado' = 'gana' then
      perform public.marcar_sospecha(yo, 'apuesta_sin_pagar',
        jsonb_build_object('reto', rid, 'apuesta', r.apuesta_min, 'rol', case when yo = r.retador then 'reta' else 'acepta' end));
    end if;
    minutos := 0;
  end if;
  if yo = r.retador then
    update public.retos set cobro_retador = minutos, cobrado_retador = now() where id = rid;
  else
    update public.retos set cobro_retado = minutos, cobrado_retado = now() where id = rid;
  end if;
  select count(*) into ganadas from public.retos x
    where x.ganador = yo and not x.apuesta_anulada
      and ((x.retador = yo and x.cobro_retador > 0) or (x.retado = yo and x.cobro_retado > 0));
  return jsonb_build_object('resultado', a ->> 'resultado', 'minutos', minutos, 'apuesta', r.apuesta_min, 'ganadas', ganadas);
end $$;
revoke all on function public.reto_apuesta_cobrar(bigint) from public, anon;
grant execute on function public.reto_apuesta_cobrar(bigint) to authenticated;

-- imperio_guardar igual que en 20261107130000_imperio_antitrampa.sql, más los premios de apuesta en el permitido.
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

notify pgrst, 'reload schema';
