-- Reinicios y versión mínima con candado en el servidor, para no depender de acordarse del orden.
--
-- 1. Reinicio pendiente: en vez de reiniciar a mano, se anota una fila en imperio_reinicios_pendientes con el
--    build que trae el arreglo. El cron lo aplica solo cuando se cumplen las tres:
--      a) Play ya sirve ese build (flag build_play, se sube a mano cuando la consola lo muestra en vivo),
--      b) el jugador ya juega con ese build o uno mayor (último evento de imperio_eventos),
--      c) el jugador no tiene la app abierta (sin guardados ni eventos en los últimos 3 minutos).
--    Así la app vieja no puede volver a subir la partida de antes ni jugar con el exploit sin arreglar.
--    Al aplicarlo guarda la fila vieja en `respaldo` y sube las jaladas en 1 (columna y estado).
--
-- 2. version_minima no puede pasar de build_play: si no, los de Play quedan bloqueados sin poder actualizar.

create table if not exists public.imperio_reinicios_pendientes (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  build_minimo int not null,
  motivo text not null,
  creado timestamptz not null default now(),
  aplicado timestamptz,
  respaldo jsonb
);
create index if not exists imperio_reinicios_pendientes_abiertos on public.imperio_reinicios_pendientes (user_id) where aplicado is null;
alter table public.imperio_reinicios_pendientes enable row level security;
revoke all on public.imperio_reinicios_pendientes from anon, authenticated;

-- Build que Play ya sirve. Inactiva para que no viaje a las apps (imperio_flags_mias solo manda las activas).
insert into public.imperio_flags (clave, valor, activo, nota)
values ('build_play', '61'::jsonb, false, 'Build en vivo en Play. Subirlo SOLO cuando la consola lo muestre disponible.')
on conflict (clave) do nothing;

create or replace function public.imperio_build_play() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select (valor #>> '{}')::int from public.imperio_flags where clave = 'build_play' and jsonb_typeof(valor) = 'number'), 0)
$$;

create or replace function public.imperio_flags_candado() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.clave = 'version_minima' and new.activo and jsonb_typeof(new.valor) = 'number'
     and (new.valor #>> '{}')::numeric > public.imperio_build_play() then
    raise exception 'version_minima % es mayor que build_play %: los de Play quedarían bloqueados. Espera a que Play la apruebe y sube build_play primero.',
      new.valor #>> '{}', public.imperio_build_play();
  end if;
  return new;
end $$;

drop trigger if exists imperio_flags_candado on public.imperio_flags;
create trigger imperio_flags_candado before insert or update on public.imperio_flags
  for each row execute function public.imperio_flags_candado();

-- Build con el que juega cada uno, sacado de version_app ('2.14.0+62' → 62).
create or replace function public.imperio_build_de(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(max(nullif(split_part(e.version_app, '+', 2), '')::int), 0)
  from public.imperio_eventos e
  where e.user_id = p_user and e.creado > now() - interval '3 days' and e.version_app ~ '\+\d+$'
$$;

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
           jalada_en = now(), guardado = now()
     where user_id = r.user_id;
    update public.imperio_reinicios_pendientes set aplicado = now(), respaldo = to_jsonb(fila) where id = r.id;
    hechos := hechos + 1;
  end loop;
  return hechos;
end $$;

revoke execute on function public.imperio_reinicios_aplicar() from public, anon, authenticated;
revoke execute on function public.imperio_build_de(uuid) from public, anon, authenticated;

select cron.schedule('imperio_reinicios', '*/5 * * * *', 'select public.imperio_reinicios_aplicar()');
