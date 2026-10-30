-- HEXA POOP: 6 cagadas en un día (hora de Caracas). Queda como hazaña para que todos los
-- teléfonos la vean al abrir la app (lib/nuclear.dart). La tarjeta del chat ya sale sola:
-- validar_mensaje guarda n = racha_del_dia y el cliente la nombra con nombreRacha(n).

create table if not exists public.hazanas (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  tipo text not null check (tipo in ('hexa')),
  n int not null,
  dia date not null,
  created_at timestamptz not null default now(),
  unique (user_id, tipo, dia)
);
create index if not exists hazanas_created_idx on public.hazanas (created_at desc);

-- Solo se leen. Las escribe el trigger; el cliente no puede inventarse una.
alter table public.hazanas enable row level security;
revoke insert, update, delete on public.hazanas from anon, authenticated;
grant select on public.hazanas to authenticated;
drop policy if exists hazanas_leer on public.hazanas;
-- Si tú bloqueaste a esa persona o ella a ti, su alerta no te llega.
create policy hazanas_leer on public.hazanas for select to authenticated
  using (not public.hay_bloqueo(user_id));

create or replace function public.registrar_hazana()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cuantas int;
  el_dia date;
begin
  begin
    if tg_op = 'DELETE' then
      -- Deshacer la sexta se lleva la hazaña; si quedan 6 o más, solo baja el número.
      el_dia := (old.created_at at time zone 'America/Caracas')::date;
      select count(*)::int into cuantas from public.cagadas x
        where x.user_id = old.user_id
          and x.created_at >= el_dia::timestamp at time zone 'America/Caracas'
          and x.created_at < (el_dia + 1)::timestamp at time zone 'America/Caracas';
      if cuantas < 6 then
        delete from public.hazanas h where h.user_id = old.user_id and h.tipo = 'hexa' and h.dia = el_dia;
      else
        update public.hazanas h set n = cuantas where h.user_id = old.user_id and h.tipo = 'hexa' and h.dia = el_dia;
      end if;
      return null;
    end if;
    cuantas := public.racha_del_dia(new);
    if cuantas >= 6 then
      insert into public.hazanas (user_id, tipo, n, dia, created_at)
      values (new.user_id, 'hexa', cuantas, (new.created_at at time zone 'America/Caracas')::date, new.created_at)
      on conflict (user_id, tipo, dia) do update set n = greatest(public.hazanas.n, excluded.n);
    end if;
  exception when others then
    -- Que la hazaña falle no puede tumbar la cagada.
    null;
  end;
  return null;
end;
$$;
revoke execute on function public.registrar_hazana() from public, anon, authenticated;

drop trigger if exists cagadas_hazana on public.cagadas;
create trigger cagadas_hazana after insert or delete on public.cagadas
  for each row execute function public.registrar_hazana();

-- Las de los últimos días que ya pasaron antes de esta migración, para que también exploten.
insert into public.hazanas (user_id, tipo, n, dia, created_at)
select c.user_id, 'hexa', count(*)::int, (c.created_at at time zone 'America/Caracas')::date, max(c.created_at)
from public.cagadas c
where c.created_at >= ((now() at time zone 'America/Caracas')::date - 2)::timestamp at time zone 'America/Caracas'
group by c.user_id, (c.created_at at time zone 'America/Caracas')::date
having count(*) >= 6
on conflict (user_id, tipo, dia) do nothing;
