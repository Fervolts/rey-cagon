-- Imperio: modo idle. Una fila por usuario; todas las escrituras van por RPC.
-- Se ajusta con otra migración el día que salga.
create function public.imperio_lanzamiento() returns timestamptz
language sql immutable as $$ select '2026-11-15 00:00:00-04'::timestamptz $$;

-- Borrar cuenta: la fila cae en cascada (profiles -> auth.users), no hace falta tocar borrar_mi_cuenta.
create table public.imperio (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  estado jsonb not null default '{}',
  mj_total double precision not null default 0,
  mps double precision not null default 0,
  fichas int not null default 0 check (fichas between 0 and 5),
  fundador boolean not null default false,
  cagadas_hasta timestamptz not null default now(),
  creado timestamptz not null default now(),
  guardado timestamptz not null default now()
);

alter table public.imperio enable row level security;
create policy "imperio_read_own" on public.imperio for select to authenticated
  using ((select auth.uid()) = user_id);

-- Carga (o crea) el imperio y suma fichas por las cagadas nuevas desde la última carga.
create function public.imperio_cargar() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  total int;
  guardado_previo timestamptz;
  nuevas jsonb := '[]'::jsonb;
  cuenta int := 0;
  es_nuevo boolean := false;
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
    update public.imperio
      set fichas = least(5, fichas + cuenta), cagadas_hasta = now()
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
    'ahora', now()
  );
end $$;

-- Guarda el progreso con un tope simple contra trampas (juego entre panas).
create function public.imperio_guardar(p_estado jsonb, p_mj_total double precision, p_mps double precision)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  seg double precision;
  permitido double precision;
  nuevo_total double precision;
  nuevo_mps double precision := greatest(coalesce(p_mps, 0), 0);
  recortado boolean := false;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  if p_estado is null or pg_column_size(p_estado) > 65536 then
    raise exception 'estado demasiado grande';
  end if;

  select * into fila from public.imperio where user_id = uid for update;
  if not found then raise exception 'imperio no existe'; end if;

  seg := extract(epoch from now() - fila.guardado);
  permitido := fila.mj_total + (seg + 7200) * greatest(fila.mps, nuevo_mps, 1) * 30 + 100000;
  nuevo_total := least(greatest(coalesce(p_mj_total, 0), fila.mj_total), permitido);
  if coalesce(p_mj_total, 0) > nuevo_total then recortado := true; end if;

  update public.imperio
    set estado = p_estado, mj_total = nuevo_total, mps = nuevo_mps, guardado = now()
    where user_id = uid;

  return jsonb_build_object('mj_total', nuevo_total, 'recortado', recortado, 'guardado', now());
end $$;

-- Gasta una ficha; -1 si no había.
create function public.imperio_usar_ficha() returns int
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  quedan int;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  update public.imperio set fichas = fichas - 1
    where user_id = uid and fichas > 0
    returning fichas into quedan;
  return coalesce(quedan, -1);
end $$;

revoke all on function public.imperio_cargar() from public, anon;
revoke all on function public.imperio_guardar(jsonb, double precision, double precision) from public, anon;
revoke all on function public.imperio_usar_ficha() from public, anon;
grant execute on function public.imperio_cargar() to authenticated;
grant execute on function public.imperio_guardar(jsonb, double precision, double precision) to authenticated;
grant execute on function public.imperio_usar_ficha() to authenticated;
