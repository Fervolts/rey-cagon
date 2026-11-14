-- Números del TRONO nuevo: días seguidos cagando (racha_dias, la misma del muro) y cagadas de los últimos 7 días.
create function public.trono_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'no_autenticado'; end if;
  return jsonb_build_object(
    'racha', public.racha_dias(uid),
    'semana', (select count(*) from public.cagadas c where c.user_id = uid and c.created_at >= now() - interval '7 days'));
end;
$$;
revoke all on function public.trono_resumen() from public, anon;
grant execute on function public.trono_resumen() to authenticated;
