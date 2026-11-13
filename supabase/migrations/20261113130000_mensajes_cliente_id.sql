-- Id que pone la app al mandar un mensaje: si un reintento por red llega dos veces, la base guarda uno solo.
-- Las apps viejas no lo mandan (queda null) y siguen igual.
alter table public.mensajes add column if not exists cliente_id uuid;
create unique index if not exists mensajes_cliente_id_idx on public.mensajes (cliente_id) where cliente_id is not null;
