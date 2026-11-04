begin;

-- Imperio fase 5: Sala de juegos. Tres minijuegos que se abren: Tubería Express (tuberia), Destapa (destapa)
-- y Memoria del rollo (memoria). El servidor decide el premio y la app lo suma como suma un regalo.
--   * imperio_minijuego(juego, puntos, duracion_ms): guarda la partida y devuelve los minutos de producción
--     propia que gana quien juega (la app los suma con Imperio.abrirRegalo, igual que un regalo).
--   * Topes duros: minijuego_minutos_max 1..30 por partida y minijuego_minutos_dia 1..120 por día de Caracas.
--     Así el margen de imperio_guardar (20261107130000_imperio_antitrampa.sql: +216000 s de ritmo por guardado,
--     o sea 3600 min) los cubre sin tocarlo.
--   * Anti-trampa: duración mínima y puntos por segundo máximos por juego (flags). Una partida imposible
--     no guarda nada y no da premio.
--   * Récord personal y ranking semanal (semana de Caracas, lunes a domingo): mejor puntaje de cada quien.
-- Las apps viejas no llaman nada de esto.

-- ---------------------------------------------------------------- flags
insert into public.imperio_flags (clave, valor, nota) values
  ('minijuegos_activo', 'true', 'Sala de juegos: los minijuegos dan premio'),
  ('minijuego_minutos_max', '10', 'Minutos máximos de producción propia que da una partida (1..30)'),
  ('minijuego_minutos_dia', '30', 'Minutos máximos de producción propia que dan los minijuegos por día de Caracas (1..120)'),
  ('minijuego_partidas_dia', '20', 'Partidas por día de Caracas que pueden dar premio (1..60)'),
  ('minijuego_meta_tuberia', '600', 'Puntos de Tubería Express que dan el premio completo'),
  ('minijuego_meta_destapa', '45', 'Puntos de Destapa que dan el premio completo'),
  ('minijuego_meta_memoria', '900', 'Puntos de Memoria del rollo que dan el premio completo'),
  ('minijuego_pps_tuberia', '16', 'Puntos por segundo máximos creíbles en Tubería Express'),
  ('minijuego_pps_destapa', '8', 'Puntos por segundo máximos creíbles en Destapa'),
  ('minijuego_pps_memoria', '300', 'Puntos por segundo máximos creíbles en Memoria del rollo'),
  ('minijuego_min_ms_tuberia', '2000', 'Duración mínima creíble de una partida de Tubería Express (ms)'),
  ('minijuego_min_ms_destapa', '4000', 'Duración mínima creíble de una partida de Destapa (ms)'),
  ('minijuego_min_ms_memoria', '5000', 'Duración mínima creíble de una partida de Memoria del rollo (ms)')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------- tabla
create table public.imperio_minijuegos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  juego text not null check (juego in ('tuberia', 'destapa', 'memoria')),
  puntos int not null check (puntos between 0 and 1000000),
  duracion_ms int not null check (duracion_ms between 0 and 3600000),
  minutos int not null default 0 check (minutos between 0 and 30),
  dia date not null default (now() at time zone 'America/Caracas')::date,
  creado timestamptz not null default now()
);
create index imperio_minijuegos_user_dia_idx on public.imperio_minijuegos (user_id, dia);
create index imperio_minijuegos_user_juego_idx on public.imperio_minijuegos (user_id, juego, puntos desc);
create index imperio_minijuegos_semana_idx on public.imperio_minijuegos (juego, creado, puntos desc);
alter table public.imperio_minijuegos enable row level security;
-- Solo lees lo tuyo. Nadie escribe directo: solo el RPC.
create policy imperio_minijuegos_ver on public.imperio_minijuegos for select to authenticated
  using ((select auth.uid()) = user_id);
revoke insert, update, delete, truncate on public.imperio_minijuegos from anon, authenticated;

-- ---------------------------------------------------------------- RPC de la app
-- Guarda una partida. {ok, motivo?, minutos, puntos, record, nuevo_record, ganados_hoy, tope_dia, partidas_hoy, tope_partidas}.
-- motivo: apagado, juego, invalida (imposible), tope_partidas (se guarda sin premio).
create function public.imperio_minijuego(p_juego text, p_puntos int, p_duracion_ms int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  yo uuid := auth.uid();
  hoy date := (now() at time zone 'America/Caracas')::date;
  m_max int := public.imperio_regalos_flag('minijuego_minutos_max', 10, 1, 30)::int;
  m_dia int := public.imperio_regalos_flag('minijuego_minutos_dia', 30, 1, 120)::int;
  p_dia int := public.imperio_regalos_flag('minijuego_partidas_dia', 20, 1, 60)::int;
  meta numeric;
  pps numeric;
  min_ms numeric;
  ganados int;
  total_hoy int;
  record_ant int;
  m int := 0;
  motivo text := null;
begin
  if yo is null then raise exception 'sin sesión' using errcode = '28000'; end if;
  if not public.imperio_regalos_si('minijuegos_activo') then
    return jsonb_build_object('ok', false, 'motivo', 'apagado');
  end if;
  if p_juego is null or p_juego not in ('tuberia', 'destapa', 'memoria') then
    return jsonb_build_object('ok', false, 'motivo', 'juego');
  end if;
  if p_puntos is null or p_duracion_ms is null or p_puntos < 0 or p_duracion_ms < 0 then
    return jsonb_build_object('ok', false, 'motivo', 'invalida');
  end if;
  meta := public.imperio_regalos_flag('minijuego_meta_' || p_juego, 600, 1, 100000);
  pps := public.imperio_regalos_flag('minijuego_pps_' || p_juego, 16, 1, 100000);
  min_ms := public.imperio_regalos_flag('minijuego_min_ms_' || p_juego, 3000, 0, 600000);
  -- Imposible: muy corta, o con más puntos por segundo de los que el juego deja. Un segundo de margen.
  if p_duracion_ms < min_ms or p_duracion_ms > 3600000 or p_puntos > 1000000
     or p_puntos > (p_duracion_ms / 1000.0 + 1) * pps then
    return jsonb_build_object('ok', false, 'motivo', 'invalida');
  end if;

  perform pg_advisory_xact_lock(hashtext('imperio_minijuego:' || yo::text));
  select coalesce(sum(x.minutos), 0), count(*)
    into ganados, total_hoy from public.imperio_minijuegos x where x.user_id = yo and x.dia = hoy;
  -- Tope de filas por día: pasado esto no se guarda nada (evita llenar la tabla).
  if total_hoy >= p_dia * 3 then
    return jsonb_build_object('ok', false, 'motivo', 'tope_partidas', 'minutos', 0, 'puntos', p_puntos,
      'ganados_hoy', ganados, 'tope_dia', m_dia, 'partidas_hoy', total_hoy, 'tope_partidas', p_dia);
  end if;
  select coalesce(max(x.puntos), 0) into record_ant from public.imperio_minijuegos x where x.user_id = yo and x.juego = p_juego;

  if total_hoy >= p_dia then
    motivo := 'tope_partidas';
  elsif p_puntos > 0 then
    m := least(m_max, greatest(1, ceil(m_max * least(p_puntos / meta, 1))::int));
    m := least(m, greatest(m_dia - ganados, 0));
  end if;

  insert into public.imperio_minijuegos (user_id, juego, puntos, duracion_ms, minutos, dia)
    values (yo, p_juego, p_puntos, p_duracion_ms, m, hoy);

  return jsonb_build_object('ok', true, 'motivo', motivo, 'minutos', m, 'puntos', p_puntos,
    'record', greatest(record_ant, p_puntos), 'nuevo_record', p_puntos > record_ant,
    'ganados_hoy', ganados + m, 'tope_dia', m_dia, 'partidas_hoy', total_hoy + 1, 'tope_partidas', p_dia);
end;
$$;

-- Resumen para la Sala: flags, lo ganado hoy y por juego el récord, las partidas y el mejor de la semana.
create function public.imperio_minijuegos_resumen()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  yo uuid := auth.uid();
  hoy date := (now() at time zone 'America/Caracas')::date;
  semana timestamptz := (date_trunc('week', now() at time zone 'America/Caracas')) at time zone 'America/Caracas';
begin
  if yo is null then raise exception 'sin sesión' using errcode = '28000'; end if;
  return jsonb_build_object(
    'activo', public.imperio_regalos_si('minijuegos_activo'),
    'minutos_max', public.imperio_regalos_flag('minijuego_minutos_max', 10, 1, 30)::int,
    'tope_dia', public.imperio_regalos_flag('minijuego_minutos_dia', 30, 1, 120)::int,
    'tope_partidas', public.imperio_regalos_flag('minijuego_partidas_dia', 20, 1, 60)::int,
    'ganados_hoy', coalesce((select sum(x.minutos) from public.imperio_minijuegos x where x.user_id = yo and x.dia = hoy), 0),
    'partidas_hoy', (select count(*) from public.imperio_minijuegos x where x.user_id = yo and x.dia = hoy),
    'juegos', coalesce((
      select jsonb_object_agg(j.juego, jsonb_build_object('record', j.rec, 'partidas', j.n, 'semana', j.sem))
      from (select x.juego, max(x.puntos) as rec, count(*) as n,
                   coalesce(max(x.puntos) filter (where x.creado >= semana), 0) as sem
            from public.imperio_minijuegos x where x.user_id = yo group by x.juego) j), '{}'::jsonb));
end;
$$;

-- Ranking semanal de un juego: el mejor puntaje de cada quien esta semana de Caracas.
-- p_alcance: 'amigos' (los que sigues y tú) o 'global'. Hasta 50 filas, y tú siempre sales si jugaste.
create function public.imperio_minijuego_ranking(p_juego text, p_alcance text default 'amigos')
returns table(user_id uuid, username text, avatar text, puntos int, yo boolean, puesto bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with semana as (
    select (date_trunc('week', now() at time zone 'America/Caracas')) at time zone 'America/Caracas' as desde
  ),
  mejor as (
    select x.user_id as uid, max(x.puntos) as pts
    from public.imperio_minijuegos x, semana s
    where (select auth.uid()) is not null
      and p_juego in ('tuberia', 'destapa', 'memoria')
      and p_alcance in ('amigos', 'global')
      and x.juego = p_juego and x.creado >= s.desde and x.puntos > 0
      and (p_alcance = 'global'
           or x.user_id = (select auth.uid())
           or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = x.user_id))
      and (x.user_id = (select auth.uid()) or not public.hay_bloqueo(x.user_id))
    group by x.user_id
  ),
  orden as (
    select m.uid, p.username as nombre, p.avatar as av, m.pts, m.uid = (select auth.uid()) as es_yo,
           row_number() over (order by m.pts desc, p.username) as n
    from mejor m join public.profiles p on p.id = m.uid
  )
  select o.uid, o.nombre, o.av, o.pts, o.es_yo, o.n from orden o where o.n <= 50 or o.es_yo order by o.n;
$$;

revoke all on function public.imperio_minijuego(text, int, int) from public, anon;
revoke all on function public.imperio_minijuegos_resumen() from public, anon;
revoke all on function public.imperio_minijuego_ranking(text, text) from public, anon;
grant execute on function public.imperio_minijuego(text, int, int) to authenticated;
grant execute on function public.imperio_minijuegos_resumen() to authenticated;
grant execute on function public.imperio_minijuego_ranking(text, text) to authenticated;

commit;
