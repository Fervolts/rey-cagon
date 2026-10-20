-- Borrar la cuenta desde la app (Google Play lo exige). Al borrar el usuario de auth se van en
-- cascada el perfil, las cagadas, los follows y los teléfonos registrados.
create function public.borrar_mi_cuenta() returns void
language sql security definer set search_path = ''
as $$
  delete from auth.users where id = (select auth.uid());
$$;
revoke execute on function public.borrar_mi_cuenta() from public, anon;
grant execute on function public.borrar_mi_cuenta() to authenticated;
