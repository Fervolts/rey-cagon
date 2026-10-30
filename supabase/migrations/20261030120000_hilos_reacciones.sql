-- Hilos y reacciones en el chat (salas públicas y soporte).
--
-- Hilos: una respuesta es un mensaje normal con `responde_a` = id del mensaje padre. Las apps nuevas
-- no las muestran en el flujo de la sala sino dentro del hilo; las apps viejas no filtran la columna
-- y las ven como mensajes sueltos (aceptado: no se rompe nada). Un solo nivel: no se responde a una
-- respuesta. Distinto de `hilo` (el usuario dueño de una conversación de soporte) y de la RPC
-- hilos_soporte, que no cambian.
--
-- Reacciones: unos pocos emojis por mensaje; cada persona puede poner varios distintos, uno de cada.

alter table public.mensajes
  add column responde_a bigint references public.mensajes (id) on delete cascade;
create index on public.mensajes (responde_a, id) where responde_a is not null;
-- La columna no se puede cambiar después: las políticas y los grants de update siguen igual
-- (authenticated solo puede actualizar oculto y fijado_hasta).

-- Validación del hilo. Corre con los permisos de quien escribe: si no puede ver el padre (bloqueo,
-- oculto, otra conversación de soporte), para él no existe.
create function public.validar_hilo()
returns trigger language plpgsql set search_path = '' as $$
declare
  padre record;
begin
  if new.responde_a is null then return new; end if;
  select m.sala, m.hilo, m.responde_a into padre from public.mensajes m where m.id = new.responde_a;
  if not found then
    raise exception 'Ese mensaje ya no existe' using errcode = 'P0001';
  end if;
  if padre.responde_a is not null then
    raise exception 'No se puede responder a una respuesta' using errcode = 'P0001';
  end if;
  if padre.sala <> new.sala or padre.hilo is distinct from new.hilo then
    raise exception 'La respuesta tiene que ir en la misma sala' using errcode = 'P0001';
  end if;
  -- Un anuncio fijado es del flujo principal, no de un hilo.
  new.fijado_hasta := null;
  return new;
end;
$$;
create trigger mensajes_validar_hilo before insert on public.mensajes
  for each row execute function public.validar_hilo();

create table public.mensaje_reacciones (
  mensaje_id bigint not null references public.mensajes (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  -- Mismos emojis que _reaccionesRapidas en lib/chat.dart.
  emoji text not null check (emoji in ('💩', '😂', '🔥', '👑', '🤢', '💀')),
  created_at timestamptz not null default now(),
  primary key (mensaje_id, user_id, emoji)
);
create index on public.mensaje_reacciones (user_id);
alter table public.mensaje_reacciones enable row level security;

-- Leer: solo las de mensajes que puedes ver. El exists pasa por la política select de mensajes
-- (salas públicas, soporte, bloqueos, ocultos), así que si esa cambia, esta la sigue sola.
-- Tampoco se ven las reacciones de alguien bloqueado en cualquier sentido.
create policy mensaje_reacciones_select on public.mensaje_reacciones for select to authenticated using (
  exists (select 1 from public.mensajes m where m.id = mensaje_id)
  and not public.hay_bloqueo(user_id)
);
create policy mensaje_reacciones_insert on public.mensaje_reacciones for insert to authenticated with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.mensajes m where m.id = mensaje_id)
);
create policy mensaje_reacciones_delete on public.mensaje_reacciones for delete to authenticated using (
  user_id = (select auth.uid())
);
revoke update on public.mensaje_reacciones from authenticated, anon;
revoke all on public.mensaje_reacciones from anon;

-- La fecha la pone el servidor.
create function public.reaccion_ahora()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.created_at := now();
  return new;
end;
$$;
create trigger mensaje_reacciones_ahora before insert on public.mensaje_reacciones
  for each row execute function public.reaccion_ahora();

-- Realtime. Con RLS, los borrados llegan solo con la llave primaria, que aquí trae todo
-- (mensaje_id, user_id, emoji): alcanza para quitar la reacción en pantalla.
alter publication supabase_realtime add table public.mensaje_reacciones;
