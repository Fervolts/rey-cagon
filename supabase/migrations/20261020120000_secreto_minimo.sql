-- El secreto de Tips pide 10 cagadas. Early birds: las cuentas creadas antes del 20 de
-- octubre de 2026 (hora de Venezuela) lo tienen desde el principio.
create function public.validar_secreto() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.placer_desbloqueado and not old.placer_desbloqueado
     and new.cagadas < 10
     and new.created_at >= '2026-10-20 00:00:00-04'::timestamptz then
    raise exception 'Todavía no' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.validar_secreto() from public, anon, authenticated;

create trigger validar_secreto before update of placer_desbloqueado on public.profiles
  for each row execute function public.validar_secreto();
