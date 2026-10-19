-- Antispam: máximo una cagada por hora por usuario. La hora la pone el servidor (no se puede retrofechar).
create or replace function public.limitar_cagadas()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ultima timestamptz;
begin
  new.created_at := now();
  -- Serializa inserts simultáneos del mismo usuario para que dos taps rápidos no pasen los dos.
  perform pg_advisory_xact_lock(hashtext(new.user_id::text));
  select max(created_at) into ultima from public.cagadas where user_id = new.user_id;
  if ultima is not null and ultima > now() - interval '1 hour' then
    raise exception 'Calma, rey: solo una por hora. Espera % min más.',
      ceil(extract(epoch from (ultima + interval '1 hour' - now())) / 60)::int
      using errcode = 'P0001', hint = 'limite_hora';
  end if;
  return new;
end;
$$;

create trigger cagadas_limite_hora
  before insert on public.cagadas
  for each row execute function public.limitar_cagadas();
