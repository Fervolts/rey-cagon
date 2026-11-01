-- Imperio v2: Ciruelas (moneda premium), estéticas del baño, racha de 30 días y su push.
--
-- 1. imperio: ciruelas (nunca negativas), estéticas compradas, racha y tope diario de suerte.
-- 2. imperio_esteticas: precio y bono de cada estética (misma tabla que lib/imperio/esteticas.dart).
--    Agregar una estética = una fila aquí (en una migración nueva) y una en Dart.
-- 3. imperio_cargar(): igual que antes + ~5% de Ciruela por cagada real (sube con las estéticas).
-- 4. RPC de la app: imperio_ciruela_suerte, imperio_gastar_ciruelas, imperio_comprar_estetica,
--    imperio_reclamar_racha.
-- 5. Push de racha: APAGADO por defecto (push_config.racha_activo), opt-out en push_ajustes.racha,
--    pg_cron cada hora; a quien reclamó ayer y no hoy, a las 20:00 de su hora local.

-- ---------------------------------------------------------------- columnas
alter table public.imperio
  add column ciruelas bigint not null default 0 check (ciruelas >= 0),
  add column esteticas text[] not null default '{}',
  add column racha_dia int not null default 0,
  add column racha_fecha date,
  add column suerte_fecha date,
  add column suerte_hoy int not null default 0;

-- ---------------------------------------------------------------- estéticas
create table public.imperio_esteticas (
  id text primary key,
  precio int not null check (precio > 0),
  bono numeric not null check (bono >= 0)
);
-- Sin políticas: solo la leen las funciones de abajo.
alter table public.imperio_esteticas enable row level security;
insert into public.imperio_esteticas (id, precio, bono) values
  ('est_tobo', 50, 0.04),
  ('est_papel', 75, 0.04),
  ('est_lavamanos', 75, 0.05),
  ('est_espejo', 100, 0.05),
  ('est_repisa', 100, 0.05),
  ('est_cortina', 150, 0.05),
  ('est_ventana', 200, 0.06),
  ('est_alfombra', 250, 0.06),
  ('est_lampara', 300, 0.07),
  ('est_piso', 400, 0.08);

-- Suma de bonos de suerte de las estéticas compradas.
create function public.imperio_bono_suerte(p_esteticas text[]) returns numeric
language sql stable set search_path = public as $$
  select coalesce(sum(bono), 0) from public.imperio_esteticas where id = any(p_esteticas)
$$;
revoke all on function public.imperio_bono_suerte(text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------- carga
-- Mismo cuerpo que 20261031120000_imperio.sql + Ciruelas por cagada real y campos nuevos.
create or replace function public.imperio_cargar() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  total int;
  guardado_previo timestamptz;
  nuevas jsonb := '[]'::jsonb;
  cuenta int := 0;
  es_nuevo boolean := false;
  prob double precision;
  ganadas int := 0;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  select coalesce(cagadas, 0) into total from public.profiles where id = uid;
  total := coalesce(total, 0);

  select * into fila from public.imperio where user_id = uid for update;
  if not found then
    -- Herencia del Trono: 1 ficha por cada 5 cagadas, tope 5
    insert into public.imperio (user_id, fundador, fichas, cagadas_hasta)
    values (
      uid,
      exists (select 1 from public.cagadas where user_id = uid and created_at < public.imperio_lanzamiento()),
      least(5, total / 5),
      now()
    )
    on conflict (user_id) do nothing;
    select * into fila from public.imperio where user_id = uid for update;
    es_nuevo := true;
    guardado_previo := fila.guardado;
  else
    guardado_previo := fila.guardado;
    select coalesce(jsonb_agg(jsonb_build_object('tipo', t.tipo, 'peso', t.peso, 'creada', t.created_at) order by t.created_at), '[]'::jsonb),
           count(*)
      into nuevas, cuenta
      from (
        select tipo, peso, created_at from public.cagadas
        where user_id = uid and created_at > fila.cagadas_hasta
        order by created_at asc limit 20
      ) t;
    -- Cada cagada real nueva tira ~5% de Ciruela; las estéticas suben la probabilidad.
    if cuenta > 0 then
      prob := 0.05 * (1 + public.imperio_bono_suerte(fila.esteticas));
      select count(*) into ganadas from generate_series(1, cuenta) where random() < prob;
    end if;
    update public.imperio
      set fichas = least(5, fichas + cuenta), ciruelas = ciruelas + ganadas, cagadas_hasta = now()
      where user_id = uid
      returning * into fila;
  end if;

  return jsonb_build_object(
    'estado', fila.estado,
    'mj_total', fila.mj_total,
    'mps', fila.mps,
    'fichas', fila.fichas,
    'fundador', fila.fundador,
    'nuevo', es_nuevo,
    'nuevas', nuevas,
    'cagadas_total', total,
    'guardado', guardado_previo,
    'ahora', now(),
    'ciruelas', fila.ciruelas,
    'ciruelas_cagadas', ganadas,
    'esteticas', to_jsonb(fila.esteticas),
    'racha_dia', fila.racha_dia,
    'racha_fecha', fila.racha_fecha
  );
end $$;

-- ---------------------------------------------------------------- suerte al pujar
-- La app tira ~1/1500 por pujo y avisa aquí. Tope diario (UTC): 3 + estéticas/2.
-- Devuelve el saldo nuevo o -1 si ya no toca hoy.
create function public.imperio_ciruela_suerte() returns bigint
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  hoy date := (now() at time zone 'utc')::date;
  saldo bigint;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  update public.imperio
     set ciruelas = ciruelas + 1,
         suerte_hoy = case when suerte_fecha = hoy then suerte_hoy + 1 else 1 end,
         suerte_fecha = hoy
   where user_id = uid
     and (suerte_fecha is distinct from hoy or suerte_hoy < 3 + cardinality(esteticas) / 2)
   returning ciruelas into saldo;
  return coalesce(saldo, -1);
end $$;

-- ---------------------------------------------------------------- tienda de Ciruelas
-- Valida saldo y descuenta; el efecto lo aplica la app. Precios = lib/imperio/ciruelas.dart.
-- Devuelve el saldo nuevo o -1 si no alcanza.
create function public.imperio_gastar_ciruelas(p_que text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  precio int;
  saldo bigint;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  precio := case p_que
    when 'cagada_fresca' then 3
    when 'produccion_2h' then 5
    when 'robot_24h' then 10
  end;
  if precio is null then raise exception 'oferta desconocida'; end if;
  update public.imperio set ciruelas = ciruelas - precio
   where user_id = uid and ciruelas >= precio
   returning ciruelas into saldo;
  return coalesce(saldo, -1);
end $$;

-- Compra una estética. Devuelve el saldo nuevo, -1 si no alcanza, -2 si ya la tenía.
create function public.imperio_comprar_estetica(p_id text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_precio int;
  saldo bigint;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  select precio into v_precio from public.imperio_esteticas where id = p_id;
  if v_precio is null then raise exception 'estética desconocida'; end if;
  if exists (select 1 from public.imperio where user_id = uid and p_id = any(esteticas)) then
    return -2;
  end if;
  update public.imperio
     set ciruelas = ciruelas - v_precio, esteticas = array_append(esteticas, p_id)
   where user_id = uid and ciruelas >= v_precio and not (p_id = any(esteticas))
   returning ciruelas into saldo;
  return coalesce(saldo, -1);
end $$;

-- ---------------------------------------------------------------- racha de 30 días
-- p_fecha = fecha local del teléfono (±1 día de la fecha UTC del servidor).
-- Igual a racha_fecha (o anterior): ya reclamado. racha_fecha + 1: día siguiente (31 vuelve a 1).
-- Otra: día 1. Acredita lo del servidor (Ciruelas y Ficha con tope 5; Ficha llena = 2 Ciruelas).
-- Premios por día = premiosRacha en lib/imperio/racha_imperio.dart.
create function public.imperio_reclamar_racha(p_fecha date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  v_dia int;
  v_cir int;
  v_ficha boolean;
  dio_ficha boolean := false;
  -- índice = día (1..30)
  cir_por_dia int[] := array[0,0,1,0,0,2,3,0,0,3, 0,0,4,5,0,0,5,0,0,6, 8,0,0,8,0,0,10,12,0,25];
  ficha_dias int[] := array[7,14,21,28];
begin
  if uid is null then raise exception 'no autenticado'; end if;
  if p_fecha is null or abs(p_fecha - (now() at time zone 'utc')::date) > 1 then
    raise exception 'fecha fuera de rango';
  end if;
  select * into fila from public.imperio where user_id = uid for update;
  if not found then raise exception 'imperio no existe'; end if;

  if fila.racha_fecha is not null and p_fecha <= fila.racha_fecha then
    return jsonb_build_object('dia', fila.racha_dia, 'ya', true, 'ciruelas_ganadas', 0, 'ficha', false,
                              'ciruelas', fila.ciruelas, 'fichas', fila.fichas);
  end if;

  if fila.racha_fecha is not null and p_fecha = fila.racha_fecha + 1 then
    v_dia := fila.racha_dia % 30 + 1;
  else
    v_dia := 1;
  end if;
  v_cir := cir_por_dia[v_dia];
  v_ficha := v_dia = any(ficha_dias);
  if v_ficha then
    if fila.fichas < 5 then dio_ficha := true; else v_cir := v_cir + 2; end if;
  end if;

  update public.imperio
     set racha_dia = v_dia, racha_fecha = p_fecha,
         ciruelas = ciruelas + v_cir,
         fichas = case when dio_ficha then fichas + 1 else fichas end
   where user_id = uid
   returning * into fila;

  return jsonb_build_object('dia', v_dia, 'ya', false, 'ciruelas_ganadas', v_cir, 'ficha', dio_ficha,
                            'ciruelas', fila.ciruelas, 'fichas', fila.fichas);
end $$;

revoke all on function public.imperio_ciruela_suerte() from public, anon;
revoke all on function public.imperio_gastar_ciruelas(text) from public, anon;
revoke all on function public.imperio_comprar_estetica(text) from public, anon;
revoke all on function public.imperio_reclamar_racha(date) from public, anon;
grant execute on function public.imperio_ciruela_suerte() to authenticated;
grant execute on function public.imperio_gastar_ciruelas(text) to authenticated;
grant execute on function public.imperio_comprar_estetica(text) to authenticated;
grant execute on function public.imperio_reclamar_racha(date) to authenticated;

-- ---------------------------------------------------------------- push de racha
alter table public.push_config add column racha_activo boolean not null default false;
alter table public.push_ajustes
  add column racha boolean not null default true,
  add column racha_en timestamptz;

-- Opt-out de los avisos de racha.
create function public.push_racha(p_activo boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;
  insert into public.push_ajustes (user_id, racha) values (auth.uid(), p_activo)
    on conflict (user_id) do update set racha = excluded.racha;
end;
$$;
revoke all on function public.push_racha(boolean) from public, anon;
grant execute on function public.push_racha(boolean) to authenticated;

-- Candidatos: reclamó ayer (fecha local) y no hoy, son las 20:00 en su zona (~4 h antes de
-- medianoche) y no recibió este aviso hoy. Llama a 'notificaciones' con tipo 'racha'.
create function public.push_racha_revisar()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  lista jsonb;
  n integer;
begin
  if not coalesce((select racha_activo from public.push_config), false) then
    return 0;
  end if;

  with zonas as (
    select distinct on (t.user_id) t.user_id,
           case when exists (select 1 from pg_catalog.pg_timezone_names z where z.name = t.zona)
                then t.zona else 'America/Caracas' end as zona
      from public.push_tokens t
     where t.user_id is not null
     order by t.user_id, t.updated_at desc
  ),
  base as (
    select z.user_id, (now() at time zone z.zona)::date as hoy_local
      from zonas z
      left join public.push_ajustes a on a.user_id = z.user_id
     where coalesce(a.racha, true)
       and extract(hour from now() at time zone z.zona) = 20
       and (a.racha_en is null
            or a.racha_en < (date_trunc('day', now() at time zone z.zona) at time zone z.zona))
  ),
  elegidos as (
    select b.user_id, i.racha_dia as llevas, i.racha_dia % 30 + 1 as dia
      from base b
      join public.imperio i on i.user_id = b.user_id
     where i.racha_dia > 0 and i.racha_fecha = b.hoy_local - 1
  ),
  marcados as (
    insert into public.push_ajustes (user_id, racha_en)
    select user_id, now() from elegidos
    on conflict (user_id) do update set racha_en = excluded.racha_en
    returning user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('user_id', e.user_id, 'llevas', e.llevas, 'dia', e.dia)), '[]'::jsonb),
         count(*)
    into lista, n
    from elegidos e
    join marcados m on m.user_id = e.user_id;

  if n > 0 then
    perform net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
      ),
      body := jsonb_build_object('tipo', 'racha', 'lista', lista)
    );
  end if;
  return n;
end;
$$;
revoke all on function public.push_racha_revisar() from public, anon, authenticated;

-- Cada hora en punto. Con el interruptor apagado no hace nada.
select cron.schedule('push_racha', '0 * * * *', $$select public.push_racha_revisar()$$);
