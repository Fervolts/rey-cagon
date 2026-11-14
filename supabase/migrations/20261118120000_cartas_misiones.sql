-- Cartas, sobres y misiones diarias (docs/CARTAS.md).
-- 128 cartas en 4 rarezas; se sacan abriendo sobres. Un sobre diario por día local y otro por cumplir las 3 misiones
-- del día. Las misiones mezclan cagar, lo social (muro y chat) y el Imperio; el servidor cuenta todo el progreso.
-- Guardar sobres no pide el lado secreto; ver la colección, abrir y mejorar sí. La app no escribe nada directo:
-- todo pasa por misiones_hoy, misiones_cobrar, cartas_estado, cartas_abrir y cartas_mejorar.
begin;

-- Rareza de cada carta: 0 común (1..64), 1 rara (65..100), 2 épica (101..120), 3 legendaria (121..128).
create table public.cartas_rareza (
  n smallint primary key check (n between 1 and 128),
  rareza smallint not null check (rareza between 0 and 3)
);
insert into public.cartas_rareza (n, rareza)
select g, case when g <= 64 then 0 when g <= 100 then 1 when g <= 120 then 2 else 3 end
  from generate_series(1, 128) g;

-- Una fila por carta que el jugador tiene. Repetidas disponibles = copias - 1 - gastadas.
-- Subir a nivel k gasta k repetidas (1..5): el nivel 5 (arcoíris) pide 16 copias en total.
create table public.cartas_usuario (
  user_id uuid not null references public.profiles (id) on delete cascade,
  n smallint not null references public.cartas_rareza (n),
  copias int not null default 1 check (copias >= 1),
  nivel smallint not null default 0 check (nivel between 0 and 5),
  gastadas int not null default 0 check (gastadas >= 0 and gastadas <= copias - 1),
  creado timestamptz not null default now(),
  primary key (user_id, n)
);

-- Sobres. Uno por usuario, día local y origen: así el diario y el de las misiones no se pueden repetir.
-- Las cartas se sortean al abrir; el resultado queda guardado para que abrir dos veces devuelva lo mismo.
create table public.cartas_sobres (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  dia date not null,
  tipo text not null check (tipo in ('normal', 'plata', 'oro', 'rey')),
  origen text not null check (origen in ('diario', 'misiones')),
  creado timestamptz not null default now(),
  abierto timestamptz,
  resultado jsonb,
  unique (user_id, dia, origen)
);
create index cartas_sobres_sin_abrir on public.cartas_sobres (user_id, creado) where abierto is null;
create index cartas_sobres_abiertos on public.cartas_sobres (user_id, abierto desc) where abierto is not null;

-- Grupo de misiones. La misma clave puede tener varias metas (la app arma el texto con clave y meta).
-- categoria: cagar, social o imperio (las 3 del día salen de categorías distintas cuando se puede).
-- familia: dos misiones de la misma familia nunca salen el mismo día (son casi iguales).
-- peso: qué tan seguido sale. secreta: solo para quien tiene el lado secreto (placer y etiquetas se anotan ahí).
create table public.misiones_catalogo (
  clave text not null,
  meta int not null check (meta >= 1),
  categoria text not null check (categoria in ('cagar', 'social', 'imperio')),
  familia text not null,
  rara boolean not null default false,
  peso int not null check (peso >= 1),
  secreta boolean not null default false,
  primary key (clave, meta)
);
insert into public.misiones_catalogo (clave, meta, categoria, familia, rara, peso, secreta) values
  -- Cagar (1 cagada por hora como máximo; la hora la pone el servidor).
  ('cagar_temprano',    1, 'cagar', 'franja',   false, 3, false), -- una antes de las 9:00
  ('cagar_almuerzo',    1, 'cagar', 'franja',   false, 2, false), -- una entre 12:00 y 13:59
  ('cagar_tarde',       1, 'cagar', 'franja',   false, 2, false), -- una entre 15:00 y 17:59
  ('cagar_noche',       1, 'cagar', 'franja',   false, 3, false), -- una desde las 22:00
  ('cagar_madrugada',   1, 'cagar', 'franja',   true,  1, false), -- una antes de las 6:00
  ('cagar_veces',       2, 'cagar', 'veces',    false, 4, false),
  ('cagar_veces',       3, 'cagar', 'veces',    false, 2, false),
  ('cagar_veces',       4, 'cagar', 'veces',    true,  1, false),
  ('cagar_en_punto',    1, 'cagar', 'hora',     false, 2, false), -- minuto 00
  ('cagar_espejo',      1, 'cagar', 'hora',     false, 1, false), -- hora igual al minuto (14:14)
  ('cagar_capicua',     1, 'cagar', 'hora',     true,  1, false), -- HHMM que se lee igual al revés (12:21)
  ('cagar_separadas',   2, 'cagar', 'separadas', false, 2, false), -- dos con 6 horas o más entre la primera y la última
  ('cagar_tres_turnos', 3, 'cagar', 'separadas', true,  1, false), -- mañana (<12), tarde (12..18) y noche (19+)
  ('cagar_anotada',     2, 'cagar', 'parte',    false, 2, false), -- con tipo y peso anotados
  ('sacar_anaconda',    1, 'cagar', 'sacar',    false, 1, false), -- tipo 4
  ('sacar_volcan',      1, 'cagar', 'sacar',    false, 1, false), -- tipo 6
  ('sacar_ballena',     1, 'cagar', 'sacar',    false, 1, false), -- peso 5
  ('sacar_pluma',       1, 'cagar', 'sacar',    false, 1, false), -- peso 1
  ('sacar_variado',     3, 'cagar', 'sacar',    true,  1, false), -- 3 tipos distintos
  ('placer_maximo',     1, 'cagar', 'placer',   false, 1, true),  -- placer 7
  ('placer_etiquetas',  1, 'cagar', 'placer',   false, 1, true),  -- 2 etiquetas o más en una cagada
  -- Social. Solo cuenta lo hecho con otros (likes y comentarios en posts ajenos, reacciones a mensajes ajenos).
  ('muro_publicar',     1, 'social', 'muro',     false, 3, false), -- post propio (sin tarjetas automáticas)
  ('muro_dibujo',       1, 'social', 'muro',     false, 1, false), -- post con dibujo
  ('dar_caca',          3, 'social', 'caca',     false, 3, false), -- 💩 en posts ajenos del muro o en mensajes ajenos
  ('dar_caca',          8, 'social', 'caca',     false, 1, false),
  ('dar_caca',         15, 'social', 'caca',     true,  1, false),
  ('muro_comentar',     1, 'social', 'comentar', false, 3, false), -- en posts ajenos distintos
  ('muro_comentar',     3, 'social', 'comentar', false, 1, false),
  ('chat_escribir',     1, 'social', 'chat',     false, 3, false), -- sala general, de idioma, privado o Cloaca
  ('chat_escribir',     5, 'social', 'chat',     false, 2, false),
  ('chat_responder',    1, 'social', 'chat',     false, 2, false), -- respondiendo un mensaje
  ('chat_privado',      1, 'social', 'chat',     false, 1, false), -- en un privado
  ('reaccionar',        3, 'social', 'reaccion', false, 2, false), -- reaccionar a mensajes ajenos distintos
  ('seguir',            1, 'social', 'seguir',   false, 1, false),
  ('retar',             1, 'social', 'cagadon',  false, 1, false), -- mandar un reto de Cagadón
  -- Imperio (solo para quien ya lo abrió). Los contadores sin fecha se miden desde que salió la misión.
  ('pujar',           100, 'imperio', 'pujar',   false, 3, false),
  ('pujar',           300, 'imperio', 'pujar',   false, 2, false),
  ('pujar',          1000, 'imperio', 'pujar',   true,  1, false),
  ('jalar',             1, 'imperio', 'cadena',  false, 2, false), -- solo sale si le falta 1 cagada o menos
  ('comprar',           5, 'imperio', 'comprar', false, 3, false), -- cagadores comprados
  ('comprar',          25, 'imperio', 'comprar', false, 1, false),
  ('comprar',         100, 'imperio', 'comprar', true,  1, false),
  ('ganar_mj',         30, 'imperio', 'mj',      false, 2, false), -- meta en minutos de la producción que tenía
  ('ganar_mj',        120, 'imperio', 'mj',      true,  1, false),
  ('jugar_tuberia',     1, 'imperio', 'jugar',   false, 1, false),
  ('jugar_destapa',     1, 'imperio', 'jugar',   false, 1, false),
  ('jugar_fusion',      1, 'imperio', 'jugar',   false, 1, false),
  ('jugar_partidas',    5, 'imperio', 'jugar',   false, 1, false),
  ('jugar_los_tres',    3, 'imperio', 'jugar',   false, 1, false),
  ('puntos_tuberia', 1500, 'imperio', 'record',  false, 1, false), -- puntos en una partida
  ('puntos_tuberia', 3000, 'imperio', 'record',  true,  1, false),
  ('puntos_destapa',  300, 'imperio', 'record',  false, 1, false),
  ('puntos_destapa',  370, 'imperio', 'record',  true,  1, false),
  ('puntos_fusion',  4000, 'imperio', 'record',  false, 1, false),
  ('puntos_fusion',  6000, 'imperio', 'record',  true,  1, false);

-- Las 3 misiones de cada día local. base y ritmo: valor de un contador del Imperio al salir la misión
-- (pujos, jaladas, cagadores, MJ de la casa) y MJ por minuto de ese momento.
create table public.misiones (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  dia date not null,
  clave text not null,
  meta int not null check (meta >= 1),
  rara boolean not null default false,
  base double precision,
  ritmo double precision,
  creado timestamptz not null default now(),
  unique (user_id, dia, clave)
);
create index misiones_usuario_dia on public.misiones (user_id, dia);

alter table public.cartas_rareza enable row level security;
alter table public.cartas_usuario enable row level security;
alter table public.cartas_sobres enable row level security;
alter table public.misiones_catalogo enable row level security;
alter table public.misiones enable row level security;
revoke all on public.cartas_rareza, public.cartas_usuario, public.cartas_sobres, public.misiones_catalogo,
  public.misiones from anon, authenticated;
grant select on public.cartas_rareza, public.cartas_usuario, public.cartas_sobres, public.misiones to authenticated;
create policy cartas_rareza_leer on public.cartas_rareza for select to authenticated using (true);
create policy cartas_usuario_leer on public.cartas_usuario for select to authenticated
  using ((select auth.uid()) = user_id);
create policy cartas_sobres_leer on public.cartas_sobres for select to authenticated
  using ((select auth.uid()) = user_id);
create policy misiones_leer on public.misiones for select to authenticated
  using ((select auth.uid()) = user_id);

-- Valor actual de un contador del Imperio que no tiene fecha. null si no tiene Imperio o la clave no es de contador.
create function public.mision_contador(p_uid uuid, p_clave text) returns double precision
language sql stable security definer set search_path = '' as $$
  select case p_clave
           when 'pujar' then public.imperio_numero(i.estado ->> 'pujos')
           when 'jalar' then i.jaladas::double precision
           when 'comprar' then (
             select coalesce(sum(public.imperio_numero(e.v)), 0)
               from jsonb_each_text(case when jsonb_typeof(i.estado -> 'edificios') = 'object'
                                         then i.estado -> 'edificios' else '{}'::jsonb end) e (k, v))
           when 'ganar_mj' then public.imperio_mj_casa(i)
         end
    from public.imperio i
   where i.user_id = p_uid;
$$;

-- Progreso de una misión en el día local p_dia. Para los contadores del Imperio es actual - base; si el contador
-- se reinició (mudanza, abdicación) y quedó por debajo de la base, cuenta el valor actual. Nunca negativo.
create function public.mision_progreso(p_uid uuid, p_clave text, p_dia date, p_zona text,
                                       p_base double precision default null, p_ritmo double precision default null)
returns int
language plpgsql stable security definer set search_path = '' as $$
declare
  desde timestamptz := p_dia::timestamp at time zone p_zona;
  hasta timestamptz := (p_dia + 1)::timestamp at time zone p_zona;
  n double precision := 0;
  actual double precision;
begin
  if p_clave like 'cagar\_%' or p_clave like 'sacar\_%' or p_clave like 'placer\_%' then
    select case p_clave
             when 'cagar_temprano' then count(*) filter (where extract(hour from x.h) < 9)
             when 'cagar_almuerzo' then count(*) filter (where extract(hour from x.h) between 12 and 13)
             when 'cagar_tarde' then count(*) filter (where extract(hour from x.h) between 15 and 17)
             when 'cagar_noche' then count(*) filter (where extract(hour from x.h) >= 22)
             when 'cagar_madrugada' then count(*) filter (where extract(hour from x.h) < 6)
             when 'cagar_veces' then count(*)
             when 'cagar_en_punto' then count(*) filter (where extract(minute from x.h) = 0)
             when 'cagar_espejo' then count(*) filter (where extract(hour from x.h) = extract(minute from x.h))
             when 'cagar_capicua' then count(*) filter (where to_char(x.h, 'HH24MI') = reverse(to_char(x.h, 'HH24MI')))
             when 'cagar_separadas' then case when count(*) >= 2 and max(x.h) - min(x.h) >= interval '6 hours' then 2
                                              else least(count(*), 1) end
             when 'cagar_tres_turnos' then count(distinct case when extract(hour from x.h) < 12 then 1
                                                               when extract(hour from x.h) < 19 then 2 else 3 end)
             when 'cagar_anotada' then count(*) filter (where x.tipo is not null and x.peso is not null)
             when 'sacar_anaconda' then count(*) filter (where x.tipo = 4)
             when 'sacar_volcan' then count(*) filter (where x.tipo = 6)
             when 'sacar_ballena' then count(*) filter (where x.peso = 5)
             when 'sacar_pluma' then count(*) filter (where x.peso = 1)
             when 'sacar_variado' then count(distinct x.tipo)
             when 'placer_maximo' then count(*) filter (where x.placer = 7)
             when 'placer_etiquetas' then count(*) filter (where cardinality(x.etiquetas) >= 2)
             else 0
           end
      into n
      from (select c.created_at at time zone p_zona as h, c.tipo, c.peso, c.placer, c.etiquetas
              from public.cagadas c
             where c.user_id = p_uid and c.created_at >= desde and c.created_at < hasta) x;

  elsif p_clave in ('muro_publicar', 'muro_dibujo') then
    select count(*) into n from public.muro m
     where m.user_id = p_uid and m.created_at >= desde and m.created_at < hasta and m.tarjeta is null
       and (p_clave = 'muro_publicar' or m.dibujo is not null);

  elsif p_clave = 'dar_caca' then
    select (select count(*) from public.muro_likes l join public.muro m on m.id = l.post_id
             where l.user_id = p_uid and m.user_id <> p_uid and l.created_at >= desde and l.created_at < hasta)
         + (select count(*) from public.mensaje_reacciones r join public.mensajes x on x.id = r.mensaje_id
             where r.user_id = p_uid and r.emoji = '💩' and x.user_id <> p_uid
               and r.created_at >= desde and r.created_at < hasta)
      into n;

  elsif p_clave = 'muro_comentar' then
    select count(distinct c.post_id) into n from public.muro_comentarios c join public.muro m on m.id = c.post_id
     where c.user_id = p_uid and m.user_id <> p_uid and c.created_at >= desde and c.created_at < hasta;

  elsif p_clave in ('chat_escribir', 'chat_responder', 'chat_privado') then
    -- Mensajes escritos (las tarjetas automáticas no cuentan). Soporte tampoco: no es para jugar.
    select count(*) into n from public.mensajes x
     where x.user_id = p_uid and x.created_at >= desde and x.created_at < hasta
       and x.tarjeta is null and btrim(x.texto) <> ''
       and (x.sala in ('global', 'es', 'en') or x.sala like 'dm:%' or x.sala like 'cloaca:%')
       and (p_clave <> 'chat_responder' or x.responde_a is not null)
       and (p_clave <> 'chat_privado' or x.sala like 'dm:%');

  elsif p_clave = 'reaccionar' then
    select count(distinct r.mensaje_id) into n from public.mensaje_reacciones r join public.mensajes x on x.id = r.mensaje_id
     where r.user_id = p_uid and x.user_id <> p_uid and r.created_at >= desde and r.created_at < hasta;

  elsif p_clave = 'seguir' then
    select count(*) into n from public.follows f
     where f.follower = p_uid and f.created_at >= desde and f.created_at < hasta;

  elsif p_clave = 'retar' then
    select count(*) into n from public.retos r
     where r.retador = p_uid and r.created_at >= desde and r.created_at < hasta;

  elsif p_clave in ('pujar', 'jalar', 'comprar', 'ganar_mj') then
    actual := public.mision_contador(p_uid, p_clave);
    if actual is null or p_base is null then return 0; end if;
    n := case when actual >= p_base then actual - p_base else actual end;
    if p_clave = 'ganar_mj' then n := n / greatest(coalesce(p_ritmo, 1), 1); end if;

  elsif p_clave like 'jugar\_%' or p_clave like 'puntos\_%' then
    select case p_clave
             when 'jugar_tuberia' then count(*) filter (where j.juego = 'tuberia')
             when 'jugar_destapa' then count(*) filter (where j.juego = 'destapa')
             when 'jugar_fusion' then count(*) filter (where j.juego = 'memoria')
             when 'jugar_partidas' then count(*)
             when 'jugar_los_tres' then count(distinct j.juego)
             when 'puntos_tuberia' then coalesce(max(j.puntos) filter (where j.juego = 'tuberia'), 0)
             when 'puntos_destapa' then coalesce(max(j.puntos) filter (where j.juego = 'destapa'), 0)
             when 'puntos_fusion' then coalesce(max(j.puntos) filter (where j.juego = 'memoria'), 0)
             else 0
           end
      into n
      from public.imperio_minijuegos j
     where j.user_id = p_uid and j.creado >= desde and j.creado < hasta;
  end if;

  return least(greatest(floor(coalesce(n, 0)), 0), 2147483647)::int;
end;
$$;

-- Sortea las 3 misiones del día (si todavía no hay). Ponderado por peso; nunca dos de la misma familia ni más de
-- una rara. Primera pasada: una por categoría y sin claves de los 6 días anteriores. Segunda (si faltan): ya puede
-- repetir categoría. Tercera (si todavía faltan): también claves de los últimos 6 días.
create function public.misiones_sortear(p_uid uuid, p_dia date) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  secreto boolean;
  tiene_imperio boolean;
  cadena_lista boolean := false;
  r record;
  elegidas int := 0;
  raras int := 0;
  familias text[] := '{}';
  categorias text[] := '{}';
  pasada int;
  v_ritmo double precision;
begin
  select coalesce(p.placer_desbloqueado, false) into secreto from public.profiles p where p.id = p_uid;
  secreto := coalesce(secreto, false);
  tiene_imperio := exists (select 1 from public.imperio i where i.user_id = p_uid);
  if tiene_imperio then
    -- Jalar la cadena solo sale si ya puede jalar o le falta 1 cagada (pide varias cagadas reales entre jaladas).
    select (i.jaladas > 0 or (jsonb_typeof(i.estado -> 'mejoras') = 'array' and (i.estado -> 'mejoras') ? 'cadena_trono'))
           and public.imperio_cagadas_tope(p_uid, coalesce(i.jalada_en, i.creado)) >= public.imperio_cadena_necesarias() - 1
      into cadena_lista
      from public.imperio i where i.user_id = p_uid;
    cadena_lista := coalesce(cadena_lista, false);
  end if;

  for pasada in 1..3 loop
    exit when elegidas >= 3;
    for r in
      select k.* from public.misiones_catalogo k
       where (not k.secreta or secreto)
         and (k.categoria <> 'imperio' or tiene_imperio)
         and (k.clave <> 'jalar' or cadena_lista)
         and (pasada = 3 or not exists (
               select 1 from public.misiones m
                where m.user_id = p_uid and m.dia >= p_dia - 6 and m.dia < p_dia and m.clave = k.clave))
       order by -ln(1 - random()) / k.peso
    loop
      exit when elegidas >= 3;
      continue when r.familia = any (familias) or (r.rara and raras >= 1);
      continue when pasada = 1 and r.categoria = any (categorias);
      v_ritmo := null;
      if r.clave = 'ganar_mj' then
        select greatest(coalesce(i.mps, 0) * 60, 1) into v_ritmo from public.imperio i where i.user_id = p_uid;
      end if;
      insert into public.misiones (user_id, dia, clave, meta, rara, base, ritmo)
      values (p_uid, p_dia, r.clave, r.meta, r.rara, public.mision_contador(p_uid, r.clave), v_ritmo);
      elegidas := elegidas + 1;
      raras := raras + case when r.rara then 1 else 0 end;
      familias := familias || r.familia;
      categorias := categorias || r.categoria;
    end loop;
  end loop;
end;
$$;

-- Tipo de sobre. Diario (y premio de misiones sin rara): normal 80, plata 14, oro 5, rey 1.
-- Premio de misiones con alguna rara: plata 70, oro 25, rey 5.
create function public.cartas_tipo_sorteo(p_raro boolean) returns text
language sql volatile set search_path = '' as $$
  select case when p_raro then case when x.r < 0.70 then 'plata' when x.r < 0.95 then 'oro' else 'rey' end
              else case when x.r < 0.80 then 'normal' when x.r < 0.94 then 'plata' when x.r < 0.99 then 'oro' else 'rey' end
         end
    from (select random() as r) x;
$$;

-- Una rareza al azar con pesos [común, rara, épica, legendaria], solo entre las rarezas >= p_minima.
create function public.cartas_rareza_azar(p_pesos int[], p_minima int default 0) returns int
language plpgsql volatile set search_path = '' as $$
declare
  total int := 0;
  r double precision;
  i int;
begin
  for i in (p_minima + 1)..4 loop total := total + p_pesos[i]; end loop;
  r := random() * total;
  for i in (p_minima + 1)..4 loop
    r := r - p_pesos[i];
    if r < 0 then return i - 1; end if;
  end loop;
  return 3;
end;
$$;

-- Cartas de un sobre. Oro garantiza una épica o más y rey una legendaria: si el sorteo no la dio, la última carta
-- se vuelve a sortear solo entre esas rarezas (con los mismos pesos del sobre).
create function public.cartas_sortear(p_tipo text) returns smallint[]
language plpgsql volatile set search_path = '' as $$
declare
  cuantas int;
  pesos int[];
  minima int;
  rarezas int[] := '{}';
  i int;
begin
  case p_tipo
    when 'normal' then cuantas := 3; pesos := array[60, 28, 10, 2]; minima := 0;
    when 'plata' then cuantas := 4; pesos := array[40, 38, 18, 4]; minima := 0;
    when 'oro' then cuantas := 5; pesos := array[20, 40, 30, 10]; minima := 2;
    when 'rey' then cuantas := 5; pesos := array[10, 35, 35, 20]; minima := 3;
    else raise exception 'tipo_malo';
  end case;
  for i in 1..cuantas loop
    rarezas := rarezas || public.cartas_rareza_azar(pesos);
  end loop;
  if minima > 0 and (select max(z) from unnest(rarezas) z) < minima then
    rarezas[cuantas] := public.cartas_rareza_azar(pesos, minima);
  end if;
  return (select array_agg((select c.n from public.cartas_rareza c where c.rareza = z.r order by random() limit 1)
                           order by z.o)
            from unnest(rarezas) with ordinality z (r, o));
end;
$$;

create function public.cartas_exigir_secreto(p_uid uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_uid is null then raise exception 'no_autenticado'; end if;
  if not coalesce((select p.placer_desbloqueado from public.profiles p where p.id = p_uid), false) then
    raise exception 'sin_secreto';
  end if;
end;
$$;

-- Misiones del día local (las crea la primera vez). {dia, proximo, cobrada, misiones: [{id, clave, rara, meta, progreso}]}
create function public.misiones_hoy() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_zona text;
  v_hoy date;
begin
  if uid is null then raise exception 'no_autenticado'; end if;
  v_zona := public.imperio_zona(uid);
  v_hoy := (now() at time zone v_zona)::date;
  perform pg_advisory_xact_lock(hashtext('misiones:' || uid::text));
  if not exists (select 1 from public.misiones m where m.user_id = uid and m.dia = v_hoy) then
    perform public.misiones_sortear(uid, v_hoy);
  end if;
  return jsonb_build_object(
    'dia', v_hoy,
    'proximo', (v_hoy + 1)::timestamp at time zone v_zona,
    'cobrada', exists (select 1 from public.cartas_sobres s
                        where s.user_id = uid and s.dia = v_hoy and s.origen = 'misiones'),
    'misiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'clave', m.clave, 'rara', m.rara, 'meta', m.meta,
               'progreso', least(public.mision_progreso(uid, m.clave, m.dia, v_zona, m.base, m.ritmo), m.meta))
             order by m.id)
        from public.misiones m where m.user_id = uid and m.dia = v_hoy), '[]'::jsonb));
end;
$$;

-- Cobrar las 3 misiones del día: un sobre, una vez por día. {sobre: {id, tipo}}. Errores no_hechas, ya_cobrada.
create function public.misiones_cobrar() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_zona text;
  v_hoy date;
  total int;
  faltan int;
  hay_rara boolean;
  v_tipo text;
  v_id bigint;
begin
  if uid is null then raise exception 'no_autenticado'; end if;
  v_zona := public.imperio_zona(uid);
  v_hoy := (now() at time zone v_zona)::date;
  perform pg_advisory_xact_lock(hashtext('misiones:' || uid::text));
  if exists (select 1 from public.cartas_sobres s where s.user_id = uid and s.dia = v_hoy and s.origen = 'misiones') then
    raise exception 'ya_cobrada';
  end if;
  select count(*),
         count(*) filter (where public.mision_progreso(uid, m.clave, m.dia, v_zona, m.base, m.ritmo) < m.meta),
         coalesce(bool_or(m.rara), false)
    into total, faltan, hay_rara
    from public.misiones m where m.user_id = uid and m.dia = v_hoy;
  if total = 0 or faltan > 0 then raise exception 'no_hechas'; end if;
  v_tipo := public.cartas_tipo_sorteo(hay_rara);
  insert into public.cartas_sobres (user_id, dia, tipo, origen) values (uid, v_hoy, v_tipo, 'misiones')
  returning id into v_id;
  return jsonb_build_object('sobre', jsonb_build_object('id', v_id, 'tipo', v_tipo));
end;
$$;

-- Colección. Crea el sobre diario si falta. {dia, proximo, sobres (sin abrir), cartas, ultimas (6, la más nueva primero)}
create function public.cartas_estado() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_zona text;
  v_hoy date;
begin
  perform public.cartas_exigir_secreto(uid);
  v_zona := public.imperio_zona(uid);
  v_hoy := (now() at time zone v_zona)::date;
  insert into public.cartas_sobres (user_id, dia, tipo, origen)
  values (uid, v_hoy, public.cartas_tipo_sorteo(false), 'diario')
  on conflict (user_id, dia, origen) do nothing;
  return jsonb_build_object(
    'dia', v_hoy,
    'proximo', (v_hoy + 1)::timestamp at time zone v_zona,
    'sobres', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'tipo', s.tipo, 'origen', s.origen) order by s.creado, s.id)
        from public.cartas_sobres s where s.user_id = uid and s.abierto is null), '[]'::jsonb),
    'cartas', coalesce((
      select jsonb_agg(jsonb_build_object('n', u.n, 'copias', u.copias, 'nivel', u.nivel, 'gastadas', u.gastadas)
                       order by u.n)
        from public.cartas_usuario u where u.user_id = uid), '[]'::jsonb),
    'ultimas', coalesce((
      select jsonb_agg(x.n order by x.abierto desc, x.id desc, x.o desc)
        from (select (e.v ->> 'n')::int as n, s.abierto, s.id, e.o
                from public.cartas_sobres s
                cross join lateral jsonb_array_elements(s.resultado -> 'cartas') with ordinality e (v, o)
               where s.user_id = uid and s.abierto is not null
               order by s.abierto desc, s.id desc, e.o desc
               limit 6) x), '[]'::jsonb));
end;
$$;

-- Abrir un sobre propio. {tipo, cartas: [{n, nueva, copias, nivel}]}. Abrirlo otra vez devuelve lo mismo.
create function public.cartas_abrir(p_sobre bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  s public.cartas_sobres;
  c smallint;
  fila public.cartas_usuario;
  lista jsonb := '[]'::jsonb;
  res jsonb;
begin
  perform public.cartas_exigir_secreto(uid);
  select * into s from public.cartas_sobres x where x.id = p_sobre and x.user_id = uid for update;
  if not found then raise exception 'sin_sobre'; end if;
  if s.abierto is not null then return s.resultado; end if;
  foreach c in array public.cartas_sortear(s.tipo) loop
    insert into public.cartas_usuario as u (user_id, n) values (uid, c)
    on conflict (user_id, n) do update set copias = u.copias + 1
    returning * into fila;
    lista := lista || jsonb_build_object('n', c, 'nueva', fila.copias = 1, 'copias', fila.copias, 'nivel', fila.nivel);
  end loop;
  res := jsonb_build_object('tipo', s.tipo, 'cartas', lista);
  update public.cartas_sobres set abierto = now(), resultado = res where id = s.id;
  return res;
end;
$$;

-- Subir una carta de nivel: el nivel k gasta k repetidas. {n, nivel, copias, gastadas}. Errores sin_repetidas, nivel_max.
create function public.cartas_mejorar(p_n smallint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  fila public.cartas_usuario;
begin
  perform public.cartas_exigir_secreto(uid);
  select * into fila from public.cartas_usuario u where u.user_id = uid and u.n = p_n for update;
  if not found then raise exception 'sin_repetidas'; end if;
  if fila.nivel >= 5 then raise exception 'nivel_max'; end if;
  if fila.copias - 1 - fila.gastadas < fila.nivel + 1 then raise exception 'sin_repetidas'; end if;
  update public.cartas_usuario u set nivel = u.nivel + 1, gastadas = u.gastadas + u.nivel + 1
   where u.user_id = uid and u.n = p_n
  returning * into fila;
  return jsonb_build_object('n', fila.n, 'nivel', fila.nivel, 'copias', fila.copias, 'gastadas', fila.gastadas);
end;
$$;

revoke all on function public.mision_contador(uuid, text) from public, anon, authenticated;
revoke all on function public.mision_progreso(uuid, text, date, text, double precision, double precision) from public, anon, authenticated;
revoke all on function public.misiones_sortear(uuid, date) from public, anon, authenticated;
revoke all on function public.cartas_tipo_sorteo(boolean) from public, anon, authenticated;
revoke all on function public.cartas_rareza_azar(int[], int) from public, anon, authenticated;
revoke all on function public.cartas_sortear(text) from public, anon, authenticated;
revoke all on function public.cartas_exigir_secreto(uuid) from public, anon, authenticated;
revoke all on function public.misiones_hoy() from public, anon;
revoke all on function public.misiones_cobrar() from public, anon;
revoke all on function public.cartas_estado() from public, anon;
revoke all on function public.cartas_abrir(bigint) from public, anon;
revoke all on function public.cartas_mejorar(smallint) from public, anon;
grant execute on function public.misiones_hoy() to authenticated;
grant execute on function public.misiones_cobrar() to authenticated;
grant execute on function public.cartas_estado() to authenticated;
grant execute on function public.cartas_abrir(bigint) to authenticated;
grant execute on function public.cartas_mejorar(smallint) to authenticated;

commit;
