-- Premios exclusivos: accesorios que no se desbloquean con cagadas. Los da el servidor (por ejemplo a quien llegó
-- lejos en el Imperio antes de un reinicio). Cada uno solo lo puede poner quien lo tiene en `premios`.

create table if not exists public.premios (
  user_id uuid not null references auth.users (id) on delete cascade,
  ranura text not null,
  emoji text not null,
  motivo text not null,
  creado timestamptz not null default now(),
  primary key (user_id, ranura, emoji)
);
alter table public.premios enable row level security;
-- Cada quien ve solo los suyos. Nadie escribe desde la app.
drop policy if exists premios_mios on public.premios;
create policy premios_mios on public.premios for select to authenticated using (user_id = (select auth.uid()));
grant select on public.premios to authenticated;

alter table public.desbloqueos add column if not exists exclusivo boolean not null default false;
insert into public.desbloqueos (ranura, emoji, minimo, exclusivo) values
  ('mascota', '🪙', 1, true),
  ('mascota', '🪠', 1, true),
  ('sombrero', '👑', 1, true)
on conflict (ranura, emoji) do update set exclusivo = true;

create or replace function public.validar_desbloqueos()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  total bigint;
  r text;
  v text;
  antes text;
begin
  select count(*) into total from public.cagadas where user_id = new.id;
  foreach r in array array['avatar', 'sombrero', 'lentes', 'mascota'] loop
    v := case r when 'avatar' then new.avatar when 'sombrero' then new.sombrero
                when 'lentes' then new.lentes else new.mascota end;
    antes := case r when 'avatar' then old.avatar when 'sombrero' then old.sombrero
                    when 'lentes' then old.lentes else old.mascota end;
    -- Solo se valida lo que cambió: si deshaces cagadas no pierdes lo que ya tenías puesto.
    if v is null or v is not distinct from antes then continue; end if;
    if r <> 'avatar' and not exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v) then
      raise exception 'Accesorio desconocido' using errcode = '23514';
    end if;
    if exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v and d.exclusivo)
       and not exists (select 1 from public.premios pr where pr.user_id = new.id and pr.ranura = r and pr.emoji = v) then
      raise exception 'Eso es un premio exclusivo' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v and d.minimo > total) then
      raise exception 'Todavía no has desbloqueado eso' using errcode = 'P0001';
    end if;
  end loop;
  return new;
end;
$function$;
