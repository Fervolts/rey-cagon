-- Imperio fase 2 (carril B): más usos de Fichas, Congelador de racha y Cofre del Trono.
-- 1. Columnas: congeladores (0..2), tanque_extra, racha_salvados, cofre_semana, semanas_racha.
-- 2. imperio_usar_fichas(p_que): sin_espera 1, tanque_extra 2 (una vez), congelador 3 (+1 congelador).
--    imperio_usar_ficha() (Cagada fresca) queda igual.
-- 3. imperio_reclamar_racha: si faltaron k días y k <= congeladores, gasta k y la racha sigue.
-- 4. imperio_gastar_ciruelas: + congelador (5) y los objetos nuevos pagables con Ciruelas.
-- 5. imperio_cofre(p_reclamar): 3 días con cagada real en la semana (lunes a domingo, hora local) = +2 Fichas.
-- 6. imperio_cargar y push_racha_revisar devuelven/mandan los congeladores.

-- ---------------------------------------------------------------- columnas
alter table public.imperio
  add column congeladores int not null default 0 check (congeladores between 0 and 2),
  add column tanque_extra boolean not null default false,
  add column racha_salvados int[] not null default '{}',
  add column cofre_semana date,
  add column semanas_racha int not null default 0 check (semanas_racha >= 0);

-- ---------------------------------------------------------------- zona del usuario
-- Zona del token de push más reciente; si no hay o no es válida, America/Caracas.
create function public.imperio_zona(p_uid uuid) returns text
language sql stable set search_path = '' as $$
  select coalesce(
    (select case when exists (select 1 from pg_catalog.pg_timezone_names z where z.name = t.zona) then t.zona end
       from public.push_tokens t
      where t.user_id = p_uid
      order by t.updated_at desc
      limit 1),
    'America/Caracas')
$$;
revoke all on function public.imperio_zona(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- usos de Fichas
-- Devuelve las Fichas que quedan, -1 si no alcanzan, -2 si ya no se puede (2 congeladores o tanque ya usado).
-- El efecto (borrar una espera, +1 h al tope offline) lo aplica la app.
create function public.imperio_usar_fichas(p_que text) returns int
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  costo int;
  fila public.imperio;
  quedan int;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  costo := case p_que
    when 'sin_espera' then 1
    when 'tanque_extra' then 2
    when 'congelador' then 3
  end;
  if costo is null then raise exception 'uso desconocido'; end if;
  select * into fila from public.imperio where user_id = uid for update;
  if not found then return -1; end if;
  if p_que = 'congelador' and fila.congeladores >= 2 then return -2; end if;
  if p_que = 'tanque_extra' and fila.tanque_extra then return -2; end if;
  if fila.fichas < costo then return -1; end if;
  update public.imperio
     set fichas = fichas - costo,
         congeladores = congeladores + case when p_que = 'congelador' then 1 else 0 end,
         tanque_extra = tanque_extra or p_que = 'tanque_extra'
   where user_id = uid
   returning fichas into quedan;
  return quedan;
end $$;
revoke all on function public.imperio_usar_fichas(text) from public, anon;
grant execute on function public.imperio_usar_fichas(text) to authenticated;

-- ---------------------------------------------------------------- tienda de Ciruelas
-- Igual que 20261101140000 + congelador (5; -2 si ya tiene 2) y los objetos nuevos de la fase 2.
-- Precios = lib/imperio/ciruelas.dart y `Objeto.ciruelas` en lib/imperio/catalogo.dart.
create or replace function public.imperio_gastar_ciruelas(p_que text) returns bigint
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
    when 'congelador' then 5
    when 'obj_ambientador' then 2
    when 'obj_laxante' then 1
    when 'obj_papel' then 2
    when 'obj_robot' then 3
    when 'obj_robot_turbo' then 6
    when 'obj_primo' then 3
    when 'obj_guardia' then 4
    when 'obj_pino' then 3
    when 'obj_greca' then 3
    when 'obj_reina_pepiada' then 2
    when 'obj_destapacanos' then 1
  end;
  if precio is null then raise exception 'oferta desconocida'; end if;
  if p_que = 'congelador' then
    if exists (select 1 from public.imperio where user_id = uid and congeladores >= 2) then return -2; end if;
    update public.imperio set ciruelas = ciruelas - precio, congeladores = congeladores + 1
     where user_id = uid and ciruelas >= precio and congeladores < 2
     returning ciruelas into saldo;
    return coalesce(saldo, -1);
  end if;
  update public.imperio set ciruelas = ciruelas - precio
   where user_id = uid and ciruelas >= precio
   returning ciruelas into saldo;
  return coalesce(saldo, -1);
end $$;

-- ---------------------------------------------------------------- racha con congelador
-- Igual que 20261101120000 + congelador: si faltaron k días (1 <= k <= congeladores), gasta k
-- y la racha sigue en día+1. El día salvado queda en racha_salvados (se vacía al volver al día 1).
create or replace function public.imperio_reclamar_racha(p_fecha date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  v_dia int;
  v_cir int;
  v_ficha boolean;
  v_falta int;
  v_cong int := 0;
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
                              'ciruelas', fila.ciruelas, 'fichas', fila.fichas, 'congelados', 0,
                              'congeladores', fila.congeladores, 'racha_salvados', to_jsonb(fila.racha_salvados));
  end if;

  v_falta := case when fila.racha_fecha is null then null else p_fecha - fila.racha_fecha - 1 end;
  if v_falta = 0 then
    v_dia := fila.racha_dia % 30 + 1;
  elsif fila.racha_dia > 0 and v_falta between 1 and fila.congeladores then
    v_cong := v_falta;
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
         fichas = case when dio_ficha then fichas + 1 else fichas end,
         congeladores = congeladores - v_cong,
         racha_salvados = (case when v_dia = 1 then '{}'::int[] else racha_salvados end)
                          || (case when v_cong > 0 then array[v_dia] else '{}'::int[] end)
   where user_id = uid
   returning * into fila;

  return jsonb_build_object('dia', v_dia, 'ya', false, 'ciruelas_ganadas', v_cir, 'ficha', dio_ficha,
                            'ciruelas', fila.ciruelas, 'fichas', fila.fichas, 'congelados', v_cong,
                            'congeladores', fila.congeladores, 'racha_salvados', to_jsonb(fila.racha_salvados));
end $$;

-- ---------------------------------------------------------------- Cofre del Trono
-- Semana = lunes a domingo en la zona del usuario. dias = días distintos con cagada real.
-- Con p_reclamar y dias >= 3 (una vez por semana): +2 Fichas (tope 5; la que no cabe = 2 Ciruelas).
-- semanas_racha: +1 si la semana anterior también se reclamó, si no 1. La app suma 1 h de producción.
create function public.imperio_cofre(p_reclamar boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_zona text;
  hoy date;
  lunes date;
  v_dias int;
  fila public.imperio;
  v_reclamado boolean;
  v_sem int;
  cabe int := 0;
  v_cir int := 0;
  ahora_si boolean := false;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  v_zona := public.imperio_zona(uid);
  hoy := (now() at time zone v_zona)::date;
  lunes := hoy - (extract(isodow from hoy)::int - 1);
  select count(distinct (c.created_at at time zone v_zona)::date) into v_dias
    from public.cagadas c
   where c.user_id = uid
     and c.created_at >= (lunes::timestamp at time zone v_zona)
     and c.created_at < ((lunes + 7)::timestamp at time zone v_zona);

  select * into fila from public.imperio where user_id = uid for update;
  if not found then raise exception 'imperio no existe'; end if;
  v_reclamado := fila.cofre_semana is not null and fila.cofre_semana >= lunes;
  -- La racha de semanas sigue viva si se reclamó esta semana o la anterior.
  v_sem := case when fila.cofre_semana is not null and fila.cofre_semana >= lunes - 7 then fila.semanas_racha else 0 end;

  if p_reclamar and not v_reclamado and v_dias >= 3 then
    cabe := greatest(0, least(2, 5 - fila.fichas));
    v_cir := (2 - cabe) * 2;
    v_sem := case when fila.cofre_semana = lunes - 7 then fila.semanas_racha + 1 else 1 end;
    update public.imperio
       set fichas = fichas + cabe, ciruelas = ciruelas + v_cir, cofre_semana = lunes, semanas_racha = v_sem
     where user_id = uid
     returning * into fila;
    v_reclamado := true;
    ahora_si := true;
  end if;

  return jsonb_build_object(
    'dias', v_dias,
    'meta', 3,
    'listo', v_dias >= 3 and not v_reclamado,
    'reclamado', v_reclamado,
    'reclamado_ahora', ahora_si,
    'semanas_racha', v_sem,
    'lunes', lunes,
    'fichas', fila.fichas,
    'fichas_ganadas', cabe,
    'ciruelas', fila.ciruelas,
    'ciruelas_ganadas', v_cir
  );
end $$;
revoke all on function public.imperio_cofre(boolean) from public, anon;
grant execute on function public.imperio_cofre(boolean) to authenticated;

-- ---------------------------------------------------------------- carga
-- Mismo cuerpo que 20261101120000 + congeladores, tanque_extra y racha_salvados.
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
    'racha_fecha', fila.racha_fecha,
    'congeladores', fila.congeladores,
    'tanque_extra', fila.tanque_extra,
    'racha_salvados', to_jsonb(fila.racha_salvados)
  );
end $$;

-- ---------------------------------------------------------------- push de racha
-- Igual que 20261101120000 + congeladores en la lista (la Edge Function cambia el texto). Mismo horario.
create or replace function public.push_racha_revisar()
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
    select b.user_id, i.racha_dia as llevas, i.racha_dia % 30 + 1 as dia, i.congeladores
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
  select coalesce(jsonb_agg(jsonb_build_object('user_id', e.user_id, 'llevas', e.llevas, 'dia', e.dia,
                                               'congeladores', e.congeladores)), '[]'::jsonb),
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
