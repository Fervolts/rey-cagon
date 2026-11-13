-- imperio_zona validaba la zona contra pg_timezone_names, que lee todos los
-- archivos de zonas en cada llamada (~60 ms). imperio_cadena la llama 3 veces,
-- imperio_cofre e imperio_progreso también. Ahora se valida probando la zona.

create or replace function public.zona_valida(p_zona text)
returns boolean
language plpgsql
immutable
set search_path to ''
as $$
begin
  if p_zona is null or p_zona = '' then return false; end if;
  perform now() at time zone p_zona;
  return true;
exception when others then
  return false;
end;
$$;

create or replace function public.imperio_zona(p_uid uuid)
returns text
language sql
stable
set search_path to ''
as $$
  select coalesce(
    (select case when public.zona_valida(t.zona) then t.zona end
       from public.push_tokens t
      where t.user_id = p_uid
      order by t.updated_at desc
      limit 1),
    'America/Caracas')
$$;
