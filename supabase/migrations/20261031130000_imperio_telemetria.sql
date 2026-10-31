-- Imperio: eventos de juego (para ver cómo se juega) y flags remotos con variantes A/B (para afinar sin sacar versión).
-- Los usuarios no leen ni escriben estas tablas directo: todo pasa por RPC.

-- ---------- Eventos ----------

create table public.imperio_eventos (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  evento text not null check (char_length(evento) between 1 and 40),
  datos jsonb not null default '{}' check (pg_column_size(datos) <= 4096),
  sesion uuid,
  version_app text check (char_length(version_app) <= 40),
  creado timestamptz not null default now(),
  -- Reloj del teléfono cuando pasó (ms epoch); creado es cuando llegó.
  cliente_ms bigint
);
create index on public.imperio_eventos (evento, creado);
create index on public.imperio_eventos (user_id, creado);
alter table public.imperio_eventos enable row level security;
-- Sin políticas: se escribe con imperio_registrar y se lee desde el editor SQL.

-- Guarda un lote: [{evento, datos, sesion, version, ms}]. Hasta 100 por llamada y 2000 por usuario al día (UTC);
-- lo que sobra o viene mal formado se descarta sin error. Devuelve cuántos guardó.
create function public.imperio_registrar(p_eventos jsonb) returns int
language plpgsql security definer set search_path = public as $$
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

  insert into public.imperio_eventos (user_id, evento, datos, sesion, version_app, cliente_ms)
  select uid,
         e->>'evento',
         case when jsonb_typeof(e->'datos') = 'object' then e->'datos' else '{}'::jsonb end,
         case when jsonb_typeof(e->'sesion') = 'string'
               and e->>'sesion' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then (e->>'sesion')::uuid end,
         case when jsonb_typeof(e->'version') = 'string' then left(e->>'version', 40) end,
         case when jsonb_typeof(e->'ms') = 'number' and (e->>'ms')::numeric between 0 and 1e14
              then floor((e->>'ms')::numeric)::bigint end
    from jsonb_array_elements(p_eventos) with ordinality as t(e, orden)
   where t.orden <= 100
     and jsonb_typeof(e) = 'object'
     and jsonb_typeof(e->'evento') = 'string'
     and e->>'evento' ~ '^[a-z0-9_]{1,40}$'
     and (e->'datos' is null or jsonb_typeof(e->'datos') in ('object', 'null'))
     and (e->'datos' is null or pg_column_size(e->'datos') <= 4096)
   order by t.orden
   limit cupo;
  get diagnostics guardados = row_count;
  return guardados;
end $$;

-- Solo admin (o el editor SQL): borra eventos más viejos que `dias`. Devuelve cuántos borró.
create function public.imperio_limpiar_eventos(dias int default 180) returns int
language plpgsql security definer set search_path = public as $$
declare
  borrados int;
begin
  if not (public.es_admin() or coalesce(auth.role(), '') = 'service_role' or session_user = 'postgres') then
    raise exception 'solo admin';
  end if;
  delete from public.imperio_eventos where creado < now() - make_interval(days => greatest(coalesce(dias, 180), 1));
  get diagnostics borrados = row_count;
  return borrados;
end $$;

-- ---------- Flags y variantes ----------

-- valor = el de todos. variantes = [{nombre, peso, valor}] con pesos sobre 100; quien cae fuera de los pesos queda en
-- 'base' con el valor de todos. activo = false: el cliente usa su default de código.
create table public.imperio_flags (
  clave text primary key check (clave ~ '^[a-z0-9_]{1,40}$'),
  valor jsonb not null,
  variantes jsonb check (variantes is null or jsonb_typeof(variantes) = 'array'),
  activo boolean not null default true,
  nota text
);
alter table public.imperio_flags enable row level security;

-- Testers con variante forzada (manda sobre todo lo demás y no se anota en asignaciones).
create table public.imperio_flags_usuario (
  user_id uuid not null references public.profiles(id) on delete cascade,
  clave text not null references public.imperio_flags(clave) on delete cascade,
  variante text not null,
  primary key (user_id, clave)
);
alter table public.imperio_flags_usuario enable row level security;

-- La primera variante que recibió cada usuario. No se reasigna aunque cambien los pesos. Sin FK a la flag: si se borra,
-- la historia queda para el análisis.
create table public.imperio_asignaciones (
  user_id uuid not null references public.profiles(id) on delete cascade,
  clave text not null,
  variante text not null,
  desde timestamptz not null default now(),
  primary key (user_id, clave)
);
create index on public.imperio_asignaciones (clave, variante);
alter table public.imperio_asignaciones enable row level security;

-- Flags activas para el usuario: {clave: {valor, variante}}. variante es null si la flag no tiene variantes.
-- Variante: forzada > ya asignada > cubeta fija abs(hashtext(user_id || clave)) % 100 sobre los pesos acumulados.
create function public.imperio_flags_mias() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  f public.imperio_flags;
  v jsonb;
  elegida text;
  valor jsonb;
  cubeta int;
  acumulado numeric;
  salida jsonb := '{}'::jsonb;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  for f in select * from public.imperio_flags where activo order by clave loop
    elegida := null;
    valor := f.valor;
    if f.variantes is not null and jsonb_array_length(f.variantes) > 0 then
      select u.variante into elegida from public.imperio_flags_usuario u where u.user_id = uid and u.clave = f.clave;
      if elegida is null then
        select a.variante into elegida from public.imperio_asignaciones a where a.user_id = uid and a.clave = f.clave;
      end if;
      if elegida is null then
        -- ::bigint antes de abs: hashtext puede dar -2147483648 y abs(int) se desborda.
        cubeta := (abs(hashtext(uid::text || f.clave)::bigint) % 100)::int;
        acumulado := 0;
        for v in select x from jsonb_array_elements(f.variantes) as t(x) loop
          if jsonb_typeof(v) = 'object' and jsonb_typeof(v->'nombre') = 'string' then
            acumulado := acumulado + case when jsonb_typeof(v->'peso') = 'number' then greatest((v->>'peso')::numeric, 0) else 0 end;
            if cubeta < acumulado then elegida := v->>'nombre'; exit; end if;
          end if;
        end loop;
        elegida := coalesce(elegida, 'base');
        insert into public.imperio_asignaciones (user_id, clave, variante) values (uid, f.clave, elegida)
          on conflict (user_id, clave) do nothing;
        -- Si otra llamada ganó la carrera, manda la que quedó anotada.
        select a.variante into elegida from public.imperio_asignaciones a where a.user_id = uid and a.clave = f.clave;
      end if;
      -- Variante que ya no existe en la lista o 'base': valor de todos.
      select x->'valor' into v from jsonb_array_elements(f.variantes) as t(x)
       where jsonb_typeof(x) = 'object' and x->>'nombre' = elegida and x ? 'valor' limit 1;
      if v is not null then valor := v; end if;
      v := null;
    end if;
    salida := salida || jsonb_build_object(f.clave, jsonb_build_object('valor', valor, 'variante', elegida));
  end loop;
  return salida;
end $$;

-- Los mismos valores que los defaults del código (catalogo.dart, motor.dart, flags.dart).
insert into public.imperio_flags (clave, valor, nota) values
  ('imperio_activo', 'true', 'Apaga la pestaña Imperio'),
  ('dorado_intervalo_min', '[5, 15]', 'Minutos activos entre mojones dorados (mínimo, máximo), sin Imán'),
  ('offline_porcentaje', '0.25', 'Parte del MJ/s que cuenta offline sin válvulas'),
  ('offline_tope_h', '2', 'Horas de tope offline sin tanques'),
  ('precio_crecimiento', '1.15', 'Cada unidad de un edificio cuesta esto por la anterior'),
  ('precio_guantes', '100', 'Precio de Guantes de látex'),
  ('precio_faja', '500', 'Precio de Faja de pujo'),
  ('cagada_bono_pct', '2', 'Producción extra por cagada real hasta 150 (en %)');

revoke all on function public.imperio_registrar(jsonb) from public, anon;
revoke all on function public.imperio_flags_mias() from public, anon;
revoke all on function public.imperio_limpiar_eventos(int) from public, anon;
grant execute on function public.imperio_registrar(jsonb) to authenticated;
grant execute on function public.imperio_flags_mias() to authenticated;
-- Comprueba es_admin() adentro.
grant execute on function public.imperio_limpiar_eventos(int) to authenticated;
